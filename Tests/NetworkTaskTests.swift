//
//  LTApp, This code is protected by intellectual property rights.
//

import XCTest
@testable import LTNetwork

// MARK: - Property 1: 取消操作产生 CancellationError

/// **Feature: network-apiclient-optimization, Property 1: 取消操作产生 CancellationError**
/// **Validates: Requirements 1.2, 1.3, 2.5, 5.4**
final class NetworkTaskTests: XCTestCase {

    // MARK: - Cancel before completion throws CancellationError

    func testCancelBeforeCompletionThrowsCancellationError() async {
        let networkTask = NetworkTask(task: Task<Response, Error> {
            // Simulate a long-running request
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Response(statusCode: 200, data: nil)
        })

        // Cancel immediately
        networkTask.cancel()

        do {
            _ = try await networkTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(type(of: error)): \(error)")
        }
    }

    // MARK: - isCancelled reflects cancel state

    func testIsCancelledReflectsState() {
        let networkTask = NetworkTask(task: Task<Response, Error> {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Response(statusCode: 200, data: nil)
        })

        XCTAssertFalse(networkTask.isCancelled)
        networkTask.cancel()
        XCTAssertTrue(networkTask.isCancelled)
    }

    // MARK: - Successful task returns response

    func testSuccessfulTaskReturnsResponse() async throws {
        let expectedData = Data("hello".utf8)
        let networkTask = NetworkTask(task: Task<Response, Error> {
            Response(statusCode: 200, data: expectedData)
        })

        let response = try await networkTask.value
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.data, expectedData)
    }

    // MARK: - Failed task throws error

    func testFailedTaskThrowsError() async {
        let networkTask = NetworkTask(task: Task<Response, Error> {
            throw AppNetworkError.httpError(statusCode: .notFound, body: nil)
        })

        do {
            _ = try await networkTask.value
            XCTFail("Expected error")
        } catch let error as AppNetworkError {
            if case .httpError(statusCode: .notFound, _) = error {
                // expected
            } else {
                XCTFail("Expected notFound, got \(error)")
            }
        } catch {
            XCTFail("Expected AppNetworkError, got \(error)")
        }
    }

    // MARK: - Cancel after completion is harmless

    func testCancelAfterCompletionIsHarmless() async throws {
        let networkTask = NetworkTask(task: Task<Response, Error> {
            Response(statusCode: 200, data: Data("done".utf8))
        })

        let response = try await networkTask.value
        XCTAssertEqual(response.statusCode, 200)

        // Cancel after completion — should not crash or change result
        networkTask.cancel()
        // isCancelled may be true on the underlying Task, but value already resolved
    }
}
