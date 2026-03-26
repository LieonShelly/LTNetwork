//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

public final class NetworkTask: Sendable {
    private let task: Task<Response, Error>

    init(task: Task<Response, Error>) {
        self.task = task
    }

    public var value: Response {
        get async throws { try await task.value }
    }

    public func cancel() {
        task.cancel()
    }

    public var isCancelled: Bool {
        task.isCancelled
    }
}
