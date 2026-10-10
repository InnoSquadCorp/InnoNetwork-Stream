# InnoNetwork-Stream

[English](README.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Русский](README.ru.md)

`6.1.1` is published. [6.1.1](https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1)

<!-- section:1 -->
## Scope

HLS parsing, bounded VOD/offline downloads, live/DVR, native playback/FairPlay integration and decoded audio. This is a media library, not a player UI, CDN, transcoder or DRM service. Choose the aggregate InnoNetwork-Stream product or individual InnoNetworkHLS, InnoNetworkHLSLive, InnoNetworkHLSAVFoundation and InnoNetworkHLSAudio products. Those four names are the Swift modules; there is no InnoNetworkStream module.

These seven quick starts cover the same stable release, setup, example, lifecycle and migration scope. The detailed English guide remains the shared advanced reference; translations do not imply native-speaker review.

<!-- section:2 -->
## Requirements

Swift 6.2+, Swift 6 language mode; Apple platforms only: iOS 16+, macOS 14+, tvOS 16+, watchOS 9+, visionOS 1+. Core is pinned to InnoNetwork 6.1.1 exactly.

Decoded-audio declarations additionally require Swift 6.4/Xcode 27 and supported OS 27 APIs; check symbol availability. The Swift 6.2 surface is not identical. All six workflow macros use throwing validated configuration factories. configuration() does not start network work.

<!-- section:3 -->
## Installation

Add these package dependencies, then the products to your consuming target.

```swift
.package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git", from: "6.1.1"),
```

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream"),
```

<!-- section:4 -->
## Quick start

The snippets below are source-checked examples, not a new compilation or device-test result. A consuming application owns its URLs, credentials and transport policies.

```swift
import Foundation
import InnoNetworkHLS

@HLSDownloadDefinition(
    maximumMediaResourceBytes: 8_388_608,
    maximumTotalDownloadBytes: 268_435_456,
    maximumConcurrentResourceTransfers: 3
)
enum MovieDownload {}

func saveMovie(source: URL, destination: URL) async throws -> HLSDownloadReceipt {
    let operation = try MovieDownload.start(
        sourceURL: source,
        destinationURL: destination
    )
    return try await withTaskCancellationHandler {
        try await operation.receipt()
    } onCancel: {
        operation.cancel()
    }
}
```

<!-- section:5 -->
## Ownership and failures

Retain the operation handle. Cancelling an event observer or receipt waiter does not stop the producer; explicitly call cancel(), or propagate task cancellation as shown. receipt() is the terminal authority; events() has up to 64 subscriptions, each retaining the newest 16 events with sequence/drop metadata. Completed output wins late cancellation and is not deleted. Errors must be caught by the caller; inspect typed failure/incident contracts rather than retaining URLs, credentials or media payloads in logs.

The async offline downloadPackage convenience runs in the caller’s task and inherits its cancellation; explicit offline start handles have independent observation and cancellation. Native background tasks use system restoration semantics. FairPlay credentials, entitlements and key storage remain application-owned; library publication is not service/device certification.

<!-- section:6 -->
## Migration

From old Core HLS products, add this sibling dependency while keeping the same individual imports. From the unpublished InnoStream checkout, update URL, package identity and product package: arguments. Do not assume an old public tag or redirect. The migration guide distinguishes older stream-owned downloads from current retained handles and parser-produced playlist documents.

<!-- section:7 -->
## Documentation and verification

Run the listed checks from this repository. Static checks do not replace Swift builds, macro expansion, DocC or device/service acceptance. Unset INNONETWORK_LOCAL_PATH when checking the published dependency graph.

- [Technical guide (English)](docs/GUIDE.md)
- [Documentation map / historical evidence](docs/README.md)
- [Migration (English)](docs/MACRO_FIRST_MIGRATION.md)
- [API stability](API_STABILITY.md)
- [AI development skill](skills/README.md)
- [Release qualification record](docs/releases/6.1.1.md)
- [Roadmap](docs/ROADMAP.md)
- [MIT License](LICENSE)

```bash
bash Scripts/validate_docs_release_state.sh
python3 Scripts/check_readme_parity.py
env -u INNONETWORK_LOCAL_PATH bash Scripts/swiftpm.sh test --force-resolved-versions --parallel
```
