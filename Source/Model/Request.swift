//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

public protocol EndPoint {
    func absoluteUrl(_ environment: AppEnvironment) -> URL
}

public protocol Request: Sendable {
    var endPoint: EndPoint { get }
    var method: HttpMethod { get }
    var payload: HttpPayload { get }
}

public enum HttpMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}


public enum HttpPayload: Sendable {
    case json(body: [String: any Sendable], urlParameter: [(key: String, value: String)]? = nil)
    case urlEncoding([(key: String, value: String)])
    case empty
}
