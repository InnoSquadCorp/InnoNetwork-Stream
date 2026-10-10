// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "StreamSkillConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git",
                 exact: "6.1.1"),
        .package(url: "https://github.com/InnoSquadCorp/InnoNetwork.git", exact: "6.1.1")
    ],
    targets: [
        .target(name: "StreamSkillExample", dependencies: [
            .product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream"),
            .product(name: "InnoNetwork", package: "InnoNetwork")
        ]),
        .testTarget(name: "StreamSkillExampleTests", dependencies: ["StreamSkillExample"])
    ],
    swiftLanguageModes: [.v6]
)
