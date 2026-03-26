//
//  LTApp, This code is protected by intellectual property rights.
//

import XCTest
@testable import LTNetwork

// MARK: - Mock URLProtocol

/// A custom URLProtocol that intercepts all requests and returns configurable responses.
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    /// Tracks how many times a request was actually sent to the network layer.
    nonisolated(unsafe) static var requestCount = 0
    private static let lock = NSLock()

    static func resetRequestCount() {
        lock.lock()
        requestCount = 0
        lock.unlock()
    }

    static func incrementRequestCount() {
        lock.lock()
        requestCount += 1
        lock.unlock()
    }

    static func currentRequestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.incrementRequestCount()
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Mock Request

private struct MockEndPoint: EndPoint {
    let path: String
    func absoluteUrl(_ environment: AppEnvironment) -> URL {
        URL(string: "https://api.example.com/\(path)")!
    }
}

private struct MockRequest: Request {
    var endPoint: EndPoint { MockEndPoint(path: path) }
    var method: HttpMethod = .get
    var payload: HttpPayload = .empty
    var path: String = "test"
}

// MARK: - Test Interceptors

private actor CallCountingInterceptor: NetworkInterceptor {
    private var _onRequestCount = 0

    var onRequestCount: Int { _onRequestCount }

    func onRequest(_ request: URLRequest, handler: RequestInterceptorHandler) async -> RequestInterceptorResult {
        _onRequestCount += 1
        return handler.next(request)
    }
}

private struct AlwaysRetryInterceptor: NetworkInterceptor {
    func onError(_ error: Error, request: URLRequest, handler: ErrorInterceptorHandler) async -> ErrorInterceptorResult {
        handler.retry()
    }
}

private struct RejectOnRequestInterceptor: NetworkInterceptor {
    let rejectError: Error
    func onRequest(_ request: URLRequest, handler: RequestInterceptorHandler) async -> RequestInterceptorResult {
        handler.reject(rejectError)
    }
}

// MARK: - Helper

private func makeApiClient(
    interceptors: [NetworkInterceptor] = [],
    maxRetryCount: Int = 2
) -> ApiClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return ApiClient(
        configuration: config,
        environment: .dev,
        interceptors: interceptors,
        maxRetryCount: maxRetryCount
    )
}

private func mockHTTPResponse(statusCode: Int, data: Data = Data()) {
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, data)
    }
}


// MARK: - Property 2: sendRequest 与 NetworkTask.value 等价

/// **Feature: network-apiclient-optimization, Property 2: sendRequest 与 NetworkTask.value 等价**
/// **Validates: Requirements 1.4**
final class ApiClientSendRequestEquivalenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.resetRequestCount()
    }

    func testSendRequestReturnsSuccessResponse() async throws {
        let responseData = Data("{\"success\":true}".utf8)
        mockHTTPResponse(statusCode: 200, data: responseData)
        let client = makeApiClient()

        let response = try await client.sendRequest(MockRequest())

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.data, responseData)
    }

    func testNetworkTaskValueReturnsSuccessResponse() async throws {
        let responseData = Data("{\"success\":true}".utf8)
        mockHTTPResponse(statusCode: 200, data: responseData)
        let client = makeApiClient()

        let task = client.request(MockRequest())
        let response = try await task.value

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.data, responseData)
    }

    func testSendRequestAndNetworkTaskValueProduceSameResult() async throws {
        let responseData = Data("{\"key\":\"value\"}".utf8)
        mockHTTPResponse(statusCode: 200, data: responseData)
        let client = makeApiClient()

        let sendResult = try await client.sendRequest(MockRequest())
        let taskResult = try await client.request(MockRequest()).value

        XCTAssertEqual(sendResult.statusCode, taskResult.statusCode)
        XCTAssertEqual(sendResult.data, taskResult.data)
    }
}

// MARK: - Property 3: 重试次数受最大上限约束

/// **Feature: network-apiclient-optimization, Property 3: 重试次数受最大上限约束**
/// **Validates: Requirements 2.2, 2.4**
final class ApiClientRetryLimitTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.resetRequestCount()
    }

    func testRetryCountBoundedByMaxRetryCount() async {
        let maxRetry = 3
        mockHTTPResponse(statusCode: 401) // Always 401
        let client = makeApiClient(
            interceptors: [AlwaysRetryInterceptor()],
            maxRetryCount: maxRetry
        )

        do {
            _ = try await client.sendRequest(MockRequest())
            XCTFail("Expected error")
        } catch {
            // Implementation: retryCount increments after each retry, throws when retryCount >= maxRetryCount.
            // So total calls = 1 initial + (maxRetry - 1) retries before hitting the limit on the last one = maxRetry.
            // Trace: call#1 → retry(count=1) → call#2 → retry(count=2) → call#3 → retry(count=3 >= 3) → throw
            XCTAssertEqual(
                MockURLProtocol.currentRequestCount(), maxRetry,
                "Expected \(maxRetry) total network calls"
            )
        }
    }

    func testRetryExhaustedThrowsLastError() async {
        mockHTTPResponse(statusCode: 401)
        let client = makeApiClient(
            interceptors: [AlwaysRetryInterceptor()],
            maxRetryCount: 1
        )

        do {
            _ = try await client.sendRequest(MockRequest())
            XCTFail("Expected error")
        } catch let error as AppNetworkError {
            if case .httpError(statusCode: .unauthorized, _) = error {
                // expected — last error is the 401
            } else {
                XCTFail("Expected unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Expected AppNetworkError, got \(error)")
        }
    }

    func testMaxRetryCountZeroMeansNoRetries() async {
        mockHTTPResponse(statusCode: 500)
        let client = makeApiClient(
            interceptors: [AlwaysRetryInterceptor()],
            maxRetryCount: 0
        )

        do {
            _ = try await client.sendRequest(MockRequest())
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(MockURLProtocol.currentRequestCount(), 1,
                           "With maxRetryCount=0, only 1 request should be made")
        }
    }
}

// MARK: - Property 4: 重试时重新执行 onRequest 拦截器链

/// **Feature: network-apiclient-optimization, Property 4: 重试时重新执行 onRequest 拦截器链**
/// **Validates: Requirements 2.3, 2.6, 3.8**
final class ApiClientRetryReExecutesOnRequestTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.resetRequestCount()
    }

    func testOnRequestCalledOnEachRetry() async {
        let maxRetry = 2
        mockHTTPResponse(statusCode: 401)
        let counter = CallCountingInterceptor()
        let client = makeApiClient(
            interceptors: [counter, AlwaysRetryInterceptor()],
            maxRetryCount: maxRetry
        )

        _ = try? await client.sendRequest(MockRequest())

        // onRequest should be called once per attempt: maxRetry total calls
        let count = await counter.onRequestCount
        XCTAssertEqual(count, maxRetry,
                       "onRequest should be called \(maxRetry) times")
        XCTAssertEqual(MockURLProtocol.currentRequestCount(), maxRetry,
                       "Network requests should equal onRequest calls")
    }
}


// MARK: - Property 11: HTTP 状态码决定结果类型

/// **Feature: network-apiclient-optimization, Property 11: HTTP 状态码决定结果类型**
/// **Validates: Requirements 5.1, 5.2**
final class ApiClientStatusCodeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.resetRequestCount()
    }

    func testHTTP2xxReturnsResponse() async throws {
        let codes = [200, 201, 204, 299]
        for code in codes {
            let data = Data("status-\(code)".utf8)
            mockHTTPResponse(statusCode: code, data: data)
            let client = makeApiClient()

            let response = try await client.sendRequest(MockRequest())
            XCTAssertEqual(response.statusCode, code, "Expected statusCode \(code)")
            XCTAssertEqual(response.data, data)
        }
    }

    func testHTTPNon2xxThrowsHttpError() async {
        let codes = [400, 401, 403, 404, 500, 502, 503]
        for code in codes {
            mockHTTPResponse(statusCode: code, data: Data("err".utf8))
            let client = makeApiClient()

            do {
                _ = try await client.sendRequest(MockRequest())
                XCTFail("Expected error for status \(code)")
            } catch let error as AppNetworkError {
                if case .httpError(let statusCode, let body) = error {
                    XCTAssertEqual(statusCode.rawValue, code,
                                   "Expected status code \(code), got \(statusCode.rawValue)")
                    XCTAssertEqual(body, Data("err".utf8))
                } else {
                    XCTFail("Expected httpError for status \(code), got \(error)")
                }
            } catch {
                XCTFail("Expected AppNetworkError for status \(code), got \(error)")
            }
        }
    }
}

// MARK: - Property 12: 网络连接失败映射为 networkError

/// **Feature: network-apiclient-optimization, Property 12: 网络连接失败映射为 networkError**
/// **Validates: Requirements 5.3**
final class ApiClientNetworkErrorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.resetRequestCount()
    }

    func testURLErrorMappedToNetworkError() async {
        let urlErrorCodes: [URLError.Code] = [.timedOut, .notConnectedToInternet, .cannotFindHost, .networkConnectionLost]

        for code in urlErrorCodes {
            MockURLProtocol.requestHandler = { _ in
                throw URLError(code)
            }
            let client = makeApiClient()

            do {
                _ = try await client.sendRequest(MockRequest())
                XCTFail("Expected error for URLError code \(code.rawValue)")
            } catch let error as AppNetworkError {
                if case .networkError(_, let errorCode, _) = error {
                    XCTAssertEqual(errorCode, code,
                                   "Expected URLError code \(code.rawValue)")
                } else {
                    XCTFail("Expected networkError, got \(error)")
                }
            } catch {
                XCTFail("Expected AppNetworkError, got \(error)")
            }
        }
    }

    func testGenericNetworkErrorMappedToNetworkError() async {
        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: "TestDomain", code: 999, userInfo: [
                NSLocalizedDescriptionKey: "Something went wrong"
            ])
        }
        let client = makeApiClient()

        do {
            _ = try await client.sendRequest(MockRequest())
            XCTFail("Expected error")
        } catch let error as AppNetworkError {
            if case .networkError(let desc, let errorCode, _) = error {
                XCTAssertTrue(desc.contains("Something went wrong"))
                XCTAssertNil(errorCode, "Non-URLError should have nil errorCode")
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Expected AppNetworkError, got \(error)")
        }
    }
}

// MARK: - Property 13: onRequest 拒绝绕过重试

/// **Feature: network-apiclient-optimization, Property 13: onRequest 拒绝绕过重试**
/// **Validates: Requirements 5.5**
final class ApiClientOnRequestRejectTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.resetRequestCount()
    }

    func testOnRequestRejectSkipsNetworkCallAndRetry() async {
        let rejectError = NSError(domain: "AuthError", code: -100, userInfo: [
            NSLocalizedDescriptionKey: "Token missing"
        ])
        mockHTTPResponse(statusCode: 200) // Should never be reached
        let client = makeApiClient(
            interceptors: [RejectOnRequestInterceptor(rejectError: rejectError)],
            maxRetryCount: 3
        )

        do {
            _ = try await client.sendRequest(MockRequest())
            XCTFail("Expected error from onRequest reject")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "AuthError")
            XCTAssertEqual(nsError.code, -100)
        }

        // No network request should have been made
        XCTAssertEqual(MockURLProtocol.currentRequestCount(), 0,
                       "onRequest reject should skip the network call entirely")
    }

    func testOnRequestRejectDoesNotTriggerOnErrorChain() async {
        let rejectError = NSError(domain: "Reject", code: -1)

        // An interceptor that would retry on error — should never be reached
        let onErrorCounter = CallCountingOnErrorInterceptor()

        mockHTTPResponse(statusCode: 200)
        let client = makeApiClient(
            interceptors: [
                RejectOnRequestInterceptor(rejectError: rejectError),
                onErrorCounter,
            ],
            maxRetryCount: 3
        )

        _ = try? await client.sendRequest(MockRequest())

        let errorCount = await onErrorCounter.onErrorCount
        XCTAssertEqual(errorCount, 0,
                       "onError should not be called when onRequest rejects")
    }
}

/// Counts how many times onError is called.
private actor CallCountingOnErrorInterceptor: NetworkInterceptor {
    private var _onErrorCount = 0

    var onErrorCount: Int { _onErrorCount }

    func onError(_ error: Error, request: URLRequest, handler: ErrorInterceptorHandler) async -> ErrorInterceptorResult {
        _onErrorCount += 1
        return handler.next(error)
    }
}
