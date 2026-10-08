# Stream 6.1.1 release execution checklist

Prepared 2026-10-08 UTC from main `81f945f751090aed7c696e4c453816e01df5dd93`.
Status: preparation only; official HLS acceptance, applicable device acceptance
and the full release gate have not passed. No release tag exists at this check.

## Freeze the candidate

Keep `RELEASE_VERSION` at 6.1.1 and Core exactly 6.1.1, revision
`44e4ca28c50c03f817231a077c0f3bdfdbc859c8`. Review [API Stability](../API_STABILITY.md):
the four modules, aggregate product, six macros/manual equivalents, ownership
rules and deployment floors are the proposed 6.x contract. Internal test hooks
and script layout are excluded. No runtime/API change is needed for this preparation.

Review the applicable [device scenarios](DEVICE_ACCEPTANCE.md) with the consuming
app owner. Background restoration, locked storage and FairPlay remain NOT RUN;
record an explicit applicability decision and redacted results, not assumed passes.

Finalize release date and coordinated ready-state documents only after the
maintainer's readiness decision. Keep draft while that decision is pending.
Document any still-unperformed checks truthfully. Commit all intended source,
script, input, API and document changes before collecting source-bound evidence.

## Official HLS inputs and environment

The collector uses `Tests/InnoNetworkHLSTests/HLSMediaFixtures.swift` and
`Tests/Fixtures/HLSRuntime/audio-fmp4/`; it materializes the baseline inputs,
then uses the public Swift SDK exporter to produce these exact six cases:

- `offline-transport-stream`
- `offline-fragmented-mp4`
- `offline-audio-fmp4`
- `dvr-transport-stream`
- `dvr-fragmented-mp4`
- `dvr-audio-fmp4`

These are bounded baseline VOD inputs. They do not qualify production CDN,
encrypted media, every LL-HLS variant or device FairPlay behavior. Fixed-fixture
validation alone cannot substitute for these SDK-produced outputs.

The exporter requires an authorized Apple SDK host with Xcode 27 / Swift 6.4.
The complete runtime preflight additionally requires macOS 27. Obtain actual
`mediastreamvalidator` and `hlsreport` from [Apple](https://developer.apple.com/streaming/)
and review the applicable download terms. Account login, installation and new
Mac execution require separate authorization. Do not assume public redistribution
rights or automate Apple account/2FA login in CI. No new infrastructure is required.

## Collect and independently review

On the clean, committed candidate, first exercise SDK generation without claiming
official conformance:

```sh
python3 Scripts/apple_hls_evidence.py smoke --bundle .build/release-sdk-smoke
```

Then, with the real tools available, use a fresh destination and the actual tool
release label/operator identity (replace the placeholders):

```sh
python3 Scripts/apple_hls_evidence.py collect \
  --bundle ReleaseEvidence/apple-hls \
  --tool-release '<actual downloaded release>' \
  --submitter '<operator GitHub login>'
```

Retain source commit/fingerprint, materialized input hashes, binary/lock/graph
provenance, tool executable hashes, all six SDK outputs and raw JSON/HTML/logs.
A failed or unexecuted collection must not produce a passing acceptance claim.

An independent authorized maintainer reviews actual execution and warnings,
then approves the manifest SHA-256 and reviewer identity. Hash consistency alone
does not prove execution. Configure `APPLE_HLS_APPROVED_EVIDENCE_SHA256` and
`APPLE_HLS_APPROVED_BY` only through a separately authorized repository-admin
action. Do not commit the approval as if it were independent evidence.

Commit only `ReleaseEvidence/apple-hls/` after collection. Any other tracked
change invalidates the source binding and requires recollection. Never commit
Apple binaries, credentials, DRM payloads or private production media.

## Validate and publish

1. Verify the bundle using the independently approved digest/reviewer as described
   in [Local HLS evidence](LOCAL_HLS_EVIDENCE.md).
2. Run `bash Scripts/run_local_release_preflight.sh --full` and the nonpublishing
   Release workflow on exact canonical main. Preserve failures; do not bypass
   missing evidence, cancellation or unexpectedly skipped required checks.
3. Recheck main identity and publication authorization, then create an unprefixed
   annotated `6.1.1` tag on the tested commit. The tag workflow must pass its own
   identity and full validation gates before publishing the source archive.
4. Build a clean external consumer using both published Stream/Core 6.1.1 tags.
   The skill's existing commit-pinned consumer is historical evidence only.

Stop on absent evidence/approval, changed candidate, failed validation or an
unresolved applicable acceptance check. A policy exception requires a separate,
explicit documented decision; this checklist grants none.
