# Changelog

## Unreleased bounded-lifecycle hardening

- Bound Content Steering clone/output records and generated URL/group text;
  bound original-pathway fallback without losing ordinary ordered failover.
- Expand DEFINE values once against preceding definitions with retained-value
  budgets, normalize exact-cap newline boundaries, and index parser groups.
- Forward PART/MAP preload consumption cancellation and preserve snapshot
  terminal results while registration/cancellation cross actor boundaries.
- Deliver UIKit background completions on main and register restoration
  handlers before native construction; install interstitial listeners before
  returning a stream. The application callback API is now MainActor.

## Unreleased Core 6.1.0 integration

- Pin both Stream and its external consumer to published InnoNetwork `6.1.0`
  at `79ff9f535a0a15ad8b52ce49cb5a4b1ea1dfec16`, and align the compiler plugin
  with Core’s SwiftSyntax 604.0.x dependency. Restore published-only CI gates.
- Consolidate checkout 7.0.1 and coupled CodeQL 4.38.2 action updates while
  preserving selective CI, metadata revalidation and immutable release checks.
- Fix bounded variable-output initialization on the supported Swift 6.2 lane.

## Unreleased iterative hardening

- Start Steering TTL and Retry-After waits after receipt, share same-context
  manifest loads with independent cancellation, and bound waiters/producers.
  Honor zero and HTTP-date Retry-After values; reject signed or overflowing
  delays instead of interpreting them as valid positive waits.
- Add macro-first offline `start` and `HLSOfflinePackageTask` with independent
  bounded events/receipt observation and explicit owner cancellation. Reuse the
  existing atomic package engine and preserve legacy ownership contracts.
- Exercise registered waiter cancellation, capacity reuse and finish races with
  actual registration barriers rather than scheduling assumptions.

## Unreleased

- Add macro-first atomic offline packages with `@HLSOfflinePackageDefinition`,
  validated dynamic settings and equivalent manual workflows. Cancellation is
  owned by the calling task; existing destinations are not overwritten.
- Enforce bodyless GET request adaptation and cancellation on both sides of
  adaptation. Reject empty media/plaintext before VOD or offline publication.
  Share strict Content-Range parsing between VOD and DVR, including actual
  open-ended response byte counts without Content-Length.
- Compile all four DocC catalogs with warnings as errors and explicit sibling
  archive dependencies. Correct macro signatures, stale overload links and
  cross-module paths; reuse generated API graphs in CI/preflight.
- Bound long-lived downloader/planner Content Steering caches to 64 recently
  used entries, including negative responses. Active plans retain their own
  immutable pathway candidates; eviction only affects subsequent planning.
- Develop against Core PR #141's `codex/core-stream-followup` branch and lock
  its exact revision. Verify manifest, active graph and checkout agreement;
  keep published release validation version-only.
- Stop cancelled streaming FairPlay requests before SPC generation, advisory
  success and license-response validation. Retain normal initial/renewal and
  advisory-key controls alongside deterministic cancellation regressions.

- Preserve typed core cancellation in HLS request policies, persistent and
  streaming FairPlay workflows, and redacted content-key failure diagnostics.
  Diagnose escaped and conditional reserved configuration members in all five
  Stream macros. Verify macro-first cancellation with published core 6.0 and
  the separate local core 6.1 candidate in the earlier compatibility snapshot.
- Add distinct semantic API signature gates, persisted-format fixtures and
  fail-closed reverse-dependent local test selection; keep full CI/release
  validation mandatory. Compile all five macro workflows and manual equivalents
  in actual Debug/Release consumers, including actor-isolated definitions.
- Make generated pure configuration explicitly nonisolated while preserving
  MainActor native playback effects. Isolate the new Live network fixture with
  the existing shared-registry suite, and build exact SwiftPM SDK library
  targets without modifying the preserved generated Xcode project. Close the
  ten-slice local validation record; remote/adopter release gates remain open.
- Keep non-transient URL errors out of automatic retry/checkpoint-restoration
  advice. Distinguish explicit no-recovery from an unspecified optional recovery
  action, with all-backend controls and retained transient/cancellation cases.

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

- Wait for the live playlist producer and relay to terminate before returning
  from DVR stop/discard, preventing requests after caller-owned session cleanup.
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
