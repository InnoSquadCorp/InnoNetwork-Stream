# Core 6.1 candidate / Stream whole-review closure

> Historical record — retained for the source, date and environment below.
> For the published 6.1.1 contract, use the [current quick start](../README.md)
> and [documentation map](README.md). Unexecuted checks are not implied passes.


Status: local implementation and validation record, not publication approval.
The maintainer explicitly included core fixes in the 2026-09-30 review.
The macro-first public workflows remain the primary consumer contract.

## Frozen inputs and authority

- Stream input: `7387802e28b08ac9144f09d9a5161c016b65d254`.
- Core 6.1 input: `79e1900ed283c129ab9523c7661c2f1a8e9cdc3c` on
  `codex/encoded-request-contract`, not the divergent original core checkout.
- Core changes live on `codex/core-stream-review-6.1` in a separate worktree.
  Current runtime/test source: `7dccf4c1412d48ddfc28fa403a03e3ef960d7e77`.
- Stream runtime/macro source: `2174d1d7b4c033ee2434951968d5e416300fe97f`;
  the subsequent `68b1a45` adds an actual external cancellation consumer only.
- Public Stream dependency remains core `6.0.0`, revision
  `9d8053d5f921ebf5c38cc2f816efe90c7db4a450`. Package lock SHA256 remains
  `00e9dbd5cadfc623a0d156d0035e797066c268873dce49c53e673d54b4530e28`.
- Xcode 27.0 / 27A266a, Swift 6.4, arm64 macOS 27.

Inventory: nine core runtime products, compiler-host MacroSupport, the compiler
plugin and OpenAPI CLI; five Stream products over HLS, Live, AVFoundation and
Audio, their compiler plugin, external consumers, contracts and release tools.
No source app migration, tag, release, push, PR, hosted CI dispatch or automation
is part of this review. Original core checkouts are not edited by this run;
Stream generated projects and earlier failure logs are preserved. A later
read-only check detected concurrent uncommitted macro/support, documentation and
release-contract edits in `InnoNetwork-encoded-request`, still at input HEAD
`79e1900`. Those edits are preserved but are not this frozen candidate's evidence
or covered by its test results. The independent Stream 1.0 remains Draft;
testing an unpublished local core candidate does not raise the public minimum.

Exit criteria were frozen before discovery: every applicable matrix row must
have source/test/contract/consumer/tool evidence or an explicit limitation.
Suspected product defects require an actual failing reproducer and a passing
control. Assertions are deduplicated by root cause. Optional features do not
become fixes merely because another review was requested.

## Confirmed defects and implemented corrections

| Severity | Root cause | Before / passing control | Correction |
| --- | --- | --- | --- |
| P2 | Core error snapshot recapture loses the original cause | Rewrapping a snapshot loses domain/code/metadata/chain; ordinary NSError chains remain correct. Two new tests fail with ten issues before the fix. | Recognize already captured snapshots before NSError bridging, preserve metadata, and clamp appended flattened causes to the existing five-frame budget. |
| P2 | Core codec cancellation becomes an encoding or decoding failure | Encoded bodies/responses, JSON factories, promoted JSON, custom/query and frame codecs disagree on three supported cancellation forms; malformed-input and ordinary-codec controls remain failures. | Normalize supported cancellation at codec boundaries. Preserve explicit custom NetworkError passthrough and the established raw CancellationError contract of direct custom decoder calls. The request pipeline still returns typed cancellation. |
| P2 | Core refresh provider cancellation activates failure cooldown | URL and typed core cancellation block an immediate subsequent refresh; CancellationError and genuine-failure cooldown controls distinguish the paths. | Reconcile provider cancellation to the coordinator's idle state before completion, without altering cancellation ownership of other shared waiters. |
| P2 | Stream/FairPlay misclassify typed core cancellation | A typed core cancellation is reported as adaptation/license-exchange failure; URL/plain cancellation controls remain cancellation. | Reuse the HLS cancellation classifier at both FairPlay workflow boundaries and preserve cancellation in payload-free content-key diagnostics. |

These are four runtime root causes, not the number of failing assertions.
Core local commits: `6ca3172`, `a1c2ad8`, `2c7225c`, `7dccf4c`.
Stream runtime correction: `32cd081`.

An additional compiler-diagnostic improvement (`2174d1d`) recognizes escaped
reserved configuration names and members in conditional branches in all five
Stream macros. The old implementation still produced a compiler error later;
this is earlier actionable diagnostics, not a separately counted runtime bug.
Tests include both conditional branches, escaped function/variable names,
unrelated conditional helpers and all four workflow default expansions.
It is not a promise to replace every Swift redeclaration diagnostic.

The first final core fast run exposed a regression introduced during the codec
fix: direct custom decoding changed CancellationError to NetworkError.cancelled.
The existing compatibility assertion was retained and `7dccf4c` corrected the
implementation. This failure is not labeled an environment flake or discarded.
Earlier fixture compile/name/manifest-identity mistakes are retained separately
and are not product findings.

## Cross-feature matrix

F = fresh execution on corrected sources; S = current source inspection;
R = reused, explicitly bounded earlier evidence. Broad regression suites are
controls, not proof that every possible interleaving has been exercised.

| Row | Closure evidence | Remaining boundary |
| --- | --- | --- |
| Core buffered/encoded | S: admission, deadlines, memoized encoding, collection caps and error projection. F: snapshot/codec matrix plus actual APIDefinition and promoted JSON clients. | Arbitrary application codec semantics remain application-owned. |
| Auth/retry/coalescing/cache | S: stage ordering, cancellation ownership, mutation generation, response budgets and signer provenance. F: refresh restart, genuine-failure cooldown and cache/auth/coalescing regressions. | Operational IdP/signers and server-specific cache policy are not certified. |
| Core streaming | S: iterator lifetime, acknowledgment/backpressure and bounded framing. F: frame decoder cancellation without reconnect plus root streaming regressions. | Real exporter/service load and hardware scheduling remain external. |
| Download/upload | S: terminal/delegate ownership, file commit, pause/restore and retained metadata. F: root suites and process restoration fixture. R: prior physical loopback sample. | OS background restoration and locked-device storage are not newly tested. |
| WebSocket | S: ordered delegate events, reconnect/heartbeat and shutdown. F: all WebSocket regression inventory. | Real server, proxy and network transitions are not reproduced. |
| Persistent cache | S: load validation before arithmetic, bounded reason aggregation, anchored file ownership and recovery. F: numeric/index/eviction/root tests. | One active owner per directory; not an interprocess database. |
| Trust/AWS | S: canonical hosts, system trust before pinning, DER bounds, non-S3 path and signer/credential boundaries. F: trust/auth AWS controls in root gates. | Real service credentials, certificate rotation and backend acceptance excluded. |
| OpenAPI/JSON | S: deferred/retained buffers, schema budgets/progress and security IR. F: codec cancellation, normal/malformed controls, CLI and generated-output checks. | Documented subset remains intentional; not full OpenAPI 3.1 conformance. |
| Macros/public contracts | S: Core host support and Stream conditional collision scanner. F: macro tests, compile-failure controls, API signature gates and actual consumers. | Compiler-host products are not runtime imports. |
| Stream parser/catalog | S: typed document admission, bounded parser, schema and transaction ownership. F: complete HLS suite and persisted-format controls. | User-owned media deletion/multi-process adapters excluded. |
| Transfer/resume | S: bounded core transfer, destination checks, rollback and checkpoint identity. F: HLS download/resume/cancellation suite and lifecycle sanitizer controls. | App background adoption and real CDN failure modes remain external. |
| Live/DVR | S: steering/preload ownership, retention accounting, delta/MAP/GAP and receipts. F: Live root and enabled loopback playback controls. | Operational steering/CDN transitions and long-lived background sessions excluded. |
| Native/FairPlay | S: caller/system lifetime and stage commit boundaries. F: all three cancellation representations, persistent/streaming workflow and diagnostic controls. | Real certificate/SPC/CKC/key-server and FairPlay device acceptance excluded. |
| Audio | S: native slot/callback ownership, bounded PCM and real-time contract. F: root and enabled loopback audio controls. R: earlier 20-repeat native race controls. | Not a hardware deadline or real-time performance certification. |
| Consumers/tooling | F: public 6.0 and exact local 6.1, Debug/Release, aggregate/individual products; all five Stream macros and real core cancelAll-to-HLS path. F: local contracts, release/tool negative controls. | No final-head hosted CI, merge, tag adoption or service deployment proof. |

## Fresh execution record

- Stream full local preflight: exit 0. Root inventory is 645 registered tests:
  637 ordinary passes, six unset-fixture skips and two unset-audio cancellations.
  The eight deferred checks were exercised separately within nine enabled
  loopback-runtime checks. Do not count those reruns as nine new unique tests.
- Stream full Thread Sanitizer: exit 0 across the same 645 registered inventory
  and the same eight deferred root dispositions. The HLS test binary links the
  TSAN runtime and HLSHTTPClient object references contain TSAN instrumentation.
  The enabled runtime checks above belong to the full preflight, not this TSAN
  invocation.
- Stream full preflight builds macOS, iOS Simulator, tvOS, watchOS and visionOS
  SDK library targets; these are builds, not executions on five devices.
  API inventory is unchanged: 2,126 declarations and 2,131 semantic signatures.
- Public core 6.0 consumer: Debug and Release, aggregate and individual products,
  all pass with the new cancellation scenario. A request interceptor signals
  actual core entry; cancelAll cancels only its tag before transport starts.
  No example.com network connection or outer task cancellation supplies the
  result. Configuration-only/manual/conditional macro controls remain present.
- Corrected core canonical fast preflight: exit 0, seven gates, all 1,997
  registered tests across four bounded shards. Four opt-in live skips are not
  ordinary passes. Static/API/docs, macro compile-failure fixtures, eleven
  consumer packages, CLI/generated output and process restoration also pass.
- Isolated corrected core 6.1 integration: the same 645-test Stream inventory
  passes, with the same eight deferred root dispositions. Debug and Release,
  aggregate and individual products, all four actual macro/cancellation
  consumers pass. Source-pair validation uses core `7dccf4c`, not the later
  concurrent dirty core edits or a claimed published 6.1 tag.
- Core full Thread Sanitizer: exit 0 across 1,997 registered tests with the same
  four opt-in live skips. Runtime linkage and RefreshTokenPolicy object
  instrumentation are verified. The slow download suite completed normally;
  a retained process sample shows checkpoint log replay work, not a deadlock.
- Additional core full-source gates are recorded below; earlier failed output
  is retained alongside final output.

The additional Core full run has also completed serial coverage with the same
1,997 registered inventory and two 30-second streaming soak controls. Runtime
line coverage is 89.13%; the separate compiler-host lane is 79.45%. Percentages
do not certify untested app/service/platform behaviors.

The fresh Core runtime benchmark lane passes all fourteen guards at the
unchanged 20% limit. Three baseline/current pairs give a worst guarded paired
median of -3.4306% for shared GET coalescing, with 31.1511 percentage-point pair
spread. This is threshold evidence, not a precise speedup or a diagnosis of
measurement variability. No retry, exemption or baseline/threshold change.
The separate JSON lane and later full gates follow.

The separate Core JSON lane passes all five guards: worst paired median
-8.0150% for anyOf all matches, pair spread 2.5772 pp. It keeps the preserved
`b358692e1e583b5cef1c97bb65208729b313f574` JSON source baseline; runtime keeps
`a4aaaba8b41553033f5d1f23fa94af85b52b4c3a`. Both use the unchanged 20% guard,
three interleaved pairs, no retry/exemption, and retained raw results. Default
and core-only SBOM profiles pass. DocC/SDK outcomes follow.

Core all-product DocC completes successfully, with all ten public archives
verified. Five-platform SDK results belong to the full gate below.

Core's single canonical full preflight now completes with **exit 0, all fourteen
gates passed**. macOS/iOS Simulator Xcode builds pass; tvOS/watchOS/visionOS each
build ten public library targets. These are SDK builds, not five-device execution.
Runtime/test, package/dependency, benchmark and workflow source is exactly
`7dccf4c`; only the Core evidence document and CHANGELOG were uncommitted during
the run. Later documentation commits do not change that measured code. Raw logs,
coverage, SBOMs, benchmark pairs and DocC outputs remain preserved locally.

Local diagnostics: `.build/core-stream-review-20260930/` in each implementation
worktree; candidate integration is separate in the detached
`InnoNetwork-Stream-core61-integration` worktree under `.build/core61-integration/`.
The diagnostic-only manifest names the local dependencies explicitly; it is
not a public manifest or lock update. These ignored raw logs are preserved on
this machine, not presented as published artifacts.

## Unresolved candidates, optional improvements and exclusions

There is no remaining reproducible, unfixed candidate in the completed local
review matrix. That is a bounded outcome, not a claim that no further defect
exists. The first validation failure and all reproducer/control logs remain.

Possible separate designs include enforced multi-process cache ownership,
broader OpenAPI language coverage, app-owned operational acceptance adapters and
target-hardware performance profiles. Their need depends on an actual adopter
and service contract; none is silently added to this patch or represented as a
newly discovered bug. Cancellation/error correctness was repaired without new
public knobs, an unpublished dependency requirement or a manual-first surface.

Xcode 26 is not installed. Exact-final-SHA hosted CI, protected integration and
release validation have not run. Corrected Core performance, DocC and five-SDK
builds are fresh above. Its prior physical loopback result is reused only for
the older recorded source, not certification of this code or Stream adoption.
No real CDN, IdP,
AWS, exporter or FairPlay acceptance, OS restoration, locked-device storage,
real-time hardware deadlines or migrated production app is claimed.
Final publication requires separately approved integration/release gates.
