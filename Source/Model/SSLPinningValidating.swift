//
//  LTApp, This code is protected by intellectual property rights.
//

import Foundation

public enum SSLPinningResult: Sendable {
    case success(URLCredential)
    case failure
    case performDefaultHandling
}

public protocol SSLPinningValidating: Sendable {
    var isDisabled: Bool { get }
    var pinnedPublicKeyHashes: [String] { get }

    func validate(
        challenge: URLAuthenticationChallenge,
        environment: AppEnvironment
    ) -> SSLPinningResult
}
