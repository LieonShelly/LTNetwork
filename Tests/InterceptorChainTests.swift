//
//  LTApp, This code is protected by intellectual property rights.
//

import XCTest
@testable import LTNetwork

// MARK: - Test Interceptors

/// Records the order it was called and optionally modifies the request by adding a header.
private final class OrderTrackingInterceptor: NetworkInterceptor, @unchecked Sendable {
    let id: Int
    let orderLog: OrderLog

    init(id: Int, orderLog: OrderLog) {
        self.id = id
        self.orderLog = orderLog
    }

    func onRequest(_ request: URLRequest, handler: RequestInterceptorHandler) async -> RequestInterceptorResult {
        orderLog.append(id)
        var modified = request
        modified.setValue("\(id)", forHTTPHeaderField: "X-Interceptor-\(id)")
        return handler.next(modified)
    }

    func onResponse(_ response: Response, handler: ResponseInterceptorHandler) async -> ResponseInterceptorResult {
        orderLog.append(id)
        return handler.next(response)
    }

    func onError(_ error: Error, request: URLRequest, handler: ErrorInterceptorHandler) async -> ErrorInterceptorResult {
        orderLog.append(id)
        return handler.next(error)
    }
}

/// Thread-safe order log.
private final class OrderLog: @unchecked Sendable {
    private var _entries: [Int] = []
    private let lock = NSLock()

    func append(_ id: Int) {
        lock.lock()
        _entries.append(id)
        lock.unlock()
    }

    var entries: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    func reset() {
        lock.lock()
        _entries.removeAll()
        lock.unlock()
    }
}

/// Rejects on onRequest.
private struct RejectingInterceptor: NetworkInterceptor {
    let error: Error
    func onRequest(_ request: URLRequest, handler: RequestInterceptorHandler) async -> RequestInterceptorResult {
        handler.reject(error)
    }
}

/// Returns .retry on onError.
private struct RetryInterceptor: NetworkInterceptor {
    func onError(_ error: Error, request: URLRequest, handler: ErrorInterceptorHandler) async -> ErrorInterceptorResult {
        handler.retry()
    }
}

/// Rejects on onResponse.
private struct ResponseRejectingInterceptor: NetworkInterceptor {
    let error: Error
    func onResponse(_ response: Response, handler: ResponseInterceptorHandler) async -> ResponseInterceptorResult {
        handler.reject(error)
    }
}

// MARK: - Property 6: 拦截器按注册顺序执行

/// **Feature: network-apiclient-optimization, Property 6: 拦截器按注册顺序执行**
/// **Validates: Requirements 3.6**
final class InterceptorChainTests: XCTestCase {

    private let dummyRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)

    // MARK: - onRequest executes in registration order

    func testOnRequestExecutesInOrder() async {
        let log = OrderLog()
        let interceptors: [NetworkInterceptor] = (0..<5).map {
            OrderTrackingInterceptor(id: $0, orderLog: log)
        }
        let chain = InterceptorChain(interceptors: interceptors)

        let result = await chain.executeOnRequest(dummyRequest)

        if case .reject = result { XCTFail("Should not reject") }
        XCTAssertEqual(log.entries, [0, 1, 2, 3, 4])
    }

    // MARK: - onResponse executes in registration order

    func testOnResponseExecutesInOrder() async {
        let log = OrderLog()
        let interceptors: [NetworkInterceptor] = (0..<5).map {
            OrderTrackingInterceptor(id: $0, orderLog: log)
        }
        let chain = InterceptorChain(interceptors: interceptors)
        let response = Response(statusCode: 200, data: nil)

        let result = await chain.executeOnResponse(response)

        if case .reject = result { XCTFail("Should not reject") }
        XCTAssertEqual(log.entries, [0, 1, 2, 3, 4])
    }

    // MARK: - onError executes in registration order

    func testOnErrorExecutesInOrder() async {
        let log = OrderLog()
        let interceptors: [NetworkInterceptor] = (0..<5).map {
            OrderTrackingInterceptor(id: $0, orderLog: log)
        }
        let chain = InterceptorChain(interceptors: interceptors)
        let error = NSError(domain: "Test", code: 1)

        let result = await chain.executeOnError(error, request: dummyRequest)

        if case .retry = result { XCTFail("Should not retry") }
        XCTAssertEqual(log.entries, [0, 1, 2, 3, 4])
    }

    // MARK: - Empty chain passes through

    func testEmptyChainPassesThrough() async {
        let chain = InterceptorChain(interceptors: [])

        let reqResult = await chain.executeOnRequest(dummyRequest)
        if case .next(let req) = reqResult {
            XCTAssertEqual(req.url, dummyRequest.url)
        } else {
            XCTFail("Empty chain should pass request through")
        }

        let response = Response(statusCode: 200, data: Data("ok".utf8))
        let resResult = await chain.executeOnResponse(response)
        if case .next(let res) = resResult {
            XCTAssertEqual(res.statusCode, 200)
        } else {
            XCTFail("Empty chain should pass response through")
        }

        let error = NSError(domain: "Test", code: 42)
        let errResult = await chain.executeOnError(error, request: dummyRequest)
        if case .next(let err) = errResult {
            XCTAssertEqual((err as NSError).code, 42)
        } else {
            XCTFail("Empty chain should pass error through")
        }
    }

    // MARK: - onRequest reject short-circuits

    func testOnRequestRejectShortCircuits() async {
        let log = OrderLog()
        let rejectError = NSError(domain: "Reject", code: -1)
        let interceptors: [NetworkInterceptor] = [
            OrderTrackingInterceptor(id: 0, orderLog: log),
            RejectingInterceptor(error: rejectError),
            OrderTrackingInterceptor(id: 2, orderLog: log),
        ]
        let chain = InterceptorChain(interceptors: interceptors)

        let result = await chain.executeOnRequest(dummyRequest)

        // Interceptor 0 ran, then reject, interceptor 2 should NOT run
        XCTAssertEqual(log.entries, [0])
        if case .reject(let err) = result {
            XCTAssertEqual((err as NSError).code, -1)
        } else {
            XCTFail("Expected reject")
        }
    }

    // MARK: - onError retry short-circuits

    func testOnErrorRetryShortCircuits() async {
        let log = OrderLog()
        let interceptors: [NetworkInterceptor] = [
            OrderTrackingInterceptor(id: 0, orderLog: log),
            RetryInterceptor(),
            OrderTrackingInterceptor(id: 2, orderLog: log),
        ]
        let chain = InterceptorChain(interceptors: interceptors)
        let error = NSError(domain: "Test", code: 1)

        let result = await chain.executeOnError(error, request: dummyRequest)

        XCTAssertEqual(log.entries, [0])
        if case .retry = result {
            // expected
        } else {
            XCTFail("Expected retry")
        }
    }

    // MARK: - onResponse reject short-circuits

    func testOnResponseRejectShortCircuits() async {
        let log = OrderLog()
        let rejectError = NSError(domain: "Reject", code: -2)
        let interceptors: [NetworkInterceptor] = [
            OrderTrackingInterceptor(id: 0, orderLog: log),
            ResponseRejectingInterceptor(error: rejectError),
            OrderTrackingInterceptor(id: 2, orderLog: log),
        ]
        let chain = InterceptorChain(interceptors: interceptors)
        let response = Response(statusCode: 200, data: nil)

        let result = await chain.executeOnResponse(response)

        XCTAssertEqual(log.entries, [0])
        if case .reject(let err) = result {
            XCTAssertEqual((err as NSError).code, -2)
        } else {
            XCTFail("Expected reject")
        }
    }

    // MARK: - onRequest modifications accumulate

    func testOnRequestModificationsAccumulate() async {
        let log = OrderLog()
        let interceptors: [NetworkInterceptor] = (0..<3).map {
            OrderTrackingInterceptor(id: $0, orderLog: log)
        }
        let chain = InterceptorChain(interceptors: interceptors)

        let result = await chain.executeOnRequest(dummyRequest)

        if case .next(let finalRequest) = result {
            // Each interceptor adds its own header
            XCTAssertEqual(finalRequest.value(forHTTPHeaderField: "X-Interceptor-0"), "0")
            XCTAssertEqual(finalRequest.value(forHTTPHeaderField: "X-Interceptor-1"), "1")
            XCTAssertEqual(finalRequest.value(forHTTPHeaderField: "X-Interceptor-2"), "2")
        } else {
            XCTFail("Expected next")
        }
    }
}
