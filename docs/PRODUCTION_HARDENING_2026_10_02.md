# Stream production-candidate hardening

> Historical record — retained for the source, date and environment below.
> For the published 6.1.1 contract, use the [current quick start](../README.md)
> and [documentation map](README.md). Unexecuted checks are not implied passes.


This is the historical `15c03db` closure snapshot. The subsequent
[iterative review and corrections](ITERATIVE_HARDENING_2026_10_02.md) reopen the
Steering timing row and supersede the final API counts and verification totals.

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
| 1 | Core boundary: request adaptation, bounded transfer, retry identity, response/Range validation, cancellation and redirects | Closed locally: shared GET/cancellation and Range corrections below; downloader/live networking regression controls; exact Core checkout/lock gate. No replacement transport or trust bypass. |
| 2 | Parser/selection: typed documents, resource references, count/byte/numeric limits, unsupported execution vs inspection | Closed locally: parser/reference/variable-expansion limits and execution admission reviewed; malformed, limit, selection and playlist fixture tests in the full suite. Inspection-only syntax remains explicitly separate from supported execution. |
| 3 | VOD/offline: operation ownership, ordered bounded writes, cancellation, checkpoint/resume, atomic commit and disk failures | Closed locally: operation/resource pipelines and package/resume stores reviewed; atomic, corruption, lease, cancellation and AES controls run; empty-resource corrections and macro-first packaging added. Disk fixtures are not power-loss durability proof. |
| 4 | Live/steering: reload/delta/freshness, fallback and shared waiter lifetime, bounded polling/retention | Closed locally: polling termination, full-reload fallback, shared recovery and immutable pathway plans reviewed; delta/freshness/failover controls plus reproduced 64-entry cache correction. |
| 5 | DVR: first terminal intent, snapshot isolation, partial/MAP/GAP/renditions, recovery and durable publication | Closed locally: recorder/writer lifecycle and snapshot ownership reviewed; Live suite and actual local HLS runtime fixtures cover restoration, speculative resources and publication; stricter advertised/received range length controls added. |
| 6 | Native: background session identity, delegate ordering, restoration, observation and local playback bridge | Fixture-closed: admission, event-hub retention/termination, session leases and local HTTP range bridge reviewed and tested. Real-device background relaunch/locked-storage acceptance remains unavailable. |
| 7 | FairPlay/audio: stage admission, error/cancel completion, key ownership, native read cancellation and bounded real-time delivery | Fixture-closed: stage-boundary cancellation, key ownership and pending native reads reviewed; FairPlay/audio suites and required PCM/mix runtime fixtures pass. Production license services and real-device timing remain unavailable. |
| 8 | Catalog/incidents: staged metadata transaction, schema corruption, ownership, bounded/redacted diagnostics | Closed locally: staged compare-and-commit, migration/corruption and cancellation controls; configured catalog ceiling 512 records/1 MiB; incident event retention/redaction reviewed and tested. App-owned persistence is an explicit contract, not an implicit filesystem implementation. |
| 9 | Macro-first adoption: all six macros, dynamic/manual equivalence, declaration diagnostics, cancellation through actual Core, coherent production examples | Closed locally: compiler expansion and diagnostics, manual-equivalence controls and real external aggregate/individual consumers. New offline macro preserves pure construction and caller-task ownership. |
| 10 | Packaging/operations: DocC, public signatures, privacy/localization, development vs release gates, deterministic local inner loop | Closed locally: four warning-free DocC catalogs, exact public contract and script fixtures; privacy/localization/package resources and development/release separation reviewed. Remote CI and version-only publication remain separate gates. |
| 11 | Consolidated verification: full normal and TSAN suites, bounded endurance/resource checks, HLS runtime/conformance, Debug/Release consumers, five SDK builds | Closed locally on the final implementation; exact results below. Remote/device/service boundaries stay open, not silently counted as passes. |

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

### Macro-first atomic packages

The uncovered primary workflow was offline multi-rendition packaging. Added
`@HLSOfflinePackageDefinition` as the sixth definition, with pure generated
configuration, media-free `prepare`, effect-free construction and async
`downloadPackage` in the calling task. It reuses the existing atomic/resumable
engine and Core transport. Dynamic/manual settings use the same single-file
validation boundary instead of another set of validation rules. Six effective
read-only settings and the new workflow comprise exactly 13 additional public
name/signature rows; no existing signature changed (2,139 names / 2,144 signatures).

Fresh controls include invalid literals/cross-field limits/declaration shapes,
dynamic error parity, actor-isolated external expansion, caller cancellation,
real Core transport into atomic packaging and reopening checksum-validated output.
`offline-macro.log`, normal/full TSAN logs and the external consumer logs record
these checks. The first consumer fixture incorrectly assumed receipt size meant
media only; the documented receipt includes playlists/manifest. Its initial
failure remains in `full-preflight.log`. The correction checks complete package
size against a validated reopened receipt; no product behavior was changed to
satisfy that incorrect assertion.

### Long-lived cache and operation retention

Static review found that reusable downloaders/planners retained an unlimited
dictionary of Steering URLs. The public downloader reproducer resolves 65
distinct presentations, refreshes entry 0, admits entry 64 and revisits entry 1.
The original kept every entry (`steering-retention-before.log`: failures for
200/410/503, hot-entry control passes). A 64-entry LRU now bounds both successful
and negative entries; eviction re-fetches the older entry without re-fetching the
hot control (`steering-retention-after.log`: four focused tests pass).

Scope of eviction is subsequent independent planning, not an active playback
session: each plan holds immutable candidates; resource failover consumes those
candidates rather than reloading this cache. In particular this does not weaken
the per-playback 410 no-retry rule in the
[Apple Content Steering specification](https://developer.apple.com/streaming/HLSContentSteeringSpecification.pdf).
The count bound is not a process RSS guarantee; per-manifest byte limits remain.

The new operation-channel endurance test covers 32 cycles, 64 slow subscribers,
8 concurrent producers x 125 events, 16 cancelled waiters per cycle and 65 late
subscriptions after every completion. It checks 2,048,000 bounded subscriber
deliveries, independent cancellation, first terminal result and released slots.
Normal and fully instrumented TSAN runs pass; this is a bounded retention/race
regression, not a real-device memory or timing benchmark.

### Executable documentation gate

Actual DocC compilation exposed macro links missing full parameter signatures,
a stale overload, an undocumented initializer parameter and sibling-module
links without root paths. `check_docc.sh` compiles all four catalogs with warnings
as errors, exported sibling archives and absolute symbol paths. It shares the
API gate's generated graphs in preflight/CI instead of recompiling the package.
The exploratory one-module and unsupported multi-root invocations are retained
separately from the successful four-archive command. `docc-absolute-links.log`
confirms all catalogs pass, without suppressing diagnostics. Link semantics were
checked against [Swift DocC's link-resolution documentation](https://swiftlang.github.io/swift-docc/documentation/swiftdocc/linkresolution/).

## Final consolidated evidence

Implementation, tests, contract snapshots and workflow source are committed at
`db848a47683e50ad2bd1f6b164f84bf73ef2534f`. The final evidence commit changes only
this record, README navigation and current roadmap inventory. Logs below are
fresh after the cache correction, not reused pre-correction success. A source,
test, script and manifest fingerprint is retained in
`.build/production-hardening/final-code.sha256`.

| Check | Fresh result / retained evidence |
| --- | --- |
| Full development preflight | `final-preflight.log`, exit 0; 661 registered methods, 655 ordinary passes, six opt-in runtime cases skipped in the ordinary suite and actually executed in the required fixture stage |
| Full TSAN | `final-tsan.log`, all five test bundles pass with the same ordinary/opt-in boundary; all five executables link `libclang_rt.tsan_osx_dynamic.dylib`; no reported races |
| Operation retention | The 2,048,000-delivery endurance case passes in both ordinary and TSAN runs; independent cancelled waiters and released subscriber capacity are asserted |
| Runtime and Apple conformance | Six opt-in runtime cases pass, plus decoded/audio-mix probes; three Apple HLS playlists pass, reports in `.build/local-release-preflight/apple-hls/apple-hls-conformance.AyaCE8/` |
| Supported SDK compilation | macOS, iOS simulator, tvOS, watchOS and visionOS; each of four library targets passes in the final preflight. These are library compilations, not signed application/device acceptance |
| Documentation and API | Four warning-free DocC archives in `.build/docc-contract/run.ir4q80/`; 2,139 public names and 2,144 semantic signatures pass; 311 Swift files pass formatting |
| Debug external consumers | Aggregate and individual product modes pass in final preflight; six Stream macros, Core macro, manual equivalence, actor isolation, real bounded transport and committed-package reopening are exercised |
| Release external consumers | `final-consumer-aggregate-release.log` and `final-consumer-individual-release.log`, both exit 0; four imports, six Stream macros, Core macro/cancellation, README and atomic offline transfer pass in optimized builds |
| Operational negative controls | Shell syntax, actionlint, eight CodeQL positive/negative controls, dependency-cache/lock/object controls, release-state/candidate/ref guards and Apple HLS gate fixtures pass; no publication gate weakened |
| Publication boundary | `final-published-gate-rejection.log`: the unmodified published-dependency gate correctly rejects the current branch pin. This expected rejection is not counted as a release pass |
| Core and workspace preservation | Root manifest/active dependency graph/checkout/object gate passes at Core `91b4b41`; root lock SHA256 remains `f9b2fc4f0003580bcfe7e98c48af422922ed0460b5bd2a6d1e2dc583e1bc541e`. Original Core's 20-file preservation manifest passes. The nine generated Stream project/Derived files remain untracked and uncommitted |

Implementation commits, in order:

- `5635d20`: validate transport/media boundaries before publication.
- `88d6603`: macro-first atomic offline package workflow and executable consumers.
- `dc6160c`: bounded Steering cache and saturated operation delivery regression.
- `db848a4`: actual four-catalog DocC build in shared contract gates.

## Completion and release decision

Confirmed in-scope defects have reproduced failing controls, corrected behavior
and fresh regression evidence. No unresolved reproducible defect is being
silently deferred from this matrix. This is not a proof of absence of defects or
a claim that all deployment environments were exercised.

Optional extensions remain separate: app-specific durable catalog adapters,
cross-store capacity inventory and exporter/native event ingestion need an
actual adopter contract. They are not required to make the existing supported
workflows function, and no player UI or second transport stack was added.

This candidate is still **not authorized for publication**. Stream deliberately
tracks Core's development branch; Core PR #141 is Draft, and current remote
checks are not a clean final release result. Required next gates are the
compatible published Core version, deliberate version-pin migration, exact-SHA
Stream remote checks/protected review and version-only release preflight.
Physical-device background/locked-storage, production CDN/license services and
real-time device acceptance remain adopter-specific and explicitly unverified.
No Stream push, merge, tag or release was performed for this hardening work.
