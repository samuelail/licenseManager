//
//  LicenseActivator.swift
//  Watchboat
//
//  Created by samuel Ailemen on 3/29/26.
//

import Combine
import Foundation

@MainActor
public final class LicenseActivator: ObservableObject {
    @Published public private(set) var plan: LicensePlan
    @Published public private(set) var activationError: String?

    public var isProUser: Bool {
        plan == .pro
    }

    public var maskedActivationCode: String? {
        Self.maskedCode(storedLicenseCode)
    }

    public var machineId: String {
        machineIdentifier
    }

    private let config: LicenseConfig
    private let apiClient: LicenseAPIClientProtocol
    private let keychainStore: KeychainStoreProtocol
    private let userDefaults: UserDefaults
    private let machineIdentifier: String
    private let activatedAtKey: String
    private let lastValidatedAtKey: String

    private var storedLicenseCode: String?

    public convenience init(config: LicenseConfig) {
        let apiClient = APIClient(config: config)
        let keychainStore = KeychainStore(
            service: config.keychainService,
            account: config.keychainAccount
        )
        self.init(
            config: config,
            apiClient: apiClient,
            keychainStore: keychainStore,
            userDefaults: .standard,
            machineIdentifier: MachineIdentifier.id()
        )
    }

    internal init(
        config: LicenseConfig,
        apiClient: LicenseAPIClientProtocol,
        keychainStore: KeychainStoreProtocol,
        userDefaults: UserDefaults,
        machineIdentifier: String
    ) {
        self.config = config
        self.apiClient = apiClient
        self.keychainStore = keychainStore
        self.userDefaults = userDefaults
        self.machineIdentifier = machineIdentifier

        let namespace = "Watchboat.\(config.keychainService).\(config.appId)"
        self.activatedAtKey = "\(namespace).activatedAt"
        self.lastValidatedAtKey = "\(namespace).lastValidatedAt"

        if let code = try? keychainStore.load() {
            self.storedLicenseCode = code
            self.plan = .pro
        } else {
            self.storedLicenseCode = nil
            self.plan = .free
        }

        self.activationError = nil
    }

    public func activate(code: String) async {
        let normalizedCode = normalize(code: code)
        guard isValidLicenseCode(normalizedCode) else {
            activationError = LicenseError.invalidCode.localizedDescription
            return
        }

        do {
            _ = try await apiClient.activate(
                licenseKey: normalizedCode,
                machineID: machineIdentifier
            )

            try keychainStore.save(code: normalizedCode)

            let now = Date()
            userDefaults.set(now, forKey: activatedAtKey)
            userDefaults.set(now, forKey: lastValidatedAtKey)

            storedLicenseCode = normalizedCode
            plan = .pro
            activationError = nil
        } catch {
            activationError = mapError(error).localizedDescription
        }
    }

    public func deactivate() {
        if let error = clearStoredLicense() {
            activationError = LicenseError.keychainError(error.localizedDescription).localizedDescription
        } else {
            activationError = nil
        }
        plan = .free
    }

    public func validateIfNeeded() async {
        guard let code = loadStoredLicenseCode() else {
            plan = .free
            return
        }

        if shouldForceDeactivationDueToLongOfflinePeriod() {
            _ = clearStoredLicense()
            plan = .free
            if let days = config.maxOfflineValidationDays {
                activationError = "License validation expired after \(days) days offline. Please activate again."
            } else {
                activationError = "License validation expired while offline. Please activate again."
            }
            return
        }

        guard shouldRunValidationNow() else {
            return
        }

        do {
            let result = try await apiClient.validate(
                licenseKey: code,
                machineID: machineIdentifier
            )

            if result.valid {
                userDefaults.set(Date(), forKey: lastValidatedAtKey)
                plan = .pro
                activationError = nil
            } else {
                let fallback = LicenseError.serverError("License validation failed.")
                handleValidationError(fallback)
            }
        } catch {
            handleValidationError(mapError(error))
        }
    }

    private func clearStoredLicense() -> Error? {
        do {
            try keychainStore.delete()
            storedLicenseCode = nil
            userDefaults.removeObject(forKey: activatedAtKey)
            userDefaults.removeObject(forKey: lastValidatedAtKey)
            return nil
        } catch {
            storedLicenseCode = nil
            userDefaults.removeObject(forKey: activatedAtKey)
            userDefaults.removeObject(forKey: lastValidatedAtKey)
            return error
        }
    }

    private func loadStoredLicenseCode() -> String? {
        if let storedLicenseCode {
            return storedLicenseCode
        }

        do {
            let loaded = try keychainStore.load()
            storedLicenseCode = loaded
            return loaded
        } catch {
            activationError = LicenseError.keychainError(error.localizedDescription).localizedDescription
            return nil
        }
    }

    private func handleValidationError(_ error: LicenseError) {
        switch error {
        case .networkError:
            // Keep current entitlement during temporary network failures.
            break
        case .licenseRevoked, .machineMismatch, .licenseNotFound, .inactiveLicense:
            _ = clearStoredLicense()
            plan = .free
            activationError = error.localizedDescription
        default:
            activationError = error.localizedDescription
        }
    }

    private func shouldRunValidationNow(referenceDate: Date = Date()) -> Bool {
        guard let validationInterval = config.validationInterval else {
            return false
        }

        guard let lastValidated = userDefaults.object(forKey: lastValidatedAtKey) as? Date else {
            return true
        }

        return referenceDate.timeIntervalSince(lastValidated) >= validationInterval
    }

    private func shouldForceDeactivationDueToLongOfflinePeriod(referenceDate: Date = Date()) -> Bool {
        guard let maxOfflineInterval = config.maxOfflineInterval else {
            return false
        }

        let baselineDate =
            (userDefaults.object(forKey: lastValidatedAtKey) as? Date)
            ?? (userDefaults.object(forKey: activatedAtKey) as? Date)

        guard let baselineDate else {
            return false
        }

        return referenceDate.timeIntervalSince(baselineDate) >= maxOfflineInterval
    }

    private func normalize(code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func isValidLicenseCode(_ code: String) -> Bool {
        guard !code.isEmpty else {
            return false
        }

        let pattern = #"^([A-Z0-9]{2,8}-)?[A-Z0-9]{4}(?:-[A-Z0-9]{4}){3}$"#
        return code.range(of: pattern, options: .regularExpression) != nil
    }

    private func mapError(_ error: Error) -> LicenseError {
        if let licenseError = error as? LicenseError {
            return licenseError
        }
        return .serverError(error.localizedDescription)
    }

    private static func maskedCode(_ code: String?) -> String? {
        guard let code, code.count >= 4 else {
            return nil
        }
        return "****\(code.suffix(4))"
    }
}
