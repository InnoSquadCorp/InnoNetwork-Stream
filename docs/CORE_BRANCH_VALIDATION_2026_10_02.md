# Core branch integration and streaming-key cancellation

> Historical record — retained for the source, date and environment below.
> For the published 6.1.1 contract, use the [current quick start](../README.md)
> and [documentation map](README.md). Unexecuted checks are not implied passes.


## Baseline and scope

- Stream baseline: `971750d664643fb888937242aa130537daf8bb0f`; development
  branch: `codex/stream-core61-development`.
- Dependency wiring commit: `e78f005`.
- Remote Core: `codex/core-stream-followup` at
  `91b4b417ca134d0f837f8e000846cd0478e7d439`,
  [PR #141](https://github.com/InnoSquadCorp/InnoNetwork/pull/141), stacked on
  [PR #132](https://github.com/InnoSquadCorp/InnoNetwork/pull/132).
- Toolchain: Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0.1, Apple silicon.
- This is a development integration milestone, not a complete new repository
  audit, a Core release approval or Stream publication evidence.

The root lock retains all previous transitive versions. The dependency gate
checks the manifest, remote lock, active graph, checkout commit and object
integrity. Both product-selection modes in the external consumer resolve the
same Core commit. That independent consumer also exercises a newly resolved
transitive graph; it is separate from the root's preserved graph.

## Confirmed correction

A pre-cancelled streaming-key fulfillment entered SPC generation. Cancellation
after SPC could become advisory-key success, while cancellation during a
license exchange could be reported as an invalid empty response instead.
The original ordering fails the added deterministic tests. The correction
checks cancellation before acquisition validation and after both asynchronous
stages, retaining the existing checks before transport and key submission.
Cancellation remains the existing redacted failure code 1; no public API is
added and successful key submission is not undone.

Three regression methods cover five cases, with initial/renewal, valid advisory
keys, SPC errors and invalid responses retained as normal/failure controls.
The macro-first API and all four public import names remain unchanged.

## Fresh local evidence

Logs are retained under `.build/core-development/`.

| Check | Result / evidence |
| --- | --- |
| Original cancellation ordering | Three new methods fail with eight issues in `streaming-key-before.log`; retained as failing control |
| Focused corrected workflow | 12 methods pass in `streaming-key-after.log`; initially run with the local Core override |
| Final remote-Core full development preflight | `full-preflight-verified.log`: exit 0, 648 registered / 642 ordinary passes / six default runtime skips |
| Runtime skips closed with local media fixtures | Six opt-in tests run successfully in the separate runtime stage; AVPlayer timeline, offline movpkg, preload, MAP rotation, GAP and DVR timeshift, plus decoded/audio-mix probes |
| Apple conformance | Three playlists pass; reports under `.build/local-release-preflight/apple-hls/apple-hls-conformance.TfQMgj/` |
| SDK builds | macOS, iOS simulator, tvOS, watchOS and visionOS: four library targets each pass |
| FairPlay TSAN | 27 methods in persistent/streaming workflow suites pass in `fairplay-tsan.log`; not full-suite TSAN |
| Public contracts | 2,126 public declarations and 2,131 semantic signatures pass, unchanged |
| Macro-first consumers | Aggregate and individual products pass in both Debug and Release; `consumer-aggregate-release.log` and `consumer-individual-release.log` |
| Dependency negative controls | Stale direct/transitive pins, missing objects, local overrides, wrong branch/manifest and published API/SDK rejection pass in `dependency-fixtures-final.log` |
| Shell/workflows/docs | Bash 3.2-compatible optional arguments, actionlint, format (306 files), scripts and Draft-state checks pass |

The initial preflight wiring attempts (`full-preflight.log`,
`full-preflight-final.log`) are retained as failures, not passes. The final
unmodified-script run above supersedes them. The default version-only preflight
also rejects the branch lock as expected (`published-preflight-rejection.log`).

The external consumer checks all five Stream macros, the Core macro, manual
equivalents and actual Core cancellation through macro-first entry points. A
new harness guard additionally compares its lock and active Core checkout to
Stream's root lock; a changed Core branch cannot silently validate a different
candidate. The deliberate wrong-revision control and normal rerun are retained
as `consumer-pin-negative.log` and `consumer-pin-controls.log`.

## Remaining boundaries

At the 2026-10-02 check, Core PR #141's Dependency Review failed because the
head dependency snapshot was absent after 180 seconds (run `37002964086`,
job `110824637058`); other checks were queued. No check is bypassed or described
as passed. Remote Core integration/merge and Stream CI/publication are separate
from this local milestone.

No dedicated FairPlay server, device-bound credentials, locked-device restore,
production CDN or real-service IdP/exporter environment was available. Local
fixtures and protocol doubles do not establish those deployment contracts.
Before release, switch to a published compatible Core version and complete the
version-only release and tagged-consumer gates.
