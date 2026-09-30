# InnoNetwork-Stream

HLS parsing, VOD download, live DVR, AVFoundation integration, FairPlay
workflows, and decoded-audio utilities for Apple platforms.

InnoNetwork-Stream (formerly InnoStream) is the media-streaming companion split
from InnoNetwork 6. It keeps the existing module and product names so
application imports do not change.

`1.0.0` is currently an unreleased draft. The dependency declaration below is
the intended post-release form, not evidence that the tag is available today.

```swift
.package(
    url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git",
    .upToNextMajor(from: "1.0.0")
)
```

Select all four modules with one product in the consuming target:

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream")
```

The repository, package display name, and all-in-one product use
`InnoNetwork-Stream`; SwiftPM's canonical package identity is
`innonetwork-stream`. Swift module names cannot contain a hyphen. Swift source
continues to use the modules it needs:

```swift
import InnoNetworkHLS
import InnoNetworkHLSLive
import InnoNetworkHLSAVFoundation
import InnoNetworkHLSAudio
```

Alternatively, choose only the individual products the application needs:

| Product | Purpose |
| --- | --- |
| `InnoNetwork-Stream` | All four modules below, selected as one dependency |
| `InnoNetworkHLS` | Playlist models, parsing, VOD and offline download |
| `InnoNetworkHLSLive` | Live reload, health, preload and DVR recording |
| `InnoNetworkHLSAVFoundation` | Playback, asset download and FairPlay |
| `InnoNetworkHLSAudio` | Decoded-audio output and pacing |

The package requires InnoNetwork 6 for bounded HTTP transfer, retry policy,
request context, trust, redirect, metrics, and observability contracts. It
resolves the published InnoNetwork `6.0.0` tag by default. The checked-in
`Package.resolved` records its release revision and the transitive dependency
versions used for compatibility validation. CI, CodeQL, and release preflight
resolve that lock without selecting InnoNetwork `main`.
An explicit dependency gate verifies active remote versions and revisions
against the resolved graph and checkouts, including when SwiftPM reuses cached state.

Resolve and test the published dependency with:

```bash
env -u INNONETWORK_LOCAL_PATH bash Scripts/check_innonetwork_dependency.sh
env -u INNONETWORK_LOCAL_PATH bash Scripts/swiftpm.sh test --force-resolved-versions --parallel
```

When developing both packages together, select a local checkout explicitly:

```bash
INNONETWORK_LOCAL_PATH=/path/to/InnoNetwork bash Scripts/swiftpm.sh test
```

Unset `INNONETWORK_LOCAL_PATH` before release preflight. Local-path testing is
for joint development; release preflight requires the published dependency.

Consumers of the earlier unreleased `InnoStream` checkout must update its
repository/path and the `.product(..., package:)` argument to
`InnoNetwork-Stream`. Existing individual product names and Swift imports are
unchanged. No old public tag or GitHub redirect is assumed to exist.

## Development

For incremental local feedback, select reverse-dependent suites from an explicit
baseline: `bash Scripts/run_affected_tests.sh --base <commit>`. Inspect the plan
with `--dry-run`. This does not replace full CI/release preflight; final candidates
still require `bash Scripts/run_local_release_preflight.sh --full`.

```bash
bash Scripts/swiftpm.sh test --filter InnoNetworkHLSTests
bash Scripts/swiftpm.sh test --filter InnoNetworkHLSLiveTests
bash Scripts/swiftpm.sh test --filter InnoNetworkHLSAVFoundationTests
bash Scripts/swiftpm.sh test --filter InnoNetworkHLSAudioTests
```

Strict Swift 6 concurrency is enabled for every target. The package is
intentionally Apple-only and keeps the same deployment floors as InnoNetwork.

## Macro-first download workflows (Draft)

Declare a workflow with checked constant limits, then start its explicitly
owned operation. No requests start during macro expansion or configuration.

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

The handle owns work; cancelling an event subscription or a receipt waiter does
not cancel another consumer's operation. Use `operation.cancel()` explicitly,
or propagate foreground scope cancellation as above. Retain the handle until
completion. `events()` admits up to 64 independent subscriptions, each with a
newest-16 buffer and sequence/drop metadata. `receipt()` is the authoritative
terminal result, even if progress was coalesced. Completed output wins late
cancellation and is never implicitly deleted.

Pass caller-owned `session`, `requestContext` and `requestPolicy` to `start` or
`makeDownloader` for trust/authentication/observation. `configuration()` only
constructs settings. For dynamic settings or compiler-plugin recovery, use
`HLSDownloadConfiguration.validated(...)` / `HLSDownloadDefining` as the
advanced equivalent; the older `advanced(...)` API retains documented clamping.

The compiler plugin shares SwiftSyntax 603.0.x with InnoNetwork 6. Runtime
targets never import SwiftSyntax. Macro expressions accept positive decimal
integer literals; resource limits fit every supported platform's signed
32-bit `Int`, output limits use `Int64`, and concurrency is `1...8`.
Keep Xcode's package/plugin trust approval for local development; reviewed,
locked CI may use the narrow `-skipMacroValidation` flag, not a global trust
setting or package-plugin bypass. Both macro expansion diagnostics and actual
external consumer compilation are required before stabilizing this Draft API.

See [the ordered implementation plan](docs/MACRO_FIRST_REDESIGN.md) for
local execution evidence and the remaining external release gates.

## Live, DVR, native playback and metadata (Draft)

```swift
import AVFoundation
import Foundation
import InnoNetworkHLS
import InnoNetworkHLSLive
import InnoNetworkHLSAVFoundation

@HLSLiveDefinition
enum ChannelWatch {}
@HLSDVRDefinition(maximumDurationSeconds: 1800, maximumSegmentCount: 900)
enum ChannelArchive {}
@HLSPlaybackDefinition(maximumPeakBitRate: 10_000_000, maximumWidth: 1920, maximumHeight: 1080)
enum PlaybackProfile {}
@HLSCatalogDefinition(maximumEntries: 128, maximumSnapshotBytes: 65_536)
enum MediaLibrary {}

func watchChannel(source: URL, session: URLSession) throws -> HLSLiveWatching {
    try ChannelWatch.watch(from: source, session: session)
}
func recordChannel(source: URL, destination: URL, client: HLSLivePlaylistClient) throws -> HLSLiveDVRRecording {
    try ChannelArchive.startRecording(from: source, to: destination, client: client)
}
@MainActor
func configurePlayback(item: AVPlayerItem) async throws -> HLSPlaybackConfigurationResult {
    try await PlaybackProfile.apply(to: item)
}
func makeMediaLibrary(store: any HLSMediaCatalogPersisting) throws -> HLSMediaCatalog {
    try MediaLibrary.makeCatalog(persistence: store)
}
```

Retain the foreground watch/recording until completion and issue explicit stop
or cancellation when the application scope ends. Observations are independent;
`finalSnapshot()` waits for ENDLIST, and `receipt()` observes DVR's committed
result without issuing stop/discard. DVR still uses the caller's configured Live
client for transport, steering and key policy. Native playback remains MainActor
and caller-owned. System background task restoration and realtime audio are
not converted into foreground handle ownership.

All five definitions delegate to throwing immutable `validated()` factories.
The corresponding `*Defining` protocols are the dynamic/manual compiler-plugin
recovery equivalent, not a different network or storage implementation.
Generated pure `configuration()` factories are nonisolated even on a global-actor
declaration. Native `apply(to:)` remains MainActor. Complete local preflight
uses Xcode 27/Swift 6.4; the separate Swift 6.2 core test lane remains supported.
Decoded-audio declarations are compiler-6.4-gated, not an identical 6.2 surface.
See [migration](docs/MACRO_FIRST_MIGRATION.md), [optional metadata storage](docs/MEDIA_CATALOG.md)
and [failure/incident contracts](docs/FAILURE_AND_INCIDENT_CONTRACT.md).

## Release documentation

- [API stability](API_STABILITY.md)
- [Migration from InnoNetwork](docs/MIGRATION_FROM_INNONETWORK.md)
- [Package and repository naming](docs/PACKAGE_NAMING.md)
- [InnoNetwork 6.0.0 compatibility](docs/INNONETWORK_6_COMPATIBILITY.md)
- [Release policy](docs/RELEASE_POLICY.md)
- [Roadmap](docs/ROADMAP.md)
- [Draft 1.0.0 release notes](docs/releases/1.0.0.md)

## License

InnoNetwork-Stream is open source under the [MIT License](LICENSE).
Copyright (c) 2026 InnoSquad.
