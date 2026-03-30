//
//  LicenseConfigTests.swift
//  LicenseManagerTests
//
//  Created by samuel Ailemen on 3/29/26.
//

import XCTest
@testable import LicenseManager

final class LicenseConfigTests: XCTestCase {
    func testDefaultsProvideLocalBaseURLAndNonEmptyKeychainService() {
        let config = LicenseConfig(appId: "app-id", appSecret: "secret")

        XCTAssertEqual(config.baseURL.absoluteString, "http://localhost:3000")
        XCTAssertEqual(config.validationIntervalDays, 7)
        XCTAssertEqual(config.maxOfflineValidationDays, 30)
        XCTAssertFalse(config.keychainService.isEmpty)
    }

    func testNilIntervalsDisableValidationTimers() {
        let config = LicenseConfig(
            appId: "app-id",
            appSecret: "secret",
            validationIntervalDays: nil,
            maxOfflineValidationDays: nil
        )

        XCTAssertNil(config.validationInterval)
        XCTAssertNil(config.maxOfflineInterval)
    }
}
