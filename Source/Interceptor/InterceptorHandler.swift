//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

// MARK: - Request Phase

public struct RequestInterceptorHandler: Sendable {
    public func next(_ request: URLRequest) -> RequestInterceptorResult { .next(request) }
    public func reject(_ error: Error) -> RequestInterceptorResult { .reject(error) }
}

public enum RequestInterceptorResult: @unchecked Sendable {
    case next(URLRequest)
    case reject(Error)
}

// MARK: - Response Phase

public struct ResponseInterceptorHandler: Sendable {
    public func next(_ response: Response) -> ResponseInterceptorResult { .next(response) }
    public func reject(_ error: Error) -> ResponseInterceptorResult { .reject(error) }
}

public enum ResponseInterceptorResult: @unchecked Sendable {
    case next(Response)
    case reject(Error)
}

// MARK: - Error Phase

public struct ErrorInterceptorHandler: Sendable {
    public func next(_ error: Error) -> ErrorInterceptorResult { .next(error) }
    public func retry() -> ErrorInterceptorResult { .retry }
}

public enum ErrorInterceptorResult: @unchecked Sendable {
    case next(Error)
    case retry
}
