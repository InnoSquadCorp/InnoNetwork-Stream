# InnoStream

HLS parsing, VOD download, live DVR, AVFoundation integration, FairPlay
workflows, and decoded-audio utilities for Apple platforms.

InnoStream is the media-streaming companion split from InnoNetwork 6. It keeps
the existing module and product names so application imports do not change:

```swift
.package(
    url: "https://github.com/InnoSquad/InnoStream.git",
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
request context, trust, redirect, metrics, and observability contracts. A
checkout beside `InnoNetwork-6-roadmap` automatically uses that local package;
other checkouts resolve the published InnoNetwork 6 dependency.

## Development

```bash
swift test --filter InnoNetworkHLSTests
swift test --filter InnoNetworkHLSLiveTests
swift test --filter InnoNetworkHLSAVFoundationTests
swift test --filter InnoNetworkHLSAudioTests
```

Strict Swift 6 concurrency is enabled for every target. The package is
intentionally Apple-only and keeps the same deployment floors as InnoNetwork.
