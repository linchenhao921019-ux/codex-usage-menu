// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "codex-usage-menu", targets: ["CodexUsageMenu"])
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageMenu",
            path: "Sources/CodexUsageMenu"
        )
    ]
)
