//
//  PayloadSignerTests.swift
//  LicenseManagerTests
//
//  Created by samuel Ailemen on 3/29/26.
//

import XCTest
@testable import LicenseManager

final class PayloadSignerTests: XCTestCase {
    func testCanonicalizationSortsFlatKeys() throws {
        let input: [String: Any] = ["b": 2, "a": 1]
        let output = try PayloadSigner.canonicalJSONString(from: input)
        XCTAssertEqual(output, "{\"a\":1,\"b\":2}")
    }

    func testCanonicalizationSortsNestedKeys() throws {
        let input: [String: Any] = [
            "z": ["b": 2, "a": 1],
            "a": "hello"
        ]

        let output = try PayloadSigner.canonicalJSONString(from: input)
        XCTAssertEqual(output, "{\"a\":\"hello\",\"z\":{\"a\":1,\"b\":2}}")
    }

    func testCanonicalizationPreservesArrayOrder() throws {
        let input: [String: Any] = ["list": [3, 1, 2], "name": "test"]
        let output = try PayloadSigner.canonicalJSONString(from: input)
        XCTAssertEqual(output, "{\"list\":[3,1,2],\"name\":\"test\"}")
    }

    func testSigningSupportsPlaintextSecret() throws {
        let signer = PayloadSigner()
        let input: [String: Any] = [
            "machine_id": "ABC-123",
            "license_key": "KW-XXXX-XXXX"
        ]

        let signature = try signer.sign(body: input, secret: "test_secret")
        XCTAssertEqual(signature, "7161b977f229cc741c5491517c30418a741be9c72046f124a2b1c64efa784b37")
    }

    func testSigningSupportsHexSecret() throws {
        let signer = PayloadSigner()
        let input: [String: Any] = [
            "machine_id": "ABC-123",
            "license_key": "KW-XXXX-XXXX"
        ]

        // Hex encoding of "test_secret"
        let signature = try signer.sign(body: input, secret: "746573745f736563726574")
        XCTAssertEqual(signature, "7161b977f229cc741c5491517c30418a741be9c72046f124a2b1c64efa784b37")
    }
}
