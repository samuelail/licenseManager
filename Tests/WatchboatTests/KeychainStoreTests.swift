//
//  KeychainStoreTests.swift
//  WatchboatTests
//
//  Created by samuel Ailemen on 3/29/26.
//

import XCTest
@testable import Watchboat

final class KeychainStoreTests: XCTestCase {
    func testSaveLoadDeleteRoundTrip() throws {
        let service = "com.licenseactivator.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: service, account: "unit_test")

        try store.delete()
        try store.save(code: "KW-AAAA-BBBB-CCCC-DDDD")

        let loaded = try store.load()
        XCTAssertEqual(loaded, "KW-AAAA-BBBB-CCCC-DDDD")

        try store.delete()
        let afterDelete = try store.load()
        XCTAssertNil(afterDelete)
    }
}
