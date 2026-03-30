//
//  ActivationResponse.swift
//  LicenseManager
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation

internal struct APIEnvelope<T: Decodable>: Decodable {
    let status: String
    let message: String
    let data: T?
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

internal struct ActivationPayload: Codable, Equatable {
    let licenseKey: String
    let machineId: String
    let activatedAt: String?
}
