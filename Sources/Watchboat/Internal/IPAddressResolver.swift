//
//  IPAddressResolver.swift
//  Watchboat
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation


internal protocol IPAddressResolving: Sendable {
    func resolveIPAddress() async -> String?
}

internal struct IPAddressResolver: IPAddressResolving {
    private let session: URLSession
    private let endpoint: URL

    internal init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.ipify.org?format=json")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    internal func resolveIPAddress() async -> String? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 2.0

        guard
            let (data, response) = try? await session.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            return nil
        }

        if
            let decoded = try? JSONDecoder().decode(PublicIPAddressResponse.self, from: data),
            Self.isValidIPAddress(decoded.ip)
        {
            return decoded.ip
        }

        if
            let ipText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            Self.isValidIPAddress(ipText)
        {
            return ipText
        }

        return nil
    }

    private static func isValidIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()

        let isIPv4 = value.withCString { pointer in
            inet_pton(AF_INET, pointer, &ipv4) == 1
        }
        if isIPv4 { return true }

        let isIPv6 = value.withCString { pointer in
            inet_pton(AF_INET6, pointer, &ipv6) == 1
        }
        return isIPv6
    }
}

private struct PublicIPAddressResponse: Decodable {
    let ip: String
}
