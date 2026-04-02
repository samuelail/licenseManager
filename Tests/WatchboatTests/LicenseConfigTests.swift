//
//  LicenseConfigTests.swift
//  WatchboatTests
//
//  Created by samuel Ailemen on 3/29/26.
//

import XCTest
@testable import Watchboat

final class LicenseConfigTests: XCTestCase {
    func testDefaultsProvideLocalBaseURLAndNonEmptyKeychainService() {
        let config = LicenseConfig(appId: "app-id", appSecret: "secret")

        XCTAssertEqual(config.baseURL.absoluteString, "https://api.watchboat.com")
        XCTAssertTrue(config.includeLocation)
        XCTAssertEqual(config.validationIntervalDays, 7)
        XCTAssertEqual(config.maxOfflineValidationDays, 30)
        XCTAssertFalse(config.keychainService.isEmpty)
    }

    func testCanDisableLocationCollection() {
        let config = LicenseConfig(
            appId: "app-id",
            appSecret: "secret",
            includeLocation: false
        )

        XCTAssertFalse(config.includeLocation)
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
