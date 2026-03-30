//
//  LicenseActivatorTests.swift
//  WatchboatTests
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation
import XCTest
@testable import Watchboat

final class LicenseActivatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testActivateSuccessPromotesPlanAndStoresCode() async throws {
        let keychain = InMemoryKeychainStore()
        let defaults = try makeDefaults()
        defer { clearDefaults(defaults) }

        let manager = makeManager(
            keychain: keychain,
            defaults: defaults,
            requestHandler: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Id"), "app-id")
                let timestamp = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Timestamp"))
                XCTAssertNotNil(Int(timestamp))

                let signature = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Signature"))
                let body: [String: Any] = [
                    "license_key": "KW-AAAA-BBBB-CCCC-DDDD",
                    "machine_id": "MACHINE-1"
                ]
                let expectedSignature = try PayloadSigner().sign(
                    body: body,
                    timestamp: timestamp,
                    secret: "test_secret"
                )
                XCTAssertEqual(signature, expectedSignature)
                XCTAssertEqual(request.url?.path, "/v1/activate")

                let responseBody = """
                {
                  "status": "success",
                  "message": "License activated successfully.",
                  "data": {
                    "license_key": "KW-AAAA-BBBB-CCCC-DDDD",
                    "machine_id": "MACHINE-1",
                    "activated_at": "2026-03-29T20:36:12.186Z"
                  },
                  "request_id": "req-1",
                  "request_time": "2026-03-29T20:36:12.186Z"
                }
                """

                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(responseBody.utf8))
            }
        )

        await manager.activate(code: " kw-aaaa-bbbb-cccc-dddd ")

        XCTAssertEqual(manager.plan, .pro)
        XCTAssertNil(manager.activationError)
        XCTAssertEqual(keychain.code, "KW-AAAA-BBBB-CCCC-DDDD")
        XCTAssertEqual(manager.maskedActivationCode, "****DDDD")
        XCTAssertTrue(manager.isProUser)
    }

    @MainActor
    func testValidateNetworkFailureKeepsProState() async throws {
        let keychain = InMemoryKeychainStore(code: "KW-AAAA-BBBB-CCCC-DDDD")
        let defaults = try makeDefaults()
        defer { clearDefaults(defaults) }

        let manager = makeManager(
            keychain: keychain,
            defaults: defaults,
            requestHandler: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        await manager.validateIfNeeded()

        XCTAssertEqual(manager.plan, .pro)
        XCTAssertEqual(keychain.code, "KW-AAAA-BBBB-CCCC-DDDD")
    }

    @MainActor
    func testValidateRevokedLicenseDeactivatesLocally() async throws {
        let keychain = InMemoryKeychainStore(code: "KW-AAAA-BBBB-CCCC-DDDD")
        let defaults = try makeDefaults()
        defer { clearDefaults(defaults) }

        let manager = makeManager(
            keychain: keychain,
            defaults: defaults,
            requestHandler: { request in
                XCTAssertEqual(request.url?.path, "/v1/validate")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Timestamp"))
                XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Signature"))

                let responseBody = """
                {
                  "status": "error",
                  "message": "This license has been revoked.",
                  "data": {
                    "valid": false,
                    "reason": "revoked"
                  },
                  "request_id": "req-2",
                  "request_time": "2026-03-29T20:36:12.186Z"
                }
                """

                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(responseBody.utf8))
            }
        )

        await manager.validateIfNeeded()

        XCTAssertEqual(manager.plan, .free)
        XCTAssertNil(keychain.code)
        XCTAssertEqual(manager.activationError, LicenseError.licenseRevoked.localizedDescription)
    }

    @MainActor
    func testValidateSkipsWhenIntervalNotReached() async throws {
        let keychain = InMemoryKeychainStore()
        let defaults = try makeDefaults()
        defer { clearDefaults(defaults) }

        let requestCounter = LockedCounter()
        let manager = makeManager(
            keychain: keychain,
            defaults: defaults,
            requestHandler: { request in
                requestCounter.increment()

                if request.url?.path == "/v1/activate" {
                    let responseBody = """
                    {
                      "status": "success",
                      "message": "License activated successfully.",
                      "data": {
                        "license_key": "KW-AAAA-BBBB-CCCC-DDDD",
                        "machine_id": "MACHINE-1",
                        "activated_at": "2026-03-29T20:36:12.186Z"
                      }
                    }
                    """
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return (response, Data(responseBody.utf8))
                }

                let responseBody = """
                {
                  "status": "success",
                  "message": "License is valid.",
                  "data": {
                    "valid": true,
                    "license_key": "KW-AAAA-BBBB-CCCC-DDDD",
                    "machine_id": "MACHINE-1",
                    "last_validated_at": "2026-03-29T20:36:12.186Z"
                  }
                }
                """
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(responseBody.utf8))
            }
        )

        await manager.activate(code: "KW-AAAA-BBBB-CCCC-DDDD")
        XCTAssertEqual(requestCounter.value, 1)

        await manager.validateIfNeeded()
        XCTAssertEqual(requestCounter.value, 1)
    }

    @MainActor
    func testValidateDoesNotRunWhenValidationIsDisabled() async throws {
        let keychain = InMemoryKeychainStore(code: "KW-AAAA-BBBB-CCCC-DDDD")
        let defaults = try makeDefaults()
        defer { clearDefaults(defaults) }

        let requestCounter = LockedCounter()
        let manager = makeManager(
            keychain: keychain,
            defaults: defaults,
            validationIntervalDays: nil,
            maxOfflineValidationDays: nil,
            requestHandler: { request in
                requestCounter.increment()
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data())
            }
        )

        await manager.validateIfNeeded()

        XCTAssertEqual(requestCounter.value, 0)
        XCTAssertEqual(manager.plan, .pro)
        XCTAssertEqual(keychain.code, "KW-AAAA-BBBB-CCCC-DDDD")
    }

    @MainActor
    private func makeManager(
        keychain: InMemoryKeychainStore,
        defaults: UserDefaults,
        validationIntervalDays: Int? = 7,
        maxOfflineValidationDays: Int? = 30,
        requestHandler: @escaping MockURLProtocol.RequestHandler
    ) -> LicenseActivator {
        MockURLProtocol.requestHandler = requestHandler

        let config = LicenseConfig(
            appId: "app-id",
            appSecret: "test_secret",
            baseURL: URL(string: "https://license-api.example.com")!,
            keychainService: "com.test.license",
            validationIntervalDays: validationIntervalDays,
            maxOfflineValidationDays: maxOfflineValidationDays
        )

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        let apiClient = APIClient(config: config, session: session)

        return LicenseActivator(
            config: config,
            apiClient: apiClient,
            keychainStore: keychain,
            userDefaults: defaults,
            machineIdentifier: "MACHINE-1"
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WatchboatTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "WatchboatTests", code: 1)
        }
        defaults.set(suiteName, forKey: "suiteName")
        return defaults
    }

    private func clearDefaults(_ defaults: UserDefaults) {
        guard let suiteName = defaults.string(forKey: "suiteName") else {
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class InMemoryKeychainStore: KeychainStoreProtocol {
    var code: String?

    init(code: String? = nil) {
        self.code = code
    }

    func save(code: String) throws {
        self.code = code
    }

    func load() throws -> String? {
        code
    }

    func delete() throws {
        code = nil
    }
}

private final class MockURLProtocol: URLProtocol {
    typealias RequestHandler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    nonisolated(unsafe) static var requestHandler: RequestHandler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
