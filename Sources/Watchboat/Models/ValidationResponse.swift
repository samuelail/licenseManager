//
//  ValidationResponse.swift
//  Watchboat
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation

internal struct ValidationPayload: Codable, Equatable {
    let valid: Bool
    let licenseKey: String?
    let machineId: String?
    let lastValidatedAt: String?
    let reason: String?
}

internal struct APIErrorData: Codable {
    let valid: Bool?
    let reason: String?
}

internal struct APIErrorEnvelope: Codable {
    let status: String?
    let message: String?
    let data: APIErrorData?
    let requestID: String?
    let requestTime: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case message
        case data
        case requestID = "request_id"
        case requestTime = "request_time"
    }
}
