---
date: 2026-09-30
status: Draft
owner: Codex
decision-owner: repository owner
document-depth: expanded
---

# Macro-first Stream redesign and execution plan

## Contract and evidence

The owner authorized planning and sequential implementation, permitting source
breaking changes and requiring a macro-first approach. This document records
implementation decisions; the specific new API has not received a separate
design review. Do not describe Draft decisions as independently reviewed.

Baseline: `1604b16a12a03bc3213d72bb20a134eba4f211a1`, freshly fetched main,
clean tracked/index state. Preserve untracked `Derived/` and
`InnoStream.xcodeproj/`. InnoNetwork remains resolved to published 6.0.0;
SwiftSyntax remains compatible with its locked 603.0.2 dependency. Preserve
Swift 6 language mode, the existing Apple platform floors, module names,
MIT licensing and `InnoNetwork-Stream` branding.

The same-SHA comprehensive review found five actual-path defects: oversized
LL-HLS skip allocation, finite duration conversion trap, intermediate variable
expansion, shared steering activation cancellation, and persistent FairPlay
stage cancellation. Normal passing controls and failure evidence remain in
`.build/code-quality-review-2026-09-30/`. Earlier full tests/TSAN are baseline
evidence, not validation of new code. Current remote CI fails; a local redesign
does not close remote release gates.

No push, PR, branch-protection change, automation, tag, publication, consumer
source migration, platform removal or deployment-floor increase is authorized
by this implementation request. Local edits and diagnostics are in scope.

## Architecture and expensive decisions

```text
declarative macro input (compile-time validation)
    -> generated typed construction / operation entry points
    -> validated immutable runtime configuration and domain values
    -> explicit operation owner / cancellation / awaitable terminal result
    -> existing bounded InnoNetwork transport and atomic storage adapters
```

Macros generate contracts and boilerplate, not hidden network or disk effects.
Runtime validation remains authoritative for dynamic values and hostile server
input. Do not let a macro imply that a prepared snapshot is still executable.
Compile-time checks cannot establish entitlement, resource identity or trust.

| Decision | Chosen direction | Alternative and trade-off | Recheck |
| --- | --- | --- | --- |
| Primary user API | Declarative workflow macros with typed generated helpers | Manual builders are easier to debug but repetitive; retain an advanced equivalent | Expansion/diagnostic snapshots plus external Debug/Release consumers |
| Macro dependency | Dedicated compiler-plugin target; shared SwiftSyntax 603.0.x | Disabling Macros would contradict primary user flow; no runtime SwiftSyntax imports | Locked dependency graph and Xcode trust contract |
| Models | Distinct multivariant/media views and parser vs executable phases | Flat optional models are source-compatible but allow contradictory construction | Complete metadata projection and adopter migration fixtures |
| Work ownership | Explicit operation handle; subscription is observation | Stream-owned convenience remains useful for foreground scopes | One/all waiter cancellation, bounded events and terminal races |
| Resource limits | Validate and account before allocation or admission | Post-allocation output checks do not protect transient memory | Boundary and adversarial allocation controls |
| Persistence | Preserve versioned formats and ownership; optional metadata coordinator | One universal store risks moving system assets/deleting app media | Migration, corruption, unknown-version and reconciliation controls |
| Native integration | Keep AV MainActor and realtime audio constraints | A universal actor cannot safely replace native callback contracts | Runtime tests plus device/provider acceptance |
| API stabilization | Workflow/signature-based rather than declaration-count targets | Removing public values indiscriminately breaks metadata consumers | External source compatibility and semantic API snapshots |

## Ordered slices and exit criteria

Execute in order. A slice is complete only with fresh focused checks and passing
controls; the final status must distinguish local completion from release gates.

| Step | Code and contract work | Validation / exit | State |
| --- | --- | --- | --- |
| 1 | Guard skip history before allocation, checked authoring comparison, budget variable expansion before append | Huge skip, huge finite duration, repeated/Unicode URI and attribute expansion; normal/boundary controls | Locally complete |
| 2 | Shared activation waiter lifetime; FairPlay stage admission and persistent-write commit semantics | One/all cancelled waiters, surviving waiter, native completion after cancellation, each DRM stage and once-only completion | Locally complete; provider acceptance excluded |
| 3 | Validated immutable limits/configuration and effective settings | Invalid dynamic values typed failures, exact accepted boundaries, existing normalized compatibility path explicit | Initial VOD configuration locally complete; other backend settings in step 7 |
| 4 | Dedicated macro target and initial download definition; compile-time bounds/collision diagnostics | Exact expansions, invalid declarations, no conditional DEBUG surface, actual external macro consumer | Initial VOD macro locally complete, Draft |
| 5 | Explicit foreground download operation handle, independent bounded subscriptions, awaitable receipt and terminal ownership | Zero/slow/multiple observers; result waiter vs operation cancel; late commit; cleanup and limits | VOD lifetime locally complete, Draft |
| 6 | Discriminated parser-produced model views, pure parser/loader effect separation and macro-first advisory preparation | Kind invariants, complete metadata preservation, lenient inspection vs unsupported execution, trust/redirect boundaries | Initial typed parse/prepare path implemented; full legacy/model migration remains |
| 7 | Generalize coherent lifetime APIs to live/DVR/native adapters and stage transitions | Existing DVR intent/native background behavior retained; observation cannot cancel background work | Pending |
| 8 | Optional bounded/versioned media metadata coordinator and explicit reconciliation | No implicit deletion/move of app/native/key resources, atomic persistence, migration/corruption limits | Pending |
| 9 | Structured parse/config/operation failures, capability/recovery and bounded redacted incidents | Preserve error codes/security redaction, drop/sequence semantics and backend-specific support | Pending |
| 10 | Macro-first examples/migration, semantic API checks and affected fast/full CI contract | External macro/manual consumers, exact counts, trust/readiness diagnostics; final full regression/runtime/API/format | Consumer/docs/count-based gate prepared; semantic API/selection/remote gates pending |

The first macro is a focused download definition rather than an umbrella
service. It validates declaration shape and constant limits, and generates
helpers delegating to the same runtime validated configuration and operation
owner as the manual equivalent. Expansion tests alone do not prove runtime
semantics. Add live/native definitions only when their distinct ownership
contracts are verified, not by generating one generic method for every backend.

### Remaining implementation order

This is the first coherent local candidate, not completion of all ten slices.
It adds migration paths before destructive public-surface removal. The pure
parser stays in the existing HLS module; no independent, dependency-free parser
product or measured binary/build-size improvement is claimed.

1. Finish step 6's legacy-model migration: inventory selector/inspection users,
   add validated authoring input only where needed, and move typed documents
   through backend planning without discarding metadata. Retain current prepare
   freshness: a preview never becomes an executable retained network plan.
2. Step 7: add macro-first live/DVR definitions on top of validated effective
   timing/count settings; introduce a foreground watch owner with independent
   observations and authoritative terminal snapshots. Preserve DVR stop/discard
   intent and native background task IDs, MainActor adapters and realtime audio
   callbacks. Verify observer cancellation separately for each backend rather
   than assuming VOD ownership semantics apply to system-managed work.
3. Step 8: define typed asset/recording IDs and an opt-in metadata coordinator.
   Use an explicit app-owned persistence boundary, bounded/versioned DTOs and
   staged atomic metadata commits. Test corruption, unknown versions, cancelled
   commit, missing asset reconciliation and each ownership class. Do not add
   signed-URL renewal or automatic pruning to this slice.
4. Step 9: classify parse/config/operation failures and capability/recovery
   decisions without renumbering existing NSError telemetry. Remove obsolete
   emitted-error claims only with migration fixtures. Add bounded incident
   composition with operation correlation, sequence/drop/truncation semantics
   and tested URL/header/key-payload redaction; raw operation events are not an
   export-safe incident format.
5. Step 10: snapshot signatures, async/throws, generics, availability and
   isolation, plus explicit persisted-format fixtures. Select affected local
   suites by reverse dependencies; keep complete release/nightly gates. Finish
   macro-first examples and external migration fixtures for each backend, then
   validate exact final candidate on all supported toolchains/platforms. Do not
   replace these gates with counts or silently loosen required checks.

## Migration and recovery

- Keep caller-owned request policy, credentials, native player/UI and key storage.
- Preserve validated checkpoint schemas and existing assets. Public type names
  must not silently redefine encoded storage formats.
- Replace unsupported legacy entry points only with documented equivalents and
  external migration fixtures. Breaking permission does not require gratuitous
  removal of useful APIs.
- Retain immutable runtime construction as a documented advanced/debug fallback
  if compiler-plugin trust or toolchain execution prevents macro expansion.
- Stop a slice if correctness controls fail; preserve original failures and
  differential evidence. Do not rerun until green or weaken a performance limit.
- Use incremental local checks while coding and one complete validation at a
  coherent final candidate. Do not launch duplicate remote CI on each slice.

## Non-goals and remaining external gates

No new player chrome, CDN/transcoding service, generic trust-bypassing HTTP
stack, automatic storage eviction, published InnoNetwork 6 API rewrite or
consumer migration. Signed-URL renewal needs an explicit identity/authorization
contract and is separate from the metadata catalog implementation.

Physical-device background restoration, dedicated CDN/FairPlay provider,
credentials/entitlement acceptance, realtime audio deadlines, Xcode 26 parity,
final-SHA remote CI and first published-tag consumer validation remain external
gates. Tests passing locally are not release-ready proof.

## Execution log

- 2026-09-30: plan established before production changes; baseline and remote
  parity rechecked. Macro opt-out proposal superseded by owner's macro-first
  instruction. No remote mutations.
- Implemented F1-F5 with passing controls and the initial VOD macro, validated
  configuration, operation owner and pure typed parse/advisory prepare path.
  Breaking permission is used to reconsider contracts, not to rewrite published
  Network 6.0.0 or change persisted schemas. No local commit or push yet.
- Fresh diagnostics live in `.build/macro-first-redesign/`. Baseline
  `.build/code-quality-review-2026-09-30/` reproductions remain preserved. The
  first Int.max delta fixture failed in sequence arithmetic before reaching the
  merger; sequence zero reaches the intended allocation boundary and recovers
  through a full reload. The first pure-parser byte fixture omitted the existing
  normalized terminal-newline reservation; its corrected boundary passes.
- A single actual-path 65,536,000-byte variable-expansion attempt now fails with
  the typed limit before constructing it: local peak footprint 8,208,960 bytes
  versus the preserved original 152,928,952-byte probe. This is allocation
  evidence, not a statistical throughput benchmark. Shared activation's actual
  cancelled-adapter control admits no replacement-playlist request.
- `candidate-tsan-ownership.log`: seven focused ownership/FairPlay tests passed with
  deterministic admission/commit barriers, including parameter variants. This
  is focused TSAN, not a full-suite sanitizer claim.
- `candidate-hls-quality.log`: all eight fixture-dependent runtime cases separately
  passed, together with three Apple validator/report fixture sets. This was
  rerun after adding the typed parser migration for this candidate; earlier
  `hls-quality.log` is separate intermediate evidence. Native device/provider and
  realtime acceptance remain excluded.
- Final local candidate verification is recorded separately in `candidate-*`
  logs. API counts are 1,942 (75 new Draft declarations), not semantic API or
  promotion evidence. New examples exercise Stream and Network macros together,
  the manual recovery boundary, the pure parser, and the README/DocC workflow in
  external consumers. Final supported-toolchain/platform and remote release
  gates remain open.
- Final unit execution (`candidate-full-tests.log`) registered 606 methods:
  four macro, 289 HLS, 144 live, 151 AV and 18 audio. 598 ordinary cases passed;
  six opt-in fixture tests skipped and two audio fixture tests cancelled when
  unset. All eight are accounted for by the separate successful runtime gate.
  Parameter invocations are not additional registered methods. Focused TSAN is
  six HLS methods and one persistent-key method with one/all/stage variants.
- External aggregate/individual Debug consumers and aggregate Release consumer
  passed (`candidate-external-consumers.log`, `candidate-release-consumer.log`).
  The normal parser consumer typechecked; the invalid external construction
  consumer was rejected specifically for inaccessible parser-produced payload
  initializers (`valid-document-consumer.log`, `invalid-document-consumer.log`).
  Formatting passed for 285 files; public API passed 1,942/1,942; release docs
  correctly remain Draft. These are uncommitted working-candidate results on
  the recorded baseline, not evidence for unchanged HEAD or remote CI.
