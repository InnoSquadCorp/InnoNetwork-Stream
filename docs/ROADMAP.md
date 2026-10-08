# Roadmap

## Release Boundary

The first planned stable Stream release is `6.1.1`, matching the owner's
chosen Network release number. Stream remains independently versioned; this
number does not make future Core upgrades or Stream releases automatic.
Core is pinned to the published `6.1.1` tag. Release qualification is tied to
the new Stream candidate, not to earlier Core 6.1.0 CI results.

Optional features below do not block 6.1.1.
The required gates are documented in [Release Policy](RELEASE_POLICY.md),
including approved local Apple-tool evidence on actual SDK-produced packages.

## Follow-up Scope

The first minor should harden real playback and offline operations without
turning InnoNetwork-Stream into a player UI, CDN, packager, or DRM credential owner.
Every candidate must be additive, independently releasable, and backed by a
named adopter or a reproducible media fixture.

### Priority 0 — adoption and durable offline state

1. **Use adopter evidence before expanding the API.** The proposed 6.1.1
   baseline contains 2,149 public name rows and 2,154 distinct signatures,
   documented in API Stability. Future additions should serve a named application
   or reproducible media case; declaration count is not an expansion goal.
2. **Managed asset-catalog persistence.** The current
   `HLSAssetDownloadLibrary` is a bounded Codable value and deliberately leaves
   file persistence to the application. The 6.1.1 candidate now provides optional
   `@HLSCatalogDefinition`/`HLSMediaCatalog` bounded metadata transactions,
   version migration and caller-reported reconciliation for app files, offline
   packages and native assets. Actual atomic durability and exclusive-writer/CAS
   enforcement remain app-adapter responsibilities. Future native-library
   integration and cross-store inventory need adopter evidence; no default
   filesystem durability adapter or automatic pruning has been implemented.
   It must never delete a system-managed asset implicitly; pruning and eviction
   remain explicit, observable caller decisions.

### Priority 1 — bounded operational insight

1. **Playback incident snapshots.** The 6.1.1 candidate's `HLSIncidentBuffer` already
   offers bounded, correlated typed-scalar composition with drop/truncation
   accounting; `HLSFailureReport` excludes arbitrary descriptions/URLs/payloads.
   Automatic native event ingestion and exporter integration remain future work.
   Compose the existing typed AVMetric event
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
- Stable promotion requires clean consumer builds against the published 6.1.1
  baseline and the proposed follow-up surface.

### Explicitly outside the next minor

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
