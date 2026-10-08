// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HLSReleaseEvidence",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "InnoNetwork-Stream", path: "../..")],
    targets: [
        .executableTarget(
            name: "HLSReleaseEvidence",
            dependencies: [
                .product(name: "InnoNetworkHLS", package: "InnoNetwork-Stream"),
                .product(name: "InnoNetworkHLSLive", package: "InnoNetwork-Stream"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
