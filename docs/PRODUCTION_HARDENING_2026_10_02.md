# Stream production-candidate hardening

## Frozen scope and execution contract

The owner requested production-quality Stream implementation, not another small
isolated improvement, while retaining macro-first use and reusing Core rather
than rebuilding its transport. Local implementation and commits are authorized;
this task does not publish a tag or claim real-service acceptance.

Baseline: `5287b1afde032b9c71ce3fd8765a4212abad8ae5` on
`codex/stream-core61-development`, with clean tracked files. Preserve untracked
`Derived/` and `InnoStream.xcodeproj/`. Core remains the remote branch locked at
`91b4b417ca134d0f837f8e000846cd0478e7d439`; no implicit dependency upgrades.
Platforms/products: HLS, Live/DVR, AVFoundation, Audio and the compiler-plugin
target; aggregate/individual consumers; five supported Apple SDKs. Xcode 27 /
Swift 6.4 is available locally. Prior exact-Core verification is documented in
`CORE_BRANCH_VALIDATION_2026_10_02.md`; it is reused baseline evidence, not proof
for later implementation.

## Ordered work and closure matrix

Each row covers applicable normal, failure, cancellation, concurrency,
retry/restoration, resource-limit, observability and admission paths. Record
reproductions and passing controls before corrections. Do not target a finding
count, silently loosen a contract, or make the primary API manual-first.

| Phase | Scope and exit requirement | Status |
| --- | --- | --- |
| 1 | Core boundary: request adaptation, bounded transfer, retry identity, response/Range validation, cancellation and redirects | Review pending |
| 2 | Parser/selection: typed documents, resource references, count/byte/numeric limits, unsupported execution vs inspection | Review pending |
| 3 | VOD/offline: operation ownership, ordered bounded writes, cancellation, checkpoint/resume, atomic commit and disk failures | Review pending |
| 4 | Live/steering: reload/delta/freshness, fallback and shared waiter lifetime, bounded polling/retention | Review pending |
| 5 | DVR: first terminal intent, snapshot isolation, partial/MAP/GAP/renditions, recovery and durable publication | Review pending |
| 6 | Native: background session identity, delegate ordering, restoration, observation and local playback bridge | Review pending |
| 7 | FairPlay/audio: stage admission, error/cancel completion, key ownership, native read cancellation and bounded real-time delivery | Review pending |
| 8 | Catalog/incidents: staged metadata transaction, schema corruption, ownership, bounded/redacted diagnostics | Review pending |
| 9 | Macro-first adoption: all five macros, dynamic/manual equivalence, declaration diagnostics, cancellation through actual Core, coherent production examples | Review pending |
| 10 | Packaging/operations: DocC, public signatures, privacy/localization, development vs release gates, deterministic local inner loop | Review pending |
| 11 | Consolidated verification: full normal and TSAN suites, bounded endurance/resource checks, HLS runtime/conformance, Debug/Release consumers, five SDK builds | Pending final source |

End when every row has static/fresh/reused evidence or an explicit unavailable
environment, confirmed in-scope defects are fixed with controls, and operational
documentation explains the supported contracts. Optional features require a
concrete supported workflow; quantity of new APIs is not an exit criterion.

## Boundaries

No independent CDN/transcoding/DRM service, player UI, automatic destructive
pruning, credentials, unsupported background scheduling or new transport stack.
Physical-device background restoration/locked storage, production CDN/FairPlay,
real-time hardware deadlines, Xcode 26 parity and final remote release gates
cannot be certified by local fixtures. Core's release/CI status remains separate
from Stream correctness. Version-only publication still rejects a branch pin.

## Findings, corrections and evidence

### Transfer-boundary correction

Confirmed against the baseline with passing controls before production edits:

- Request adapters could change a GET into POST or add data/stream bodies while
  retry eligibility still used the original GET. The shared HLS boundary now
  rejects these changes before transport; header/URL adaptation is retained.
- Pre-cancelled work still invoked application adaptation. Cancellation is now
  checked before and after the async adapter, without replacing Core transport.
- A zero-byte resource could publish a partial single-file or offline package
  if another segment was nonempty. Reject each empty resource, including
  padding-only AES plaintext (adjacent regression control).
- DVR accepted missing/invalid Content-Range totals and published short/long
  open-ended range responses without Content-Length. VOD and DVR now share a
  package-only decimal/range parser; actual received length must match even when
  the HTTP response omits Content-Length. Malformed responses leave no output.

Fresh logs under `.build/production-hardening/`: `transfer-boundary-before.log`
(11 assertion failures, normal header/nonempty controls pass), `range-before.log`
(14 assertion failures, valid total/unknown total/exact length controls pass),
`transport-regression.log` (131 downloader + 136 live networking tests pass),
`boundary-final.log` (all added boundary/AES/range cases pass). These are local
Xcode 27 results; assertions are not independent defect counts. No public Core
API, Core source, retry policy, URL admission or trust behavior was weakened.
