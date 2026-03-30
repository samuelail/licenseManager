// swift-tools-version: 6.0
//
//  Package.swift
//  Watchboat
//
//  Created by samuel Ailemen on 3/29/26.
//
import PackageDescription

let package = Package(
    name: "Watchboat",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Watchboat",
            targets: ["Watchboat"]
        )
    ],
    targets: [
        .target(
            name: "Watchboat",
            path: "Sources/Watchboat",
            linkerSettings: [
                .linkedFramework("IOKit", .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "WatchboatTests",
            dependencies: ["Watchboat"],
            path: "Tests/WatchboatTests"
        )
    ]
)
