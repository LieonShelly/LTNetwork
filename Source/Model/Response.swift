//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

public struct Response: Sendable {
    let statusCode: Int
    let data: Data?
}

extension Response {
    public func parseJson<T: Decodable>(with dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate) throws -> T {
        guard let data else {
            throw AppNetworkError.dataError(debugDescription: "Response doesn't contain data")
        }

        return try JSONDecoder.parseJson(data,
                                         with: dateDecodingStrategy)
    }
}

public extension JSONDecoder {
    static func parseJson<T: Decodable>(_ data: Data, with dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        return try decoder.decode(T.self, from: data)
    }
}

