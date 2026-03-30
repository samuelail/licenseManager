// swift-tools-version: 6.0
//
//  Package.swift
//  LicenseManager
//
//  Created by samuel Ailemen on 3/29/26.
//
import PackageDescription

let package = Package(
    name: "LicenseManager",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "LicenseManager",
            targets: ["LicenseManager"]
        )
    ],
    targets: [
        .target(
            name: "LicenseManager",
            path: "Sources/LicenseManager",
            linkerSettings: [
                .linkedFramework("IOKit", .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "LicenseManagerTests",
            dependencies: ["LicenseManager"],
            path: "Tests/LicenseManagerTests"
        )
    ]
)
