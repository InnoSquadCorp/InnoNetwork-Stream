# Migrating HLS products from InnoNetwork

InnoNetwork 6 removes its four HLS products. InnoNetwork-Stream 6.1.1 preserves their
product and module names, so Swift imports remain unchanged while package
ownership changes.

## Package manifest

Before:

```swift
dependencies: [
    .package(
        url: "https://github.com/InnoSquadCorp/InnoNetwork.git",
        .upToNextMajor(from: "5.1.0")
    )
],
targets: [
    .target(
        name: "MediaFeature",
        dependencies: [
            .product(name: "InnoNetwork", package: "InnoNetwork"),
            .product(name: "InnoNetworkHLS", package: "InnoNetwork"),
        ]
    )
]
```

After:

```swift
dependencies: [
    .package(
        url: "https://github.com/InnoSquadCorp/InnoNetwork.git",
        exact: "6.1.1"
    ),
    .package(
        url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git",
        .upToNextMajor(from: "6.1.1")
    ),
],
targets: [
    .target(
        name: "MediaFeature",
        dependencies: [
            .product(name: "InnoNetwork", package: "InnoNetwork"),
            .product(name: "InnoNetworkHLS", package: "InnoNetwork-Stream"),
        ]
    )
]
```

Apply the same package-owner change to `InnoNetworkHLSLive`,
`InnoNetworkHLSAVFoundation`, and `InnoNetworkHLSAudio`. Existing source keeps
using `import InnoNetworkHLS` and the corresponding unchanged module names.

To select all four modules at once, replace the individual HLS product
dependencies with:

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream")
```

This is a product name, not a Swift import. Consumers of the original
unreleased `InnoStream` checkout must update its path/URL and `package:`
arguments to the new name. No old published tag or GitHub redirect is assumed.

## Validation

1. Remove stale SwiftPM pins and generated project state using the consuming
   project's documented regeneration workflow.
2. Resolve InnoNetwork 6.1.1 and InnoNetwork-Stream 6.1.1 from their published tags without a
   local path override.
3. Build every target that imports an HLS module on its supported Apple
   platform.
4. Run at least one representative playlist parse/download test and any
   application-owned FairPlay acceptance flow.

`INNONETWORK_LOCAL_PATH` is only a development bridge. A build that relies on
the sibling checkout does not prove that a clean machine can resolve the
released package graph.
