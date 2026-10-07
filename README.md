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
env -u INNONETWORK_LOCAL_PATH swift test --force-resolved-versions --parallel
```

When developing both packages together, select a local checkout explicitly:

```bash
INNONETWORK_LOCAL_PATH=/path/to/InnoNetwork swift test
```

Unset `INNONETWORK_LOCAL_PATH` before release preflight. Local-path testing is
for joint development; release preflight requires the published dependency.

Consumers of the earlier unreleased `InnoStream` checkout must update its
repository/path and the `.product(..., package:)` argument to
`InnoNetwork-Stream`. Existing individual product names and Swift imports are
unchanged. No old public tag or GitHub redirect is assumed to exist.

## Development

```bash
swift test --filter InnoNetworkHLSTests
swift test --filter InnoNetworkHLSLiveTests
swift test --filter InnoNetworkHLSAVFoundationTests
swift test --filter InnoNetworkHLSAudioTests
```

Strict Swift 6 concurrency is enabled for every target. The package is
intentionally Apple-only and keeps the same deployment floors as InnoNetwork.

## Release documentation

- [API stability](API_STABILITY.md)
- [Migration from InnoNetwork](docs/MIGRATION_FROM_INNONETWORK.md)
- [Package and repository naming](docs/PACKAGE_NAMING.md)
- [InnoNetwork 6.0.0 compatibility](docs/INNONETWORK_6_COMPATIBILITY.md)
- [Release policy](docs/RELEASE_POLICY.md)
- [Roadmap](docs/ROADMAP.md)
- [Draft 1.0.0 release notes](docs/releases/1.0.0.md)

## Sponsorship

Support InnoNetwork-Stream development through [GitHub Sponsors](https://github.com/sponsors/InnoSquadCorp) or [Patreon](https://www.patreon.com/c/InnoSquad).

## License

InnoNetwork-Stream is open source under the [MIT License](LICENSE).
Copyright (c) 2026 InnoSquad.
