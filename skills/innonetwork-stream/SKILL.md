---
name: innonetwork-stream
description: Implement, test, diagnose, or migrate Swift HLS media workflows with InnoNetwork-Stream (formerly InnoStream), including playlists, VOD/offline packages, live DVR, AVFoundation, FairPlay, and decoded audio. Use for InnoNetworkHLS module or Stream macro tasks; ordinary JSON/Protobuf HTTP requests and generic Swift AsyncStream work belong elsewhere.
---

# InnoNetwork-Stream

Use this skill for the four Stream modules on Apple platforms. Stable support
is **6.1.x (`>=6.1.0 <6.2.0`, excluding prereleases)**. The exact checked baseline
is published **6.1.1**, tag commit `2af03b24cfc8f11442a3b9ba2fd8adcfe58d8116`.
Core is independently published and required at **exact 6.1.1**. Do not claim
that every supported patch has been tested. Read [compatibility](references/compatibility.md) when selecting,
upgrading or qualifying a dependency; machine-readable facts live in
[support.json](references/support.json).

## Choose the public workflow

Inspect the consumer's manifest, resolved graph, source revision, toolchain and
minimum platform before writing code. Keep the existing supported patch. Choose
an individual product or the aggregate `InnoNetwork-Stream`; imports remain
`InnoNetworkHLS`, `InnoNetworkHLSLive`, `InnoNetworkHLSAVFoundation`, and
`InnoNetworkHLSAudio`. There is no `import InnoStream` or hyphenated Swift import.

- **Playlist inspection, VOD or offline media:** read
  [parsing and downloads](references/parsing-downloads.md). Use the throwing pure
  parser and discriminated documents; prefer `@HLSDownloadDefinition` for a
  single file and `@HLSOfflinePackageDefinition` for a preserved presentation.
- **Live reload or DVR:** read [live and native](references/live-native.md).
  Prefer `@HLSLiveDefinition` / `@HLSDVRDefinition` with a retained owner.
- **Native playback, background downloads, FairPlay or PCM:** also read
  [live and native](references/live-native.md) for MainActor, restoration,
  compiler/OS availability and service boundaries. A playback definition
  configures a caller-owned item; it never creates or plays a player.
- **Metadata, diagnostics or tests:** read
  [testing and metadata](references/testing-metadata.md). Catalog data is an
  opaque identifier, not a URL/path/key store; recovery advice executes nothing.

Static definitions accept checked positive decimal literals on structs/enums.
Use the matching `*Defining` protocol plus throwing immutable `validated(...)`
factory for dynamic settings or compiler-plugin recovery. Do not silently
substitute legacy clamping `advanced(...)` for rejecting validation. Pure
`configuration()` is effect-free and nonisolated; native `apply(to:)` is MainActor.

## Preserve ownership and transport

`start` explicitly starts work: retain the handle. Cancelling a subscription or
receipt waiter only ends that observation. Explicitly cancel the operation when
its application scope ends; await its receipt for the authoritative committed
result. `downloadPackage(...)` instead runs in the calling task and inherits
that task's cancellation. A committed output survives late cancellation.
DVR uses `stopAndCommit()` or `cancelAndDiscard()`; the first terminal intent
wins. Background tasks keep system restoration semantics.

Pass caller-owned session, request context and request policy through. HLS
request adaptation must preserve a bodyless GET. Do not disable TLS validation,
replace trust/authentication policy, retry cancellation, or treat parsed DRM
metadata as backend execution support. Keep resource/concurrency limits bounded.

## Validate the result

Use public library APIs and focused success/failure/cancellation controls.
The bundled [consumer](assets/consumer/Package.swift) compiles all six macros
and their dynamic equivalents; its tests exercise parsing, bounded configuration,
mocked transfer, publication, ownership, catalog and failure contracts.

```bash
python3 scripts/validate_consumer.py --scratch-path /tmp/innonetwork-stream-skill
```

Run the command from this skill directory. The helper copies the fixture outside
it, verifies the exact remote lock/graph/checkouts, and uses Swift 6 strict
concurrency plus warnings-as-errors. It verifies the official 6.1.1 tag before
and after validating the exact release consumer; application integration is separate. Adapt tests to the app's
actual resolved patch. Separate fixture success, AI-generated compilation,
native device/service acceptance, source merge and public release.
