//
//  APIClient.swift
//  LicenseManager
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation

internal protocol LicenseAPIClientProtocol: Sendable {
    func activate(licenseKey: String, machineID: String) async throws -> ActivationPayload
    func validate(licenseKey: String, machineID: String) async throws -> ValidationPayload
}

internal actor APIClient: LicenseAPIClientProtocol {
    private let config: LicenseConfig
    private let signer: PayloadSigner
    private let session: URLSession
    private let decoder: JSONDecoder

    internal init(
        config: LicenseConfig,
        signer: PayloadSigner = PayloadSigner(),
        session: URLSession = .shared
    ) {
        self.config = config
        self.signer = signer
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    internal func activate(licenseKey: String, machineID: String) async throws -> ActivationPayload {
        let body: [String: Any] = [
            "license_key": licenseKey,
            "machine_id": machineID
        ]

        let (statusCode, data) = try await send(path: "v1/activate", body: body)

        if statusCode == 200 {
            let envelope = try decodeEnvelope(ActivationPayload.self, from: data)
            guard let payload = envelope.data else {
                throw LicenseError.serverError("Activation response missing payload.")
            }
            return payload
        }

        let errorEnvelope = decodeErrorEnvelope(from: data)
        throw mapError(statusCode: statusCode, envelope: errorEnvelope)
    }

    internal func validate(licenseKey: String, machineID: String) async throws -> ValidationPayload {
        let body: [String: Any] = [
            "license_key": licenseKey,
            "machine_id": machineID
        ]

        let (statusCode, data) = try await send(path: "v1/validate", body: body)

        if statusCode == 200 {
            let envelope = try decodeEnvelope(ValidationPayload.self, from: data)
            guard let payload = envelope.data else {
                throw LicenseError.serverError("Validation response missing payload.")
            }
            if payload.valid {
                return payload
            }
            throw mapValidationReason(payload.reason, fallbackMessage: envelope.message)
        }

        let errorEnvelope = decodeErrorEnvelope(from: data)
        throw mapError(statusCode: statusCode, envelope: errorEnvelope)
    }

    private func send(path: String, body: [String: Any]) async throws -> (Int, Data) {
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appId, forHTTPHeaderField: "X-App-Id")

        do {
            let signature = try signer.sign(body: body, secret: config.appSecret)
            request.setValue(signature, forHTTPHeaderField: "X-Signature")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw LicenseError.serverError("Failed to create signed request: \(error.localizedDescription)")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LicenseError.serverError("Invalid response from license server.")
            }
            return (httpResponse.statusCode, data)
        } catch let licenseError as LicenseError {
            throw licenseError
        } catch {
            throw LicenseError.networkError(error)
        }
    }

    private func makeURL(path: String) -> URL {
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return config.baseURL.appendingPathComponent(cleanedPath)
    }

    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> APIEnvelope<T> {
        do {
            return try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            throw LicenseError.serverError("Failed to parse server response: \(error.localizedDescription)")
        }
    }

    private func decodeErrorEnvelope(from data: Data) -> APIErrorEnvelope? {
        try? decoder.decode(APIErrorEnvelope.self, from: data)
    }

    private func mapValidationReason(_ reason: String?, fallbackMessage: String?) -> LicenseError {
        switch reason?.lowercased() {
        case "revoked":
            return .licenseRevoked
        case "machine_mismatch":
            return .machineMismatch
        case "inactive":
            return .inactiveLicense
        default:
            return .serverError(fallbackMessage ?? "License validation failed.")
        }
    }

    private func mapError(statusCode: Int, envelope: APIErrorEnvelope?) -> LicenseError {
        let reason = envelope?.data?.reason?.lowercased()
        let message = envelope?.message ?? "Unexpected server response."
        let normalizedMessage = message.lowercased()

        if let reason {
            let mapped = mapValidationReason(reason, fallbackMessage: message)
            if case .serverError = mapped {
                // Fall through and use HTTP status mapping.
            } else {
                return mapped
            }
        }

        switch statusCode {
        case 400:
            if normalizedMessage.contains("required") {
                return .invalidCode
            }
            if normalizedMessage.contains("inactive") {
                return .inactiveLicense
            }
            return .serverError(message)
        case 401:
            return .invalidSignature
        case 403:
            if normalizedMessage.contains("deactivated") {
                return .appDeactivated
            }
            if normalizedMessage.contains("revoked") {
                return .licenseRevoked
            }
            return .serverError(message)
        case 404:
            return .licenseNotFound
        case 409:
            return .alreadyActivatedOnAnotherMachine
        case 500...599:
            return .serverError(message)
        default:
            return .serverError(message)
        }
    }
}
