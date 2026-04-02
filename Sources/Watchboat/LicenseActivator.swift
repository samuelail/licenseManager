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
    private let locallyInvalidatedKey: String

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
        let activatedAtKey = "\(namespace).activatedAt"
        let lastValidatedAtKey = "\(namespace).lastValidatedAt"
        let locallyInvalidatedKey = "\(namespace).locallyInvalidated"
        let locallyInvalidated = userDefaults.bool(forKey: locallyInvalidatedKey)

        self.activatedAtKey = activatedAtKey
        self.lastValidatedAtKey = lastValidatedAtKey
        self.locallyInvalidatedKey = locallyInvalidatedKey

        let hasActivationHistory =
            (userDefaults.object(forKey: activatedAtKey) as? Date) != nil
            || (userDefaults.object(forKey: lastValidatedAtKey) as? Date) != nil

        do {
            if let code = try keychainStore.load(), !locallyInvalidated {
                self.storedLicenseCode = code
                self.plan = .pro
            } else {
                self.storedLicenseCode = nil
                self.plan = .free
            }
        } catch {
            self.storedLicenseCode = nil
            self.plan = (!locallyInvalidated && hasActivationHistory) ? .pro : .free
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
            userDefaults.removeObject(forKey: locallyInvalidatedKey)

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
            return
        } else {
            activationError = nil
        }
        plan = .free
    }

    public func validateIfNeeded() async {
        switch loadStoredLicenseCode() {
        case .code(let code):
            if shouldForceDeactivationDueToLongOfflinePeriod() {
                markLocallyInvalidated()
                _ = clearStoredLicense(forceLocalClearOnFailure: true)
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
        case .missing:
            plan = .free
            return
        case .error:
            // Transient keychain read failures should not revoke local entitlement.
            return
        }
    }

    private func clearStoredLicense(forceLocalClearOnFailure: Bool = false) -> Error? {
        do {
            try keychainStore.delete()
            clearLocalLicenseState()
            return nil
        } catch {
            if forceLocalClearOnFailure {
                clearLocalLicenseState()
            }
            return error
        }
    }

    private func clearLocalLicenseState() {
        storedLicenseCode = nil
        userDefaults.removeObject(forKey: activatedAtKey)
        userDefaults.removeObject(forKey: lastValidatedAtKey)
    }

    private func loadStoredLicenseCode() -> StoredLicenseLoadResult {
        if isLocallyInvalidated {
            return .missing
        }

        if let storedLicenseCode {
            return .code(storedLicenseCode)
        }

        do {
            let loaded = try keychainStore.load()
            storedLicenseCode = loaded
            if let loaded {
                return .code(loaded)
            }
            return .missing
        } catch {
            activationError = LicenseError.keychainError(error.localizedDescription).localizedDescription
            return .error
        }
    }

    private func handleValidationError(_ error: LicenseError) {
        switch error {
        case .networkError:
            // Keep current entitlement during temporary network failures.
            break
        case .licenseRevoked, .machineMismatch, .licenseNotFound, .inactiveLicense:
            markLocallyInvalidated()
            _ = clearStoredLicense(forceLocalClearOnFailure: true)
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

    private var isLocallyInvalidated: Bool {
        userDefaults.bool(forKey: locallyInvalidatedKey)
    }

    private func markLocallyInvalidated() {
        userDefaults.set(true, forKey: locallyInvalidatedKey)
    }

    private enum StoredLicenseLoadResult {
        case code(String)
        case missing
        case error
    }

    private static func maskedCode(_ code: String?) -> String? {
        guard let code, code.count >= 4 else {
            return nil
        }
        return "****\(code.suffix(4))"
    }
}
