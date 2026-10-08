# Iterative Stream hardening

Baseline: `15c03db3327fd850015b65971684dc1a61fc81a1`, tracked clean; preserve
`Derived/` and `InnoStream.xcodeproj/`. Core stays locked at `91b4b41`.
The owner authorized fixes, local commits and repeat review. No push or release.

## Fixed scope and exit criteria

Cover the previous production-hardening changes and their adjacent runtime,
macro, tests, consumer and CI contracts, not arbitrary new features or Core APIs.
For each row, check success, failure, cancellation, concurrent completion,
retry/reuse, resource limits and observability where applicable. A new confirmed
issue reopens its row; finish only after the final source passes regression and
a repeat pass leaves no unresolved reproducible issue in this matrix. This is
not a proof of zero defects in every environment.

| Work | Implementation and closure evidence |
| --- | --- |
| Steering receive-time TTL/Retry-After | Immediate 200/429 controls passed before and after; delayed cases failed before and pass after receipt anchoring (`steering-time-before/after.log`). |
| Bounded same-resolver manifest sharing | `steering-flight.log`: 200/429/410/503 shared responses, independent cancellation, 64 waiter/producer bounds, capacity reuse and a late cancelled generation pass. Cancelled producers count against capacity until drained; overload falls back without I/O. |
| Macro-first offline owned operation | `offline-registered-fixed.log`: macro/manual parity, calling-task cancellation, independent progress/receipt cancellation, explicit owner cancellation/release, lease reuse, atomic receipt and late cancel controls pass. Debug aggregate/individual consumer succeeds in `consumer-debug.log`; nine additive API rows are reviewed, 2,148 names/2,153 signatures pass. |
| Registered waiter cancellation | Actual registered-count barriers: 64-waiter admission, cancellation/replacement, cancellation-first/finish-first and 200 concurrent completion races pass (`offline-registered-fixed.log`). |
| Adjacent VOD/DVR/resource/API contracts | Re-read the changed resolver, package worker, shared channel and destination-lease ordering. Full fresh tests cover bodyless GET admission, cancellation around adaptation, empty/AES resources, Content-Range, atomic failure, resume/corruption, DVR/MAP/GAP and redacted typed errors. Transport, trust, retry identity and persisted formats remain unchanged. |
| Final source verification | Ordinary and full TSAN pass; local HLS/Apple validation, five SDKs, Debug/Release aggregate and individual consumers, API/DocC and script fixtures pass. The original public reproducer linked against the final optimized objects confirms the fixes. |

The original delayed-response reproducer is retained at
`/private/tmp/stream-current-review.Tf9RNq/`; immediate controls make one request,
delayed 200/429 cases make two. That bug predates the latest LRU correction.
New logs will be retained under `.build/iterative-hardening/`.

The repeat pass reopened the timing row: Retry-After ignored zero, HTTP-date
and surrounding whitespace, while accepting signed `+1`. Ten syntax controls
produce five failures before correction (`retry-syntax-before.log`); ordinary
positive seconds, malformed/negative/fractional/overflow controls remain distinct.
The correction reuses the existing HLS HTTP-date parser, samples wall time only
for conversion and retains monotonic receipt-based storage. Contract reference:
[RFC 9110 section 10.2.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.2.3).
All ten syntax cases pass after correction. The eleven-method combined suite
passes 20 consecutive runs (`all-repeat-1.log` through `all-repeat-20.log`),
including 200 registered completion races per run. An additional actual Core
transfer cancellation case confirms that the first waiter does not stop its
survivor, while the last cancellation calls URLProtocol `stopLoading` and drains
the producer. The final focused suite is 12 methods (`final-focused.log`).
Remote CI, publication, Xcode 26, physical-device background/locked-storage and
real DRM/CDN/exporter acceptance are not substituted by local fixture success.

## Final implementation evidence

Implementation revision: `4ee83bd` (subsequent documentation-only closure does
not change the source/test/package/script fingerprint).

| Check | Fresh evidence under `.build/iterative-hardening/` |
| --- | --- |
| Full development preflight | `final-preflight.log`, exit 0; 673 registered methods, 667 ordinary passes and six default opt-in skips. Required runtime stage subsequently actually runs all six opt-in fixtures, plus PCM/mix/local-bridge controls. |
| Apple HLS conformance | Three playlists pass; reports at `.build/local-release-preflight/apple-hls/apple-hls-conformance.eauhQ7`. |
| SDK builds | macOS/iOS/tvOS/watchOS/visionOS, all four public library targets per SDK pass. This is package compilation, not device/signing acceptance. |
| Full TSAN | `final-tsan.log`, exit 0, same 673/667/6 counts; `tsan-instrumentation.log` confirms all five test bundles link the TSAN runtime. No race report; opt-in media runtime is validated separately without TSAN. |
| API/DocC/format | 2,148 name rows, 2,153 semantic signatures; all four catalogs compile with warnings as errors; 315 Swift files lint. |
| Consumer and release boundaries | Debug aggregate/individual consumers pass. Six additional script-fixture logs verify exact dependency graph/object pins, Draft/Ready boundaries, off-main/bad-tag rejection, Apple-tool gate and optional FairPlay acceptance. `actionlint.log` is empty with exit 0. These temporary fixture tags are not Stream tags. |
| Optimized external adoption | `consumer-aggregate-release.log` and `consumer-individual-release.log`, both exit 0. Actual macro start/events/receipt and late-cancel preservation succeed through Core and the atomic writer; the direct async convenience is also exercised. |
| Original public reproducer | `public-probe-build.log` and `public-probe-results.log`, exit 0. Both 200/TTL and 429/Retry-After delayed responses now make one request instead of two; immediate controls remain one. Eight concurrent plans share one request instead of eight. All four sequential cases retain healthy media plans. The original failing binary/results remain untouched in the external diagnostic directory. |
| Preservation | `code-preservation.log` matches the implementation fingerprint; Core original-tree 20-file hash check passes. Core pin and root lock hash unchanged; nine generated files in `Derived/` and `InnoStream.xcodeproj/` remain untracked and untouched. No push or cleanup-triggering remote action. |

Prior broad architectural review remains reusable context in
`PRODUCTION_HARDENING_2026_10_02.md`; the tests, platform builds and ownership
controls above are new runs of the current source, not old green results reused
as proof of the fixes. Bounded-retention assertions do not claim an RSS/leak or
power-loss durability certification. Application-owned adapters must cooperate
with cancellation; draining Steering producers still consume their bounded slot.

## Closure

The repeat review leaves no unresolved reproducible defect in the fixed matrix.
It found and closed one additional root cause (Retry-After syntax), rather than
stopping at the first timing fix. The final implementation passed the complete
local gates without changing Core, bypassing policy, loosening limits or skipping
failed tests. This is a locally verified development candidate, not a universal
absence-of-defects claim or publication approval. The supported Xcode 26 lane,
exact-SHA remote CI, version-only Core adoption and real device/service acceptance
remain separately unverified. Optional roadmap expansion is not treated as a bug.

Local commits: `63dddfc` receipt-time anchoring; `53660c8` bounded shared loads;
`6d8519b` offline ownership; `0fe6e3d` registered cancellation;
`4ee83bd` Retry-After correction. The closing commit changes documentation only.
