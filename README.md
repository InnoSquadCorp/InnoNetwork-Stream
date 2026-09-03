# InnoStream

HLS parsing, VOD download, live DVR, AVFoundation integration, FairPlay
workflows, and decoded-audio utilities for Apple platforms.

InnoStream is the media-streaming companion split from InnoNetwork 6. It keeps
the existing module and product names so application imports do not change:

`1.0.0` is currently an unreleased draft. The dependency declaration below is
the intended post-release form, not evidence that the tag is available today.

```swift
.package(
    url: "https://github.com/InnoSquadCorp/InnoStream.git",
    .upToNextMajor(from: "1.0.0")
)
```

Choose only the products the application needs:

| Product | Purpose |
| --- | --- |
| `InnoNetworkHLS` | Playlist models, parsing, VOD and offline download |
| `InnoNetworkHLSLive` | Live reload, health, preload and DVR recording |
| `InnoNetworkHLSAVFoundation` | Playback, asset download and FairPlay |
| `InnoNetworkHLSAudio` | Decoded-audio output and pacing |

The package requires InnoNetwork 6 for bounded HTTP transfer, retry policy,
request context, trust, redirect, metrics, and observability contracts. It
will resolve the published dependency by default after InnoNetwork 6.0.0 is
tagged. Before that release, or while developing both packages together,
select a local checkout explicitly:

```bash
INNONETWORK_LOCAL_PATH=/path/to/InnoNetwork swift test
```

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
- [Release policy](docs/RELEASE_POLICY.md)
- [Roadmap](docs/ROADMAP.md)
- [Draft 1.0.0 release notes](docs/releases/1.0.0.md)
