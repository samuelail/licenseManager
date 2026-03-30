//
//  LicenseConfig.swift
//  Watchboat
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation

public struct LicenseConfig: Sendable {
    public let appId: String
    public let appSecret: String
    public let baseURL: URL
    public let keychainService: String
    public let validationIntervalDays: Int?
    public let maxOfflineValidationDays: Int?
    public let keychainAccount: String

    public init(
        appId: String,
        appSecret: String,
        baseURL: URL = URL(string: "https://api.watchboat.com")!,
        keychainService: String = "",
        validationIntervalDays: Int? = 7,
        maxOfflineValidationDays: Int? = 30,
        keychainAccount: String = "activation_code"
    ) {
        self.appId = appId
        self.appSecret = appSecret
        self.baseURL = baseURL
        let normalizedService = keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keychainService = normalizedService.isEmpty
            ? LicenseConfig.defaultKeychainService()
            : normalizedService
        self.validationIntervalDays = validationIntervalDays
        self.maxOfflineValidationDays = maxOfflineValidationDays
        self.keychainAccount = keychainAccount
    }

    internal var validationInterval: TimeInterval? {
        guard let validationIntervalDays, validationIntervalDays > 0 else {
            return nil
        }
        return TimeInterval(validationIntervalDays) * 24 * 60 * 60
    }

    internal var maxOfflineInterval: TimeInterval? {
        guard let maxOfflineValidationDays, maxOfflineValidationDays > 0 else {
            return nil
        }
        return TimeInterval(maxOfflineValidationDays) * 24 * 60 * 60
    }

    private static func defaultKeychainService() -> String {
        if
            let bundleIdentifier = Bundle.main.bundleIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleIdentifier.isEmpty
        {
            return "\(bundleIdentifier).license"
        }
        return "com.watchboat.license"
    }
}
