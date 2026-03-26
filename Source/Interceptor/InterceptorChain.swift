//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

struct InterceptorChain: Sendable {
    let interceptors: [NetworkInterceptor]

    func executeOnRequest(_ request: URLRequest) async -> RequestInterceptorResult {
        var current = request
        let handler = RequestInterceptorHandler()
        for interceptor in interceptors {
            let result = await interceptor.onRequest(current, handler: handler)
            switch result {
            case .next(let modified):
                current = modified
            case .reject(let error):
                return .reject(error)
            }
        }
        return .next(current)
    }

    func executeOnResponse(_ response: Response) async -> ResponseInterceptorResult {
        var current = response
        let handler = ResponseInterceptorHandler()
        for interceptor in interceptors {
            let result = await interceptor.onResponse(current, handler: handler)
            switch result {
            case .next(let modified):
                current = modified
            case .reject(let error):
                return .reject(error)
            }
        }
        return .next(current)
    }

    func executeOnError(_ error: Error, request: URLRequest) async -> ErrorInterceptorResult {
        var currentError = error
        let handler = ErrorInterceptorHandler()
        for interceptor in interceptors {
            let result = await interceptor.onError(currentError, request: request, handler: handler)
            switch result {
            case .next(let modified):
                currentError = modified
            case .retry:
                return .retry
            }
        }
        return .next(currentError)
    }
}
