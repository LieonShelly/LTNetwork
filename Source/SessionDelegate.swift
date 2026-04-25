//
//  SessionDelegate.swift
//  Network
//
//  Created by 李仁军 on 2026/4/25.
//

import Foundation

final class SessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let validator: (any SSLPinningValidating)?
    private let environment: AppEnvironment

    init(validator: (any SSLPinningValidating)?, environment: AppEnvironment) {
        self.validator = validator
        self.environment = environment
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let validator, !validator.isDisabled else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let result = validator.validate(challenge: challenge, environment: environment)
        switch result {
        case .success(let credential):
            completionHandler(.useCredential, credential)
        case .failure:
            completionHandler(.cancelAuthenticationChallenge, nil)
        case .performDefaultHandling:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
