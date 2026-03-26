//
//  LTApp, This code is protected by intellectual property rights.
//

import XCTest
@testable import LTNetwork
// MARK: - Default Interceptor (no overrides)

/// A struct that conforms to `NetworkInterceptor` without overriding any methods.
/// All three lifecycle methods use the protocol's default implementation (pass-through).
private struct DefaultInterceptor: NetworkInterceptor {}

// MARK: - Property 5: 默认拦截器透传

/// **Feature: network-apiclient-optimization, Property 5: 默认拦截器透传**
/// **Validates: Requirements 3.5**
///
/// *For any* `NetworkInterceptor` that uses only default implementations (no overrides),
/// requests, responses, and errors should pass through unchanged.
///
/// This test generates random `URLRequest`, `Response`, and `Error` values across 100+
/// iterations and verifies that the default interceptor returns them unmodified.
final class DefaultInterceptorPassThroughTests: XCTestCase {

    private let interceptor = DefaultInterceptor()
    private let iterations = 100

    // MARK: - Helpers

    /// Generate a random URLRequest with random URL, HTTP method, headers, and body.
    private func randomURLRequest() -> URLRequest {
        let paths = (0..<Int.random(in: 1...5)).map { _ in
            String((0..<Int.random(in: 3...10)).map { _ in
                "abcdefghijklmnopqrstuvwxyz".randomElement()!
            })
        }
        let urlString = "https://\(paths.first ?? "api").example.com/\(paths.dropFirst().joined(separator: "/"))"
        var request = URLRequest(url: URL(string: urlString)!)

        let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
        request.httpMethod = methods.randomElement()!

        // Random headers
        let headerCount = Int.random(in: 0...5)
        for _ in 0..<headerCount {
            let key = "X-Custom-\(UUID().uuidString.prefix(8))"
            let value = UUID().uuidString
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Random body (50% chance)
        if Bool.random() {
            let bodySize = Int.random(in: 1...256)
            var bodyData = Data(count: bodySize)
            for i in 0..<bodySize {
                bodyData[i] = UInt8.random(in: 0...255)
            }
            request.httpBody = bodyData
        }

        // Random timeout
        request.timeoutInterval = TimeInterval.random(in: 5...120)

        return request
    }

    /// Generate a random Response with random status code and data.
    private func randomResponse() -> Response {
        let statusCode = Int.random(in: 100...599)
        let dataSize = Int.random(in: 0...512)
        let data: Data? = dataSize > 0 ? Data((0..<dataSize).map { _ in UInt8.random(in: 0...255) }) : nil
        return Response(statusCode: statusCode, data: data)
    }

    /// Generate a random Error.
    private func randomError() -> NSError {
        let domains = ["NSURLErrorDomain", "TestDomain", "AppError", "NetworkError", "CustomDomain"]
        let domain = domains.randomElement()!
        let code = Int.random(in: -1099 ... 999)
        let description = "Random error \(UUID().uuidString.prefix(8))"
        return NSError(domain: domain, code: code, userInfo: [
            NSLocalizedDescriptionKey: description
        ])
    }

    // MARK: - Property 5a: onRequest passes URLRequest through unchanged

    /// For any random URLRequest, the default interceptor's `onRequest` returns
    /// `.next(request)` with the exact same URLRequest.
    func testOnRequestPassesThrough() async {
        let handler = RequestInterceptorHandler()

        for i in 0..<iterations {
            let request = randomURLRequest()
            let result = await interceptor.onRequest(request, handler: handler)

            switch result {
            case .next(let passedRequest):
                XCTAssertEqual(passedRequest.url, request.url,
                               "Iteration \(i): URL must be unchanged")
                XCTAssertEqual(passedRequest.httpMethod, request.httpMethod,
                               "Iteration \(i): HTTP method must be unchanged")
                XCTAssertEqual(passedRequest.allHTTPHeaderFields, request.allHTTPHeaderFields,
                               "Iteration \(i): Headers must be unchanged")
                XCTAssertEqual(passedRequest.httpBody, request.httpBody,
                               "Iteration \(i): Body must be unchanged")
                XCTAssertEqual(passedRequest.timeoutInterval, request.timeoutInterval,
                               "Iteration \(i): Timeout must be unchanged")
            case .reject(let error):
                XCTFail("Iteration \(i): Default onRequest must not reject. Got error: \(error)")
            }
        }
    }

    // MARK: - Property 5b: onResponse passes Response through unchanged

    /// For any random Response, the default interceptor's `onResponse` returns
    /// `.next(response)` with the exact same statusCode and data.
    func testOnResponsePassesThrough() async {
        let handler = ResponseInterceptorHandler()

        for i in 0..<iterations {
            let response = randomResponse()
            let result = await interceptor.onResponse(response, handler: handler)

            switch result {
            case .next(let passedResponse):
                XCTAssertEqual(passedResponse.statusCode, response.statusCode,
                               "Iteration \(i): statusCode must be unchanged")
                XCTAssertEqual(passedResponse.data, response.data,
                               "Iteration \(i): data must be unchanged")
            case .reject(let error):
                XCTFail("Iteration \(i): Default onResponse must not reject. Got error: \(error)")
            }
        }
    }

    // MARK: - Property 5c: onError passes Error through unchanged

    /// For any random Error, the default interceptor's `onError` returns
    /// `.next(error)` with the exact same error (domain, code, userInfo).
    func testOnErrorPassesThrough() async {
        let handler = ErrorInterceptorHandler()

        for i in 0..<iterations {
            let error = randomError()
            let dummyRequest = randomURLRequest()
            let result = await interceptor.onError(error, request: dummyRequest, handler: handler)

            switch result {
            case .next(let passedError):
                let passedNSError = passedError as NSError
                XCTAssertEqual(passedNSError.domain, error.domain,
                               "Iteration \(i): Error domain must be unchanged")
                XCTAssertEqual(passedNSError.code, error.code,
                               "Iteration \(i): Error code must be unchanged")
                XCTAssertEqual(
                    passedNSError.localizedDescription, error.localizedDescription,
                    "Iteration \(i): Error description must be unchanged"
                )
            case .retry:
                XCTFail("Iteration \(i): Default onError must not retry")
            }
        }
    }
}
