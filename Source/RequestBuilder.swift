//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

public class RequestBuilder {
    private let request: any Request
    
    public init(request: any Request) {
        self.request = request
    }
    
    public func build(_ environment: AppEnvironment) -> URLRequest {
        let url = request.endPoint.absoluteUrl(environment)
        var urlRequest =  URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        var header: [String: String] = [:]
        switch request.payload {
        case .json(let body, let urlParameters):
            header["Content-Type"] = "application/json"
            urlRequest.httpBody = encodeJson(parameters: body)
            if let urlParameters {
                var urlComponents = URLComponents(string: url.absoluteString)
                urlComponents?.queryItems = urlParameters.map { URLQueryItem(name: $0.0, value: $0.1)}
                urlRequest.url = url
            }
            urlRequest.allHTTPHeaderFields = header
            return urlRequest
        case .urlEncoding(let values):
            if [.get, .delete].contains(request.method) {
                var urlComponents = URLComponents(string: url.absoluteString)
                urlComponents?.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
                urlRequest.url = urlComponents?.url
            } else {
                header["Content-Type"] = "application/x-www-form-urlencoded"
                var parameters = [String: Any]()
                values.forEach { parameters[$0.key] = $0.value }
                urlRequest.httpBody = encodeUrlParameter(parameters: parameters).data(using: .utf8, allowLossyConversion: false)
            }
            urlRequest.allHTTPHeaderFields = header
            return urlRequest
        case .empty:
            return urlRequest
        }
    }
    
    private func encodeJson(parameters: [String: Any]) -> Data? {
        let json = try? JSONSerialization.data(withJSONObject: parameters, options: [])
        return json
    }
    
    private func encodeUrlParameter(parameters: [String: Any]) -> String {
        let urlEncodedParameters = parameters.map { key, value -> String in
            let escapedKey = escape(key)
            guard let value = value as? String else {
                fatalError("Not implemented yet")
            }
            
            let escapedValue = escape(value)
            return "\(escapedKey)=\(escapedValue)"
        }
        .sorted()
        .joined(separator: "&")
        
        return urlEncodedParameters
    }
    
    private func escape(_ string: String) -> String {
        let generalDelimitersToEncode = ":#[]@"
        let subDelimitersToEncode = "!$&'()*+,;="
        
        var allowedCharacterSet = CharacterSet.urlQueryAllowed
        allowedCharacterSet.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
        
        let escaped = string.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? string
        return escaped
    }
}
