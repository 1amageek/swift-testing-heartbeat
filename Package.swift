// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TestHeartbeat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TestHeartbeat",
            targets: ["TestHeartbeat"]
        )
    ],
    targets: [
        .target(
            name: "TestHeartbeat"
        ),
        .testTarget(
            name: "TestHeartbeatTests",
            dependencies: ["TestHeartbeat"]
        )
    ]
)
