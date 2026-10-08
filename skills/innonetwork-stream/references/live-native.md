# Live, DVR and native media

```swift
import Foundation
import AVFoundation
import InnoNetworkHLS
import InnoNetworkHLSLive
import InnoNetworkHLSAVFoundation

@HLSLiveDefinition(minimumPollingMilliseconds: 500, maximumPollingMilliseconds: 30_000,
                   requestTimeoutSeconds: 45)
enum ChannelWatch {}
@HLSDVRDefinition(maximumDurationSeconds: 1800, maximumSegmentCount: 900)
enum ChannelArchive {}
@HLSPlaybackDefinition(maximumPeakBitRate: 10_000_000, maximumWidth: 1920, maximumHeight: 1080)
enum PlaybackProfile {}
```

`try ChannelWatch.watch(from: source, session: session)` returns
`HLSLiveWatching`. Retain it. `observations()` is a bounded throwing stream;
`finalSnapshot()` awaits ENDLIST. Cancelling observers does not stop reloads;
`cancel()` or releasing the owner does. Zero/slow observers do not own the work.
Dynamic settings use `HLSLiveDefining` + `HLSLiveConfiguration.validated(...)`.

`try ChannelArchive.startRecording(from: source, to: directory, client: client)`
returns `HLSLiveDVRRecording` and reuses the caller's configured Live client,
including transport, steering and key policy. To finish use
`try await recording.stopAndCommit()`; to discard use
`await recording.cancelAndDiscard()`. First terminal intent wins. `receipt()`
and `observations()` only observe; neither issues stop or discard. The legacy
`events` property is single-channel. DVR checkpoint recovery is opt-in; do not
invent an unconditional resume guarantee. Dynamic: `HLSDVRDefining` +
`HLSLiveDVRConfiguration.validated(...)`.

## Playback and native background tasks

`try await PlaybackProfile.apply(to: playerItem)` requires MainActor and returns
`HLSPlaybackConfigurationResult`. The application owns the `AVPlayerItem`, player,
play/pause state and lifetime. The macro only supplies settings. Dynamic settings
use `HLSPlaybackDefining` + `HLSPlaybackConfiguration.validated(...)`.

For system-managed asset downloads use `HLSAssetDownloadSession`; inspect its
exact platform guards/signatures in the resolved source. Keep system task IDs,
session identifier and restoration mapping. Cancelling an event observer does
not cancel a native download. Call
`handleBackgroundSessionCompletion(_:completion:)` on MainActor with UIKit's
ordinary escaping callback. On reconnection,
`init(configuration:backgroundSessionCompletion:)` registers before restored
event delivery. Do not replace this with a foreground handle/checkpoint model.

## FairPlay

`HLSFairPlaySession` is MainActor. Streaming and persistent-key workflows use
caller-owned certificate/content identifier, `HLSFairPlayLicenseTransporting`
and (for persistent keys) `HLSFairPlayPersistentKeyStoring`. Check the selected
platform's public declarations; these FairPlay files exclude tvOS. Preserve
key ownership, retry and expiration policies. Parsing KEY tags or compiling a
mock does not validate entitlement, license service, device provisioning or DRM
playback. Use the repository's device/FairPlay acceptance procedures with actual
app-owned credentials when requested; do not log certificate/SPC/CKC/key bytes.

## Decoded audio

Import `InnoNetworkHLSAudio`. Public decoded-audio declarations are inside
`#if compiler(>=6.4)` and require OS 27 availability; the general package floor
does not make these APIs available on OS 16. `HLSDecodedAudioOutput` is MainActor
and attaches to a caller-owned player item. Use
`try HLSDecodedAudioConfiguration.float32(sampleRate: 48_000, channelCount: 2)`.
Read with `nextSample()` or `pacedSamples(configuration:)`, one outstanding read
only. Skip PCM processing for marker-only samples and reset analysis state on
`sequenceWasRestarted`. Inspect delivered format, which can differ from requested.

Cancellation ends a client wait without detaching; a pending native read may
still block a new read until it completes. `detach()` is terminal; a paced
sequence retains but does not detach the output. The app owns retained buffers.
`HLSAudioMixProcessingTap` is a distinct real-time callback path, unavailable on
watchOS and for FairPlay-protected audio. Never allocate, block, perform I/O,
escape pointers or actor-hop inside that callback. No DRM bypass or automatic
playback control is implied. Consult exact source for full callback signatures.
