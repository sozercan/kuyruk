// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Kuyruk",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(
            name: "Kuyruk",
            targets: ["Kuyruk"]),
        .executable(
            name: "api-explorer",
            targets: ["APIExplorer"]),
    ],
    dependencies: [
        // No third-party dependencies (first-party only policy)
    ],
    targets: [
        // Main app executable
        .executableTarget(
            name: "Kuyruk",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]),
        // API Explorer CLI tool
        .executableTarget(
            name: "APIExplorer",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]),
        // Unit tests
        .testTarget(
            name: "KuyrukTests",
            dependencies: ["Kuyruk"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]),
    ],
    swiftLanguageModes: [.v6])
