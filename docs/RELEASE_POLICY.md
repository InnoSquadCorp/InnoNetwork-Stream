# Release Policy

## Version and API boundary

`RELEASE_VERSION` records the release line: `6.1.1`, now published. The
release-note `ready` marker preserves the pre-publication qualification state.
A published README links the stable tag; it does not rewrite historical evidence.
For the next release, update the version and repeat the sequence below. The owner chose this
number to align with Network; Stream is still independently versioned. It has
no prior stable 1.0.0 tag. The released 6.x public contract and pre-release breaking
migrations are in [API Stability](../API_STABILITY.md). Major incompatible changes
after publication need a Stream major version. Optional roadmap work is not a
release blocker.

## Dependency contract

Core is pinned exactly to published `6.1.1`, revision
`44e4ca28c50c03f817231a077c0f3bdfdbc859c8`. Core source is not modified. The dependency
gate checks the manifest, root lock, resolved graph, active checkouts and Git
object availability, with no local override. Both normal public consumers and
the local evidence exporter must resolve the reviewed dependency graph.
New-candidate checks cannot inherit the earlier Core 6.1.0 CI result.

## Release states and local evidence

A coherent candidate uses a `draft` marker and an explicitly unpublished status.
A coherent `ready` document records an actual date and the reviewed 6.x API
contract; it does not falsely assert that a tag already exists. Ordinary CI
accepts either internally consistent state. Independent draft/ready fixtures
exercise both positive states and rejection controls. Publication requires ready.

Official Apple-tool execution is local-first; permanent CI infrastructure or
Apple login on every runner is not required. See [Local HLS evidence](LOCAL_HLS_EVIDENCE.md).
The maintainer reviews the actual SDK-generated offline/DVR outputs and report
bundle, then approves its manifest digest outside the bundle. CI validates that
approval, exact candidate source fingerprint, dependency/fixture inputs and raw
results. Missing/unexecuted evidence never becomes a successful conformance claim.
The original three fixed-media fixture checks remain distinct development tests.

## Publication sequence

1. Finalize source, tests, Core lock, API scope and release documents. Keep
   unperformed official-tool/device checks explicitly pending.
2. Run the ordinary Xcode matrix, external aggregate/individual Debug+Release
   consumers, exporter compile check, five Apple platforms, API/DocC, CodeQL,
   and AVPlayer/audio/runtime checks for this exact candidate.
3. Select the release date and ready state, commit the complete candidate, then
   locally collect actual SDK-output Apple evidence. Review the immutable bundle.
4. Add only the evidence directory in a follow-up commit. An authorized
   maintainer configures its approved digest/reviewer through the repository's
   protected administration boundary. Source changes invalidate the evidence.
5. Run `Scripts/run_local_release_preflight.sh --full` with approved evidence,
   and the nonpublishing Release workflow on exact canonical main. These run
   all other validation normally while verifying local Apple evidence.
6. Only with explicit publication authorization, create an unprefixed annotated
   `6.1.1` tag on that exact canonical-main commit. The tag workflow checks ready
   state, reruns validation, rechecks tag/commit identity, and publishes an archive
   and checksums. It retains the reviewed evidence with the release artifacts.
7. Before application rollout, build a clean external consumer using both
   published 6.1.1 tags. Path-based fixture consumers are not this post-tag check.

[Device acceptance](DEVICE_ACCEPTANCE.md) covers application-owned background,
locked-storage, and FairPlay-provider scenarios. Actual device execution needs
its own authorized environment and credentials; deterministic/injected tests do
not certify physical power-loss durability. FairPlay live acceptance is required
when changed/used behavior and available app-owned entitlement context warrant it.

If official tools cannot be executed anywhere authorized, the maintainer must
make an explicit documented policy decision. Do not remove a failing command,
use synthetic test reports, or relabel NOT RUN as conformance success.
