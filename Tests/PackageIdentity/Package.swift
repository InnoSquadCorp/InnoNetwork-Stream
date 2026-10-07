// swift-tools-version: 6.2

import Foundation
import PackageDescription

let mode =
    ProcessInfo.processInfo.environment[
        "INNONETWORK_STREAM_CONSUMER_MODE"
    ] ?? "aggregate"
precondition(mode == "aggregate" || mode == "individual")

let products =
    mode == "aggregate"
    ? ["InnoNetwork-Stream"]
    : [
        "InnoNetworkHLS",
        "InnoNetworkHLSLive",
        "InnoNetworkHLSAVFoundation",
        "InnoNetworkHLSAudio",
    ]

let package = Package(
    name: "StreamPackageIdentityConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
        .package(
            url: "https://github.com/InnoSquadCorp/InnoNetwork.git",
            exact: "6.1.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "PackageIdentityConsumer",
            dependencies: products.map {
                .product(name: $0, package: "InnoNetwork-Stream")
            } + [.product(name: "InnoNetwork", package: "InnoNetwork")]
        )
    ],
    swiftLanguageModes: [.v6]
)
