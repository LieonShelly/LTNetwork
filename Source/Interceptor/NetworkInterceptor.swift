//
//  Created by lieon on 2026/05/17.
//  This code is protected by intellectual property rights.
//

import Foundation

public protocol NetworkInterceptor: Sendable {
    func onRequest(_ request: URLRequest, handler: RequestInterceptorHandler) async -> RequestInterceptorResult
    func onResponse(_ response: Response, handler: ResponseInterceptorHandler) async -> ResponseInterceptorResult
    func onError(_ error: Error, request: URLRequest, handler: ErrorInterceptorHandler) async -> ErrorInterceptorResult
}


extension NetworkInterceptor {
    public func onRequest(_ request: URLRequest, handler: RequestInterceptorHandler) async -> RequestInterceptorResult {
        handler.next(request)
    }

    public func onResponse(_ response: Response, handler: ResponseInterceptorHandler) async -> ResponseInterceptorResult {
        handler.next(response)
    }

    public func onError(_ error: Error, request: URLRequest, handler: ErrorInterceptorHandler) async -> ErrorInterceptorResult {
        handler.next(error)
    }
}
