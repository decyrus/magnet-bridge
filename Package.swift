// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MagnetBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MagnetBridgeCore", targets: ["MagnetBridgeCore"])
    ],
    targets: [
        .target(
            name: "MagnetBridgeCore",
            path: "Sources/MagnetBridgeCore"
        ),
        .testTarget(
            name: "MagnetBridgeCoreTests",
            dependencies: ["MagnetBridgeCore"],
            path: "Tests/MagnetBridgeCoreTests"
        )
    ]
)
