# Roadmap

## 1.0.0 Release Boundary

InnoStream is independently versioned from InnoNetwork. Its first release is
therefore `1.0.0`, not `6.0.0`, and the follow-up minor is `1.1.0`, not
`6.1.0`. The 1.0 draft preserves the four HLS product and module names while
moving their package ownership out of InnoNetwork.

No 1.1 candidate below is a blocker for 1.0. The 1.0 exit gate remains the
documented clean remote resolution order: publish InnoNetwork 6.0.0, validate
InnoStream without a local override, publish InnoStream 1.0.0, and then build a
clean external consumer from both tags.

## 1.1.0 Candidate Scope

The first minor should harden real playback and offline operations without
turning InnoStream into a player UI, CDN, packager, or DRM credential owner.
Every candidate must be additive, independently releasable, and backed by a
named adopter or a reproducible media fixture.

### Priority 0 — adoption and durable offline state

1. **Promote only adopter-proven declarations.** Use Capto plus at least one
   additional media consumer to identify the subset of the 1,867 provisional
   declarations that applications use directly and without SPI. Promotion is
   per coherent workflow—playlist parsing, live reload, playback, asset
   download, FairPlay, or decoded audio—not a bulk declaration-count goal.
2. **Managed asset-catalog persistence.** The current
   `HLSAssetDownloadLibrary` is a bounded Codable value and deliberately leaves
   file persistence to the application. Evaluate an actor-owned coordinator
   for atomic catalog checkpoints, schema migration, and reconciliation with
   `HLSAssetDownloadStorage`. It must never delete a system-managed asset
   implicitly; pruning and eviction remain explicit, observable caller
   decisions.

### Priority 1 — bounded operational insight

1. **Playback incident snapshots.** Compose the existing typed AVMetric event
   streams, playback health snapshots, content-steering decisions, and live
   reload health into a bounded, exporter-neutral incident report. Reports
   need stable correlation, truncation counts, and URL/header redaction; they
   must not retain media bytes, FairPlay payloads, licenses, or user tokens.
2. **Cross-store capacity inventory.** Evaluate a read-only inventory that can
   summarize application-owned offline packages, live-DVR snapshots, and
   system-managed AVAsset downloads under one byte/availability view. Any
   deletion or quota enforcement stays in an explicit follow-up operation so
   an observation API cannot evict playable media.
3. **Server delivery hint discovery.** Investigate typed Common Media Server
   Data ingestion only if a real CDN adopter can supply fixtures and desired
   decisions. Existing AVFoundation CMCD configuration remains the client-data
   path. Server hints must first be observable; automatic ABR, pathway, or
   retry changes require a separate policy proposal and failure-mode tests.

### Admission and release gates

- Public additions update the owning symbol allowlist, API stability counts,
  changelog, DocC, and migration examples together.
- Offline-state changes need corruption, crash-between-write, schema-version,
  missing-asset, cancellation, and disk-pressure tests.
- Diagnostic aggregation needs deterministic clocks, bounded retention,
  redaction fixtures, dropped-event accounting, and zero-media-payload tests.
- HLS behavior changes run the Apple conformance fixtures and supported-runtime
  smoke in addition to Swift tests and all-platform builds.
- Stable promotion requires clean consumer builds against the published 1.0
  baseline and the proposed 1.1 surface.

### Explicitly outside 1.1

- Player chrome, queue UX, Picture in Picture policy, AirPlay UI, analytics
  dashboards, and CDN control planes belong to applications or dedicated
  products.
- Transcoding, media packaging, origin hosting, and server-side DRM services
  are not library responsibilities.
- FairPlay certificates, SPC/CKC payload ownership, persistent-key storage,
  entitlements, and license-server credentials remain application-owned.
- Reimplementing InnoNetwork transport/retry/trust, automatic destructive
  storage cleanup, and public product/module renames are not minor-release
  goals.
