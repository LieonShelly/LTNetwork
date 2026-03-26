//
//  LTApp, This code is protected by intellectual property rights.
//


import Foundation

public extension Encodable {
    func json() -> [String: any Sendable] {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: any Sendable] else {
            return [:]
        }
        return dict
    }
}
