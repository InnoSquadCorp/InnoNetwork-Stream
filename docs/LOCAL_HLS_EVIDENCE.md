# Local Apple HLS evidence (6.1.1 candidate)

## What this changes

Official Apple tools run locally once for a reviewed candidate. CI verifies the
result bundle plus an independent maintainer approval; CI does not log in to
Apple, download/rehost proprietary tools, or pretend it executed them itself.
No runner registration, account grant, license acceptance, or tool installation
is performed by these scripts. Obtain the correct official tools and review
their current terms separately.

`Scripts/validate_hls_with_apple_tools.sh` remains a useful **fixed-input fixture**
check. Its three checked-in playlists do not establish that Stream's own writer
produces conforming output. Release evidence instead runs the public SDK using
`Tests/HLSReleaseEvidence` and inspects six output cases: offline package and DVR
recording for TS video, fMP4 video, and fMP4 audio. The exporter uses only local
fixture transport. It records public SDK receipts; it does not write replacement
playlists by hand. These are small baseline VOD inputs, not coverage of all
LL-HLS, encrypted, multi-track, CDN, or real-device scenarios.

## Local collection

1. Finalize source, Core 6.1.1 lock, test harness, scripts, and candidate documents.
   Commit them and require a clean tree. Finish intended ready-state document
   edits before collecting final release evidence; those edits are fingerprinted.
2. On a supported local macOS/Xcode environment, install officially obtained
   `mediastreamvalidator` and `hlsreport`. Tool licensing and architecture must be
   checked by the maintainer. The SDK exporter itself needs Swift/Apple SDKs;
   Linux support for the standalone Apple tools does not make this exporter a
   Linux build.
3. Run the command below, supplying the real downloaded tool release label and
   operator identity. Paths can be selected with `--validator`/`--reporter`.

```
python3 Scripts/apple_hls_evidence.py collect \
  --bundle ReleaseEvidence/apple-hls \
  --tool-release '<actual official package version>' \
  --submitter '<operator GitHub login>'
```

A pre-existing destination is rejected to preserve prior reports. Archive or
move old evidence deliberately before recollecting; the collector never removes
it. Official-tool or exporter failure leaves diagnostics but no passing manifest.
The collector builds the public SDK exporter in Release, checks its resolved
pins against the candidate lock, executes the prepared binary for all six cases,
runs both Apple tools,
and retains raw JSON/HTML/stdout plus original inputs and SDK outputs. It also
records the exact source commit, all tracked source-tree entries, input hashes,
tool executable hashes/version label, platform, and execution time.

The validator explicitly runs with `--compatible-output=v1.x`. The verified
JSON/report format is 1.3; unsupported schemas or an HTML notice such as
"Version 3 output is not understood" fail even when both tools exit zero.
JSON completion, nested blocking messages and every HTML Must Fix section are
checked. Raw Should Fix issues and advisories remain visible for review. Actual
`--version` output from both installed tools is retained with the package label
and executable hashes.

For direct media inputs, offline packages use the localized primary media
playlist as their entry. A master wrapper cannot safely invent bandwidth,
codec or rendition metadata absent from the source. Multivariant source inputs
still retain their selected multivariant entry and existing packages reopen.

## SDK output smoke without Apple tools

Both Xcode lanes use the same generation path as collection. To exercise it
without official Apple validators, use a new output directory:

```
python3 Scripts/apple_hls_evidence.py smoke --bundle .build/hls-sdk-output-smoke
```

This compiles once, generates and reopens six SDK outputs, checks local media
references, and verifies the prepared binary, source commit, candidate/consumer
locks and clean dependency graph after execution. It writes no acceptance
manifest and explicitly reports that official conformance did not run.

`check_hls_evidence_consumer.sh prepare` seeds candidate pins and builds the
exporter. Its `verify` mode only inspects the prepared binary/lock/graph and
checkouts; it never resolves, rebuilds or repairs them. Graph verification checks
each unique dependency checkout once per verification, rejecting conflicting
identities or paths. All evidence, graph and orchestration controls run through
the same discovery command in CI and preflight.

## Approval and CI trust boundary

The collector's manifest is **unapproved**. An operator name inside it is only a
claim. A maintainer must inspect the real execution, downloaded tool version,
source/inputs, dependency lock, generated outputs, raw results, and warnings.
Hash consistency alone cannot prove that Apple tools or the SDK actually ran.

After review, an authorized maintainer may separately configure these repository
Actions variables (not files supplied inside the report bundle):

- `APPLE_HLS_APPROVED_EVIDENCE_SHA256`: exact SHA-256 of manifest.json
- `APPLE_HLS_APPROVED_BY`: approving maintainer's GitHub login

This is a repository-administration trust boundary, not an Apple attestation or
cryptographic signature of the operator. Preserve the approval/audit record and
restrict variable changes to trusted release maintainers. These variables have
not been configured by this draft. Configuring access or approvals requires the
owner's authorization. Reports should contain synthetic media only; review them
before committing or publishing. Never commit Apple binaries, credentials, DRM
payloads, or private production streams.

Commit the approved evidence under the fixed data-only directory
`ReleaseEvidence/apple-hls/`. CI verifies that its source commit is an ancestor
and every tracked entry outside that directory is identical to the tested
candidate. This permits the evidence-only follow-up commit without a circular
commit hash. Any other edit, including source, scripts, manifests, test media,
release documents, or mode bits, invalidates it and requires recollection.
The directory is never a source of scripts to execute.

```
python3 Scripts/apple_hls_evidence.py verify \
  --bundle ReleaseEvidence/apple-hls \
  --approved-digest '<independently approved manifest digest>' \
  --approved-by '<approving maintainer>'
```

`--full` preflight and Release use this verified evidence. Missing approval,
missing evidence, another commit/tree, modified/materialized inputs, extra or
missing output/report files, symlinks, failed tools, fixed-fixture-only reports,
and Must Fix issues fail closed. Enumeration is limited to 4,000 entries and
24 levels, with at most 2,000 files, 64 MiB per file and 256 MiB total; empty
directories count toward the entry/depth limits. Output explicitly says **APPROVED LOCAL
EXECUTION**, never “tools executed in this CI run.” Core/Swift/API/consumer/runtime
and platform checks still run normally. No `skip` or unverified-success switch is
provided.

## Remaining boundaries

No official Apple execution has been performed for this implementation draft.
Python fixtures are explicitly synthetic validator-protocol tests and must never
be used as release evidence. Actual SDK-output generation is wired into both Xcode CI lanes. The six SDK output cases passed both Xcode lanes in
[PR #4 validation](https://github.com/InnoSquadCorp/InnoNetwork-Stream/actions/runs/37776311885).
That validates generation, not execution of the official Apple validators or
the eventual release commit. Synthetic controls alone are not SDK execution.

If no authorized environment can execute the tools, evidence cannot be invented.
The owner must decide a documented release-policy exception rather than marking
conformance passed. Real-device background/FairPlay checks are described in
[Device acceptance](DEVICE_ACCEPTANCE.md), independently of these local reports.
