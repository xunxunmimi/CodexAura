// swift-tools-version: 5.10
// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import PackageDescription

let package = Package(
    name: "CodexAura",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexAura", targets: ["CodexAura"])
    ],
    targets: [
        .executableTarget(
            name: "CodexAura",
            path: "Sources/CodexAura"
        ),
        .testTarget(name: "CodexAuraTests", dependencies: ["CodexAura"], path: "Tests/CodexAuraTests")
    ]
)
