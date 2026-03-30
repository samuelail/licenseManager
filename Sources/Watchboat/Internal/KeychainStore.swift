//
//  KeychainStore.swift
//  Watchboat
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation
import Security

internal protocol KeychainStoreProtocol {
    func save(code: String) throws
    func load() throws -> String?
    func delete() throws
}

internal enum KeychainStoreError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
}

extension KeychainStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status: \(status)"
        case .invalidData:
            return "Stored license data is corrupted."
        }
    }
}

internal final class KeychainStore: KeychainStoreProtocol {
    private let service: String
    private let account: String

    internal init(service: String, account: String = "activation_code") {
        self.service = service
        self.account = account
    }

    internal func save(code: String) throws {
        try delete()

        var query = baseQuery
        query[kSecValueData as String] = Data(code.utf8)
#if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
#endif

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    internal func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let code = String(data: data, encoding: .utf8) else {
                throw KeychainStoreError.invalidData
            }
            return code
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    internal func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
