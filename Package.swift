// swift-tools-version: 6.2

import Foundation
import CompilerPluginSupport
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let innoNetworkDependency: Package.Dependency
if let localInnoNetworkPath = ProcessInfo.processInfo.environment[
    "INNONETWORK_LOCAL_PATH"
] {
    precondition(
        FileManager.default.fileExists(
            atPath: localInnoNetworkPath + "/Package.swift"
        ),
        "INNONETWORK_LOCAL_PATH must point to an InnoNetwork package checkout."
    )
    innoNetworkDependency = .package(
        name: "InnoNetwork",
        path: localInnoNetworkPath
    )
} else {
    innoNetworkDependency = .package(
        url: "https://github.com/InnoSquadCorp/InnoNetwork.git",
        exact: "6.1.0"
    )
}

let package = Package(
    name: "InnoNetwork-Stream",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "InnoNetwork-Stream",
            targets: [
                "InnoNetworkHLS",
                "InnoNetworkHLSLive",
                "InnoNetworkHLSAVFoundation",
                "InnoNetworkHLSAudio",
            ]
        ),
        .library(name: "InnoNetworkHLS", targets: ["InnoNetworkHLS"]),
        .library(name: "InnoNetworkHLSLive", targets: ["InnoNetworkHLSLive"]),
        .library(
            name: "InnoNetworkHLSAVFoundation",
            targets: ["InnoNetworkHLSAVFoundation"]
        ),
        .library(
            name: "InnoNetworkHLSAudio",
            targets: ["InnoNetworkHLSAudio"]
        ),
    ],
    dependencies: [
        innoNetworkDependency,
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            .upToNextMinor(from: "604.0.0")
        ),
    ],
    targets: [
        .macro(
            name: "InnoNetworkStreamMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ],
            swiftSettings: strictSettings
        ),
        .target(
            name: "InnoNetworkHLS",
            dependencies: [
                .product(name: "InnoNetwork", package: "InnoNetwork"),
                "InnoNetworkStreamMacros",
            ],
            resources: [.process("Resources")],
            swiftSettings: strictSettings
        ),
        .target(
            name: "InnoNetworkHLSLive",
            dependencies: [
                .product(name: "InnoNetwork", package: "InnoNetwork"),
                "InnoNetworkHLS",
                "InnoNetworkStreamMacros",
            ],
            swiftSettings: strictSettings
        ),
        .target(
            name: "InnoNetworkHLSAVFoundation",
            dependencies: [
                .product(name: "InnoNetwork", package: "InnoNetwork"),
                "InnoNetworkHLS",
                "InnoNetworkStreamMacros",
            ],
            resources: [.process("Resources")],
            swiftSettings: strictSettings
        ),
        .target(
            name: "InnoNetworkHLSAudio",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "InnoNetworkStreamMacroTests",
            dependencies: [
                "InnoNetworkStreamMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "InnoNetworkHLSTests",
            dependencies: [
                .product(name: "InnoNetwork", package: "InnoNetwork"),
                "InnoNetworkHLS",
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "InnoNetworkHLSLiveTests",
            dependencies: [
                .product(name: "InnoNetwork", package: "InnoNetwork"),
                "InnoNetworkHLS",
                "InnoNetworkHLSLive",
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "InnoNetworkHLSAVFoundationTests",
            dependencies: [
                .product(name: "InnoNetwork", package: "InnoNetwork"),
                "InnoNetworkHLS",
                "InnoNetworkHLSLive",
                "InnoNetworkHLSAVFoundation",
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "InnoNetworkHLSAudioTests",
            dependencies: ["InnoNetworkHLSAudio"],
            swiftSettings: strictSettings
        ),
    ]
)
