# Changelog

## Unreleased

- Add structured parse/operation failure reports, backend lifetime/recovery
  capabilities and explicit bounded export-safe incidents. Preserve existing
  NSError codes and suppress underlying descriptions, URLs and credentials.

- Add opt-in `@HLSCatalogDefinition` and bounded versioned metadata coordination
  with typed identities, explicit reconciliation and staged app-owned atomic
  persistence. Never implicitly delete/move media or touch key storage.

- Add macro-first Live, DVR and native playback definitions with validated
  effective limits. Add a foreground watch owner and independent bounded DVR
  observations/receipts while preserving native background and audio ownership.

These changes have not been tagged. `1.0.0` remains a draft until the release
state, remote dependency, Apple-platform, and HLS conformance gates pass.

- Breaking pre-release change: make contradictory flat playlist construction
  internal. Parse into typed documents, then select and plan from those
  documents; retain lossless inspection and unchanged persisted formats.

- Add a pure bounded `HLSPlaylistParser` and parser-produced discriminated
  multivariant/media documents, with a lossless legacy projection.
- Add the generated workflow's advisory `prepare` phase. Execution still
  re-resolves metadata and preserves transport admission and freshness.
- Clarify that observation drop counts describe losses observed before enqueue,
  not a post-delivery final-channel total. Retain independent terminal receipts.

- Begin the authorized macro-first redesign with `@HLSDownloadDefinition`,
  compile-time limit diagnostics and the same validated immutable runtime
  settings used by the advanced manual equivalent.
- Add explicit foreground download handles with independent bounded events,
  cancellation and awaitable committed receipts. Keep new contracts Draft.
- Reject unavailable LL-HLS skip history before allocation, compare huge finite
  authoring durations without integer traps, and bound variable expansion
  before intermediate append.
- Propagate shared Content Steering cancellation according to waiter ownership;
  preserve active survivors and cancel activation when all waiters leave.
- Check persistent FairPlay cancellation between stages; successful app-owned
  key storage is the commit point and is not undone by late cancellation.
- Gate public macro declarations in the symbol contract, test actual aggregate
  and individual macro consumers, and use narrow locked-graph macro validation
  handling for Xcode CI. Correct historical test disposition reporting.

- Split the four HLS products from InnoNetwork 6 into an independently
  versioned package while preserving their module names.
- Depend on InnoNetwork's public bounded-transfer and retry-execution
  contracts instead of package-internal transport coordinators.
- Add an explicit public API snapshot, release-state contract, CI workflow,
  and tag validation process for independent publication.
- Resolve the published InnoNetwork `6.0.0` release in the dependency lock,
  CI, CodeQL, and local release preflight. Preserve the existing transitive
  dependency versions and reject local-path overrides during release preflight.
- Check the published dependency's locked version and revision against the
  resolved graph and checkout, including when SwiftPM reuses cached state.
- Rename the unreleased repository and package to `InnoNetwork-Stream` and
  provide a matching all-in-one library product. Preserve the four existing
  individual products and Swift module imports.
- Establish the public `InnoSquadCorp/InnoNetwork-Stream` repository under
  the existing MIT license, without creating a stable release tag.
