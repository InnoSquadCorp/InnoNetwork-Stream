# Macro-first redesign: local validation record

Date: 2026-09-30. Toolchain: Xcode 27.0 / Swift 6.4, macOS 27.
Scope: baseline `1604b16a12a03bc3213d72bb20a134eba4f211a1` through the
authorized ten-slice local redesign. No push, PR, automation, tag, publication,
consumer-source migration or deployment-floor change. This is not Ready.

## Inventory and closure matrix

All four runtime modules and the compiler-plugin/test target are in scope.
New public workflows are Draft, not independently reviewed/stabilized. The
pure parser stays in HLS; it is not a new dependency-free product. Bounded
delivery shares transport-neutral mechanics, not one native ownership policy.

| Risk row | Fresh evidence / closure | Specific boundary |
| --- | --- | --- |
| Normal parsing/planning | Full regression, discriminated-kind controls, typed selectors/loader, media metadata projection and actual external consumers | Parsed metadata is not executable backend support; preparation re-resolves on start |
| Hostile input/resource limits | Huge skip/duration/Unicode variable controls, immutable configuration validation, catalog count/byte/reference checks, bounded subscriptions/incidents | App storage reads must bound allocation before returning data |
| Failure/security | Stable HLS code controls, status-specific and backend-aware recovery, incident export redaction, corruption/unknown-version cases | Advice cannot bypass request policy or obtain credentials; no invented line diagnostics |
| Cancellation/commit | Operation/result separation, steering survivors, FairPlay stage barriers, staged metadata discard and commit-wins-late-cancel | Provider/device acceptance remains external; storage atomicity is app-owned |
| Concurrency/observation | Independent/capacity/slow/terminal subscriptions, DVR observer vs stop/discard, native observer cancellation, full-suite TSAN | Shared test transport registry belongs to one serialized suite; raw events are not export-safe |
| Retry/restoration/persistence | Actual VOD/offline automatic resume and DVR checkpoint controls; v1/v3 offline, v1 DVR and v0 catalog wire fixtures | Capability requires matching checkpoints/enabled policy; system background restoration needs device acceptance |
| Public contracts/examples | 2,126 name rows, 2,131 distinct signatures; async/throws, actor, generic, availability/conformance mutation controls; all five macros/manual fallbacks/README/DocC compilation | Snapshot gate is Xcode 27; Xcode 26 core lane is not an identical audio surface |
| Build/release/consumer | Five SDK library builds, runtime/Apple conformance gate, Debug aggregate/individual consumers; final Release consumer below | SDK compilation is not five-platform runtime, signing, published-tag adoption or remote CI |

## Evidence and corrections

Diagnostics remain in ignored `.build/macro-first-redesign/`; no failed
attempt is erased. Reused initial memory-footprint/profiler evidence is recorded
in the execution plan, not claimed as a new final-SHA performance benchmark.

- `final-full-preflight.log`: initial failure. A new standalone Live suite used
  the global URLProtocol registry concurrently with the existing serialized
  suite; the failure shows the CDN URL and the workflow URL together. The
  new network test now belongs to that same serialization boundary.
  `shared-registry-fixed.log` runs both affected methods in parallel and passes.
- `macro-isolation-control.log`: actor-isolated macro definitions fail specifically
  because generated configuration cannot satisfy nonisolated requirements.
  Pure configuration now explicitly uses `nonisolated`; native apply remains
  MainActor. `macro-isolation-fixed.log` validates all five actor-isolated
  definitions across a detached caller, qualified names and manual equivalents.
- `final-full-preflight-fixed.log`: 630 registered methods; 622 ordinary passes,
  six opt-in fixture skips and two unset-audio-fixture cancellations. Separate
  HLS quality/runtime gates execute all eight deferred cases. The next stage
  fails because preserved `InnoStream.xcodeproj` shadows the implicit package
  scheme; no generated file is deleted/renamed to solve that failure.
- The local preflight now builds exact SwiftPM library targets/SDK triples for
  macOS, iOS simulator, tvOS, watchOS and visionOS. Each `final-platform-*.log`
  passes all four library targets. This changes the local builder, not required
  CI checks or their thresholds. It does not claim application signing/linking.
- `final-full-tsan.log`: all 630 registered methods pass with the same eight
  fixture dispositions. The test binary links `libclang_rt.tsan_osx_dynamic`
  and new channel test objects contain `__tsan` instrumentation. No sanitizer
  report is observed. Apple runtime fixtures are a separate unsanitized gate.
- `semantic-fixtures.log` and `affected-fixtures-fixed.log` close semantic drift
  and reverse-dependency selection controls. `affected-audio-actual.log` runs
  the selected 18 audio methods. Full/release gates remain mandatory.
- Catalog wire migration/ownership/stage cancellation/commit failure tests pass.
  One active coordinator owns each store; real app adapters must enforce
  exclusive writer ownership or revision/CAS, not only serialized renames.
  Existing VOD/offline durable checkpoint capabilities are explicitly retained.
- `closing-recovery-control-failed.log`: an ambiguous optional `.none` caused
  bad URL, unsupported URL and untrusted-certificate errors to fall back to
  retry/restoration advice (24 failures across eight backends). Explicit
  `HLSRecoveryAction.none` fixes that actual report error; transient timeout
  and cancelled controls retain their expected behavior. The source candidate
  below is rerun after this correction, not inferred from earlier green logs.

`final-consolidated-preflight-v2.log` exits 0 (`local-release-preflight: OK (full)`):
630 registered methods, 622 ordinary passes and all eight deferred fixture cases
executed by the separate runtime gate; Apple conformance, all five SDK library
builds, format (303 files), API contracts and Debug consumers pass.
`final-release-consumer-v2.log` exits 0 with `package-identity-consumer: OK` after
the optimized aggregate consumer build. These source-candidate results precede
only documentation closure; final documentation/fixture/format checks are in
`closing-contract-checks.log`. `final-full-tsan-v2.log` is the full sanitizer
run after the recovery correction; earlier un-suffixed logs remain historical
source-candidate evidence.

The unchanged `Package.resolved` SHA-256 is
`00e9dbd5cadfc623a0d156d0035e797066c268873dce49c53e673d54b4530e28`.
All nine original generated files pass their before-hash manifest. Final local
HEAD/tree, exact commit range, tracked/index disposition and preservation checks
are recorded after the closing commit in `final-git-state.log` and
`final-preservation.log`. No source-candidate result is presented as a new
remote-SHA CI or device acceptance result.

## Remaining boundaries

Xcode 26/Swift 6.2 remote core tests and final-SHA CI are not run in this local
request. Decoded audio is compiler-6.4-gated. Physical-device native background
restoration, real FairPlay server/entitlements/key store, realtime audio deadlines,
actual app persistence durability/multi-process ownership and first published
Stream tag adoption are not established by these tests. Existing AVFoundation
unbalanced-listener and renamed-cache alternate/stale-output diagnostics remain
visible; their framework/cache origins are not proven by passing tests or TSAN.

InnoNetwork remains pinned to published 6.0.0; Stream remains independently
versioned 1.0.0 Draft. The preserved generated project and Derived files are
checked against their original hash manifest. No push means no post-push cleanup
was triggered. A green local record is not proof that no further defect exists.
