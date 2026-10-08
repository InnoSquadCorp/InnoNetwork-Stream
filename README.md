# InnoNetwork-Stream

HLS parsing, VOD download, live DVR, AVFoundation integration, FairPlay
workflows, and decoded-audio utilities for Apple platforms.

InnoNetwork-Stream (formerly InnoStream) is the media-streaming companion split
from InnoNetwork 6. It keeps the existing module and product names so
application imports do not change.

`6.1.1` is an unpublished release candidate. The dependency declaration below is
the intended post-release form, not evidence that the tag is available today.
Local official-tool acceptance is documented in [Local HLS evidence](docs/LOCAL_HLS_EVIDENCE.md);
real-device prerequisites are in [Device acceptance](docs/DEVICE_ACCEPTANCE.md).

```swift
.package(
    url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git",
    .upToNextMajor(from: "6.1.1")
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

The root package and aggregate/individual consumer pin published InnoNetwork
`6.1.1` exactly. `Package.resolved` records tag commit
`44e4ca28c50c03f817231a077c0f3bdfdbc859c8` and the reviewed transitive versions.
CI and CodeQL use the published graph. The dependency gate checks the exact
manifest requirement, tag version/revision, active graph and actual checkouts,
including when SwiftPM reuses cached state.

Validate and test the published dependency with:

```bash
env -u INNONETWORK_LOCAL_PATH bash Scripts/check_innonetwork_dependency.sh
env -u INNONETWORK_LOCAL_PATH bash Scripts/swiftpm.sh test --force-resolved-versions --parallel
env -u INNONETWORK_LOCAL_PATH bash Scripts/run_local_release_preflight.sh --quick
```

When developing both packages together, select a local checkout explicitly:

```bash
INNONETWORK_LOCAL_PATH=/path/to/InnoNetwork bash Scripts/swiftpm.sh test
```

Unset `INNONETWORK_LOCAL_PATH` before validating the published graph. A local
path or branch cannot satisfy release validation. Stream `6.1.1` remains an
unpublished candidate; Core publication does not authorize a Stream release. See the
[Core dependency contract](docs/CORE_DEVELOPMENT.md).

Consumers of the earlier unreleased `InnoStream` checkout must update its
repository/path and the `.product(..., package:)` argument to
`InnoNetwork-Stream`. Existing individual product names and Swift imports are
unchanged. No old public tag or GitHub redirect is assumed to exist.

## AI library skill

The library-owned [InnoNetwork-Stream skill](skills/README.md) supports the planned
stable 6.1.x line from an exact 6.1.1 candidate commit. It includes shared Codex
and Claude Code guidance, public consumer tests and a remote dependency validator.
The central plugin collects this source as a pinned snapshot; see the
[validation record](skills/validation.md) for the tested baseline and limits.

## Development

The [production-candidate review and evidence](docs/PRODUCTION_HARDENING_2026_10_02.md)
cover all four modules, six macro-first workflows and the remaining device/service
and publication boundaries. Local validation does not imply a published release.

For incremental local feedback, select reverse-dependent suites from an explicit
baseline: `bash Scripts/run_affected_tests.sh --base <commit>`. Inspect the plan
with `--dry-run`. Development milestones require
`bash Scripts/run_local_release_preflight.sh --full` against the exact published
Core pin, including external consumers and HLS runtime checks.

```bash
bash Scripts/swiftpm.sh test --filter InnoNetworkHLSTests
bash Scripts/swiftpm.sh test --filter InnoNetworkHLSLiveTests
bash Scripts/swiftpm.sh test --filter InnoNetworkHLSAVFoundationTests
bash Scripts/swiftpm.sh test --filter InnoNetworkHLSAudioTests
```

Strict Swift 6 concurrency is enabled for every target. The package is
intentionally Apple-only and keeps the same deployment floors as InnoNetwork.

## Macro-first download workflows (6.1.1 candidate)

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

The compiler plugin shares SwiftSyntax 604.0.x with InnoNetwork 6.1.1. Runtime
targets never import SwiftSyntax. Macro expressions accept positive decimal
integer literals; resource limits fit every supported platform's signed
32-bit `Int`, output limits use `Int64`, and concurrency is `1...8`.
Keep Xcode's package/plugin trust approval for local development; reviewed,
locked CI may use the narrow `-skipMacroValidation` flag, not a global trust
setting or package-plugin bypass. Both macro expansion diagnostics and actual
external consumer compilation are required for final candidate qualification.

See [the ordered implementation plan](docs/MACRO_FIRST_REDESIGN.md) for
local execution evidence and the remaining external release gates.

## Macro-first offline packages (6.1.1 candidate)

Use a package instead of concatenating a single file when preserving the HLS
presentation and selected audio/subtitle timelines matters. This async operation
runs in the calling task: cancelling that task cancels the unfinished download.
The receipt is returned only after atomic publication; an existing destination
is never overwritten. The default keeps resumable checkpoints after interruption.

```swift
import Foundation
import InnoNetworkHLS

@HLSOfflinePackageDefinition(
    maximumMediaResourceBytes: 8_388_608,
    maximumTotalDownloadBytes: 268_435_456,
    maximumConcurrentResourceTransfers: 3
)
enum OfflineMovie {}

func saveOfflineMovie(source: URL, destination: URL) async throws -> HLSOfflinePackageReceipt {
    try await OfflineMovie.downloadPackage(sourceURL: source, destinationDirectoryURL: destination)
}
```

`prepare(...)` is an advisory, media-free preview; download revalidates its plan.
Pass caller-owned transport/context/request policy to these entry points. Dynamic
rendition, retry and storage settings use `HLSOfflinePackageConfiguration.validated`
through `HLSOfflinePackageDefining`; both paths run the same bounded package engine.
Request policies may adapt URLs and headers but must preserve a bodyless GET.

For independent progress observation, use `try OfflineMovie.start(...)` and
retain the returned `HLSOfflinePackageTask`. `try operation.events()` provides
bounded, sequenced events; `try await operation.receipt()` confirms atomic
publication. Cancelling an observer or receipt waiter does not stop the producer:
call `operation.cancel()` explicitly, or release the owner. The default preserves
resumable checkpoints, not an incomplete destination. A committed package is not
removed by late cancellation. The legacy `downloader.download(...)` stream still
cancels its producer when observation terminates. These ownership contracts are
intentionally different; the async convenience above remains caller-owned.

## Live, DVR, native playback and metadata (6.1.1 candidate)

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

All six definitions delegate to throwing immutable `validated()` factories.
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
- [Historical InnoNetwork 6.0.0 compatibility](docs/INNONETWORK_6_COMPATIBILITY.md)
- [Release policy](docs/RELEASE_POLICY.md)
- [Roadmap](docs/ROADMAP.md)
- [6.1.1 candidate release notes](docs/releases/6.1.1.md)

## Sponsorship

Support InnoNetwork-Stream development through [GitHub Sponsors](https://github.com/sponsors/InnoSquadCorp) or [Patreon](https://www.patreon.com/15188938/join).

## License

InnoNetwork-Stream is open source under the [MIT License](LICENSE).
Copyright (c) 2026 InnoSquad.
