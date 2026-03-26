//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

public protocol ApiClientType {
    func sendRequest(_ request: any Request) async throws -> Response
}

public class ApiClient: ApiClientType, @unchecked Sendable {
    private let session: URLSession
    private let environment: AppEnvironment
    private let interceptors: [NetworkInterceptor]
    private let chain: InterceptorChain
    private let maxRetryCount: Int

    public init(
        configuration: URLSessionConfiguration = .default,
        environment: AppEnvironment,
        interceptors: [NetworkInterceptor],
        maxRetryCount: Int = 2
    ) {
        self.session = URLSession(configuration: configuration)
        self.environment = environment
        self.interceptors = interceptors
        self.chain = InterceptorChain(interceptors: interceptors)
        self.maxRetryCount = maxRetryCount
    }

    public func sendRequest(_ request: any Request) async throws -> Response {
        let networkTask = makeTask(for: request)
        return try await networkTask.value
    }

    public func request(_ request: any Request) -> NetworkTask {
        makeTask(for: request)
    }

    private func makeTask(for request: any Request) -> NetworkTask {
        let task = Task<Response, Error> {
            try await executeWithRetry(request)
        }
        return NetworkTask(task: task)
    }

    // MARK: - Retry loop

    private func executeWithRetry(_ request: any Request) async throws -> Response {
        let builder = RequestBuilder(request: request)
        let baseRequest = builder.build(environment)
        var retryCount = 0

        while true {
            try Task.checkCancellation()

            // 1. onRequest interceptor chain
            let requestResult = await chain.executeOnRequest(baseRequest)
            let urlRequest: URLRequest
            switch requestResult {
            case .next(let req):
                urlRequest = req
            case .reject(let error):
                throw error
            }

            try Task.checkCancellation()
            let responseData: (Data, URLResponse)
            do {
                responseData = try await session.data(for: urlRequest)
            } catch {
                if error is CancellationError { throw error }
                throw AppNetworkError.networkError(
                    debugDescription: error.localizedDescription,
                    errorCode: (error as? URLError)?.code
                )
            }

            guard let httpResponse = responseData.1 as? HTTPURLResponse else {
                throw AppNetworkError.dataError(debugDescription: "Data error")
            }
            let statusCode = httpResponse.statusCode
            print("[ApiClient]:\(request.endPoint.absoluteUrl(.dev)) - statusCode: \(statusCode)")

            // 3. Handle response based on status code
            switch statusCode {
            case 200..<300:
                let response = Response(statusCode: statusCode, data: responseData.0)
                // Run onResponse interceptor chain
                let responseResult = await chain.executeOnResponse(response)
                switch responseResult {
                case .next(let res):
                    return res
                case .reject(let error):
                    throw error
                }
            default:
                let error = AppNetworkError.httpError(
                    statusCode: HttpErrorCode(rawValue: statusCode) ?? .badRequest,
                    body: responseData.0
                )
                // 4. onError interceptor chain
                let errorResult = await chain.executeOnError(error, request: urlRequest)
                switch errorResult {
                case .next(let finalError):
                    throw finalError
                case .retry:
                    retryCount += 1
                    if retryCount >= maxRetryCount {
                        throw error
                    }
                    continue
                }
            }
        }
    }

    public func sendSSERequest<T: Codable>(_ request: any Request) -> (stream: AsyncThrowingStream<T, any Error>, task: NetworkTask) where T: Sendable {
        var streamContinuation: AsyncThrowingStream<T, any Error>.Continuation?
        let stream = AsyncThrowingStream<T, any Error> { continuation in
            streamContinuation = continuation
        }

        let sseTask = Task<Response, Error> {
            guard let continuation = streamContinuation else {
                throw CancellationError()
            }

            let builder = RequestBuilder(request: request)
            var urlRequest = builder.build(self.environment)
            urlRequest.timeoutInterval = .infinity
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            // Use InterceptorChain instead of manual iteration
            let requestResult = await self.chain.executeOnRequest(urlRequest)
            switch requestResult {
            case .next(let modified):
                urlRequest = modified
            case .reject(let error):
                continuation.finish(throwing: error)
                throw error
            }

            do {
                try Task.checkCancellation()
                let bytes = try await self.session.bytes(for: urlRequest)
                guard let httpResponse = bytes.1 as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let error = URLError(.badServerResponse)
                    continuation.finish(throwing: error)
                    throw error
                }
                for try await line in bytes.0.lines {
                    try Task.checkCancellation()
                    if line.hasPrefix("data:") {
                        let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        print("SSE:\(jsonString)")

                        if let data = jsonString.data(using: .utf8) {
                            if let jsonData = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let dataStr = jsonData["data"] as? [String: Any] {
                                let data = try JSONSerialization.data(withJSONObject: dataStr)
                                let reponse = try JSONDecoder().decode(T.self, from: data)
                                continuation.yield(reponse)
                            }
                        }
                    }
                }
                print("SSE: finish")
                continuation.finish()
            } catch {
                print("SSE ERROR: \(error)")
                continuation.finish(throwing: error)
                throw error
            }

            // Return a placeholder response — callers use the stream, not this value
            return Response(statusCode: 200, data: Data())
        }

        let networkTask = NetworkTask(task: sseTask)
        return (stream: stream, task: networkTask)
    }
}
