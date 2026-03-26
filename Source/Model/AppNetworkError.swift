//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

public enum AppNetworkError: LocalizedError, Sendable {
    public enum NetworkConnectionError: Int, Sendable {
        case slowCellular
        case noInternet
        case notAllowedHost
    }
    
    case httpError(statusCode: HttpErrorCode, body: Data?)
    case dataError(debugDescription: String)
    case networkError(debugDescription: String, errorCode: URLError.Code?, httpResponse: HTTPURLResponse? = nil)
    case localizedError(model: ErrorModel)
    case connectionError(type: NetworkConnectionError)
    case authorizationError(debugDescription: String)
    
    public var errorDescription: String? {
        return "errorDescription"
    }
}


public enum HttpErrorCode: Int, Sendable {
    case found = 302
    case badRequest = 400
    case unauthorized = 401
    case paymentRequired
    case forbidden
    case notFound
    case methodNotAllowed
    case notAcceptable
    case proxyAuthenticationRequired
    case requestTimeout
    case conflict
    case gone
    case lengthRequired
    case preconditionFailed
    case payloadTooLarge
    case uRITooLong
    case unsupportedMediaType
    case rangeNotSatisfiable
    case expectationFailed
    case imATeapot
    case misdirectedRequest = 421
    case unprocessableEntity
    case locked
    case failedDependency
    case upgradeRequired = 426
    case preconditionRequired = 428
    case tooManyRequests
    case requestHeaderFieldsTooLarge = 431
    case unavailableForLegalReasons = 451
    case clientClosedRequest = 499
    
    case internalServerError = 500
    case notImplemented
    case badGateway
    case serviceUnavailable
    case gatewayTimeout
    case httpVersionNotSupported
    case variantAlsoNegotiates
    case insufficientStorage
    case loopDetected
    case notExtended = 510
    case networkAuthenticationRequired
    case networkConnectTimeoutError = 599
}

public struct ErrorModel: Codable, Equatable, Sendable {
    public let errorCode: String
    public let title: String?
    public let titleCode: String?
    public let message: String?
    public let messageCode: String?
    public let timestamp: String
    public let messageArguments: [String]?
    
    public init(errorCode: String,
                title: String?,
                message: String?,
                timestamp: String,
                titleCode: String? = nil,
                messageCode: String? = nil,
                messageArguments: [String]? = nil) {
        self.errorCode = errorCode
        self.title = title
        self.message = message
        self.timestamp = timestamp
        
        self.titleCode = titleCode
        self.messageCode = messageCode
        self.messageArguments = messageArguments
    }
}
