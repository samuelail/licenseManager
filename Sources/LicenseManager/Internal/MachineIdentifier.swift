//
//  MachineIdentifier.swift
//  LicenseManager
//
//  Created by samuel Ailemen on 3/29/26.
//

import Foundation

#if os(macOS)
import IOKit
#endif

#if canImport(UIKit)
import UIKit
#endif

internal enum MachineIdentifier {
    private static let fallbackKey = "LicenseManager.machineIdentifier"

    @MainActor
    internal static func id() -> String {
#if os(macOS)
        return macOSHardwareIdentifier()
#elseif canImport(UIKit)
        if let identifier = UIDevice.current.identifierForVendor?.uuidString, !identifier.isEmpty {
            return identifier
        }
        return fallbackIdentifier()
#else
        return fallbackIdentifier()
#endif
    }

#if os(macOS)
    private static func macOSHardwareIdentifier() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        guard service != 0 else {
            return fallbackIdentifier()
        }

        defer { IOObjectRelease(service) }

        guard
            let uuid = IORegistryEntryCreateCFProperty(
                service,
                kIOPlatformUUIDKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String,
            !uuid.isEmpty
        else {
            return fallbackIdentifier()
        }

        return uuid
    }
#endif

    private static func fallbackIdentifier() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: fallbackKey), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString
        defaults.set(generated, forKey: fallbackKey)
        return generated
    }
}
