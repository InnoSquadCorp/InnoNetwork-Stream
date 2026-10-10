# API Stability (6.x)

`6.1.1` is the first published stable Stream release. The reviewed contract below
has applied since its publication on 2026-10-09 UTC. See the
[published 6.1.1 release](https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1).

## 6.1.1 supported surface

The reviewed `Scripts/symbols/*.allowlist` and `public-signatures.tsv` define the
public declaration baseline: 2,149 name rows and 2,154 semantic signatures.
The supported workflows are pure playlist parsing/planning, VOD downloads,
offline packages, live observation/DVR, AVFoundation playback/background asset
integration, application-owned FairPlay integration, decoded audio, and the
bounded metadata catalog. The six macro-first definitions and their manual
validated equivalents are included. `advanced()` normalization remains supported.
No public declaration is silently made unsupported merely because it originated
in the pre-release Draft redesign.

The four module/product names, aggregate `InnoNetwork-Stream` product, and Apple
deployment floors (iOS 16, macOS 14, tvOS 16, watchOS 9, visionOS 1) are the package
boundary. Core is a separate dependency pinned exactly to `6.1.1` at
`44e4ca28c50c03f817231a077c0f3bdfdbc859c8`; updating it requires explicit review.

Since 6.1.1 publication, removals, incompatible concurrency/signature changes, raised
platform floors, and changed operation-ownership semantics require a Stream
major release. Additive APIs require reviewed signature/allowlist updates and
release notes. Consumers should handle unknown enum cases where supported.

## Pre-release breaking migrations

- Replace public flat `HLSPlaylist(...)` construction with `HLSPlaylistParser`
  and its discriminated media/multivariant documents.
- Move media products from the Core package declaration to Stream; the four
  module imports remain unchanged.
- Request adapters must preserve a bodyless GET and Core admission/trust rules.
- Background completion registration is MainActor-isolated and accepts UIKit's
  ordinary escaping closure. Use the restoration initializer to register the
  handler before the native session can deliver restored events.
- Retain foreground operation owners explicitly. Cancelling observations does
  not cancel owned work; use the operation's cancellation API.

See [migration examples](docs/MACRO_FIRST_MIGRATION.md). Existing compiled
consumers of unreleased revisions may need these changes; Core source is not
modified by this package migration.

## Scope and evidence limits

The contract covers documented behavior and supported inputs, not arbitrary HLS
backends, DRM entitlements, CDN availability, device timing, or application UI.
Catalog persistence adapters, FairPlay credentials/KSM, and native device
background/locked-storage acceptance remain application-owned responsibilities.
Internal symbols, test hooks, script layout, and symbol counts alone are not
compatibility promises. Checkpoint/offline schema changes require explicit
recovery and migration review.

A green PR run is development evidence. Future publication additionally requires
coherent release-state documents, a canonical-main candidate, approved local
Apple-tool evidence for actual SDK outputs, and post-tag remote consumer checks.
Published Core and Stream 6.1.1 do not transfer acceptance to later changes.
The older Core 6.1.0 run remains evidence for its own revision only.
