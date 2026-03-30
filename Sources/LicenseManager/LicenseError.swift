//
//  LicenseError.swift
//  LicenseManager
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation

public enum LicenseError: Error {
    case invalidCode
    case licenseNotFound
    case licenseRevoked
    case alreadyActivatedOnAnotherMachine
    case machineMismatch
    case appDeactivated
    case invalidSignature
    case inactiveLicense
    case networkError(Error)
    case serverError(String)
    case keychainError(String)
}

extension LicenseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "Please enter a valid license code."
        case .licenseNotFound:
            return "License not found."
        case .licenseRevoked:
            return "This license has been revoked."
        case .alreadyActivatedOnAnotherMachine:
            return "This license is already activated on another machine."
        case .machineMismatch:
            return "This license is activated on a different device."
        case .appDeactivated:
            return "This application has been deactivated by the license server."
        case .invalidSignature:
            return "License signature validation failed."
        case .inactiveLicense:
            return "This license exists but has not been activated yet."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return message
        case .keychainError(let message):
            return "Secure storage error: \(message)"
        }
    }
}
