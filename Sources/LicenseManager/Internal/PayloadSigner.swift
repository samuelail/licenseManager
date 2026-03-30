//
//  PayloadSigner.swift
//  LicenseManager
//
//  Created by samuel Ailemen on 3/29/26.
//

import CryptoKit
import Foundation

internal enum PayloadSignerError: Error {
    case unsupportedValue(Any.Type)
    case invalidNumber(NSNumber)
}

extension PayloadSignerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedValue(let type):
            return "Unsupported JSON value type: \(type)"
        case .invalidNumber(let number):
            return "Invalid JSON number: \(number)"
        }
    }
}

internal struct PayloadSigner {
    internal init() {}

    internal func sign(body: [String: Any], secret: String) throws -> String {
        let canonicalJSON = try Self.canonicalJSONString(from: body)
        let keyData = Self.keyData(from: secret)
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(canonicalJSON.utf8),
            using: SymmetricKey(data: keyData)
        )
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    internal static func canonicalJSONString(from object: Any) throws -> String {
        try serialize(value: object)
    }

    private static func serialize(value: Any) throws -> String {
        if value is NSNull {
            return "null"
        }

        if let dictionary = value as? [String: Any] {
            let components = try dictionary.keys.sorted().map { key -> String in
                let keyString = quoteJSONString(key)
                let valueString = try serialize(value: dictionary[key] as Any)
                return "\(keyString):\(valueString)"
            }
            return "{\(components.joined(separator: ","))}"
        }

        if let array = value as? [Any] {
            let components = try array.map { try serialize(value: $0) }
            return "[\(components.joined(separator: ","))]"
        }

        if let string = value as? String {
            return quoteJSONString(string)
        }

        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }

        if let int = value as? Int {
            return String(int)
        }

        if let int8 = value as? Int8 {
            return String(int8)
        }

        if let int16 = value as? Int16 {
            return String(int16)
        }

        if let int32 = value as? Int32 {
            return String(int32)
        }

        if let int64 = value as? Int64 {
            return String(int64)
        }

        if let uint = value as? UInt {
            return String(uint)
        }

        if let uint8 = value as? UInt8 {
            return String(uint8)
        }

        if let uint16 = value as? UInt16 {
            return String(uint16)
        }

        if let uint32 = value as? UInt32 {
            return String(uint32)
        }

        if let uint64 = value as? UInt64 {
            return String(uint64)
        }

        if let double = value as? Double {
            return try serializeNumber(NSNumber(value: double))
        }

        if let float = value as? Float {
            return try serializeNumber(NSNumber(value: float))
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return try serializeNumber(number)
        }

        throw PayloadSignerError.unsupportedValue(Swift.type(of: value))
    }

    private static func serializeNumber(_ number: NSNumber) throws -> String {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: ["value": number],
                options: []
            )

            guard
                let json = String(data: data, encoding: .utf8),
                let colonIndex = json.firstIndex(of: ":"),
                json.hasSuffix("}")
            else {
                throw PayloadSignerError.invalidNumber(number)
            }

            let valueStart = json.index(after: colonIndex)
            let valueEnd = json.index(before: json.endIndex)
            return String(json[valueStart..<valueEnd])
        } catch {
            throw PayloadSignerError.invalidNumber(number)
        }
    }

    private static func quoteJSONString(_ string: String) -> String {
        var result = "\""

        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22:
                result += "\\\""
            case 0x5C:
                result += "\\\\"
            case 0x08:
                result += "\\b"
            case 0x0C:
                result += "\\f"
            case 0x0A:
                result += "\\n"
            case 0x0D:
                result += "\\r"
            case 0x09:
                result += "\\t"
            case 0x00...0x1F:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        result += "\""
        return result
    }

    private static func keyData(from secret: String) -> Data {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if
            !trimmed.isEmpty,
            trimmed.count % 2 == 0,
            trimmed.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil,
            let hexData = dataFromHex(trimmed)
        {
            return hexData
        }

        return Data(secret.utf8)
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        return data
    }
}
