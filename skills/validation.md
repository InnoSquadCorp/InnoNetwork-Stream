# Stream skill validation — 2026-10-10

The skill supports stable **6.1.x** and validates the published **6.1.1** tag at
`2af03b24cfc8f11442a3b9ba2fd8adcfe58d8116`. The manifest requires Core **exact
6.1.1**, `44e4ca28c50c03f817231a077c0f3bdfdbc859c8`. Skill-source revision and
library baseline remain independent. This change does not alter runtime code.

## Fresh released-consumer evidence

- Xcode 27 / Swift 6.4, macOS 27 arm64: **13 Swift Testing tests passed** with
  strict concurrency complete and warnings as errors. All four module imports,
  six macros, manual equivalents, MainActor playback and guarded audio compile.
- Exact seven remote pins, active graph, workspace/prebuilt entries and clean
  checkout SHAs verified before tests; unchanged pins, source hashes and checkout
  heads/status verified afterwards. SwiftSyntax 604.0.0 uses a verified prebuilt.
- Remote annotated tag object `c8b74e3fd2f009276b47a5f4c4cee885e0c871bc` and peeled
  commit verified both before and after the run. Missing, mismatched or moved
  tags fail validation.
- **Six automation tests passed**, covering stderr warning separation, command
  failure, malformed JSON, dependency drift and release-tag rejection controls.
- Skill frontmatter/discovery metadata validated. Sanitized command hashes,
  dependency identities and results: [release-6.1.1-evidence.json](validation/release-6.1.1-evidence.json).

The fixture uses mocked URLProtocol responses and temporary output. This is not
fresh device playback, FairPlay, background restoration, PCM delivery, full HLS
conformance, other-toolchain or five-platform release qualification. AI host
selection/generation evidence belongs to the central plugin and is unchanged.
Other 6.1.x patches require their own tag/diff and consumer check when used.

## Historical pre-release validation — 2026-10-09

The following records the earlier unpublished baseline; it does not describe
current release availability. Its original evidence is retained unchanged.

The skill supports planned stable **6.1.x**, but validates unpublished main
`bd50e877644ded1b739f66bdd8fb604908606e4b`, intended for 6.1.1. No Stream tag or
GitHub Release existed at check. The manifest requires published Core **exact
6.1.1**, `44e4ca28c50c03f817231a077c0f3bdfdbc859c8`. Skill-source revision and
library baseline are independent. No runtime library implementation is changed.

### Historical local evidence

- Xcode 27 / Swift 6.4, macOS 27 arm64; all four module imports, all six macros,
  manual equivalents, MainActor playback and guarded audio compile externally.
- **13 Swift Testing tests**, strict concurrency complete and warnings as errors.
  Covers typed media/master parsing, malformed/oversize rejection, dynamic limits,
  nonisolated factories, mocked single-file bytes/late cancel, offline preview,
  atomic publication/reopening/no overwrite, gated observer cancellation while
  the producer is still running, pretransport cancellation/no publication,
  ENDLIST without observers, catalog capacity/reconciliation and failure policy.
- Exact seven remote pins, active graph, workspace/prebuilt entries and clean
  checkout SHAs verified before tests; unchanged pins/source hashes and checkout
  heads/status verified afterwards. SwiftSyntax 604.0.0 uses a verified prebuilt.
- A disposable wrong Stream revision and a local Core override were each
  rejected before any Swift command. Positive and negative evidence is retained
  in [consumer-evidence.json](validation/consumer-evidence.json).
- Skill frontmatter/discovery metadata and relative runtime links validated.
  Repository draft-release documentation gate and CI workflow lint passed.

The fixture uses session-local URLProtocol responses and temporary output only.
DVR and playback entry points compile but do not start real recording/playback.
Audio settings construction is not actual PCM delivery. No private library API
or local dependency substitution is used. AI host evaluations belong to the
central plugin and are separate from this authored fixture.

### Historical boundaries

This is skill and consumer validation, not a complete library regression/release
run. Other toolchains, five-platform builds, native background restoration,
FairPlay/device/service acceptance, full HLS conformance, actual audio delivery,
multi-process persistence, later patches and the eventual Stream 6.1.1 tag are
not newly qualified here. Existing historical library reports are not reused as
fresh proof. Verify the actual release tag and its diff and rerun a tagged
consumer before marking a release validated. No merge, tag or release is created.
