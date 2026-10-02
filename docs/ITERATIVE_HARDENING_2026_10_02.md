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
| Macro-first offline owned operation | Pending: progress/receipt independence, owner cancel/release, atomic success/failure and external consumer |
| Registered waiter cancellation | Pending: registration barrier, completion/cancel ordering and capacity reuse |
| Adjacent VOD/DVR/resource/API contracts | Pending: repeat review and regression |
| Final source verification | Pending: normal + TSAN, runtime/Apple HLS, five SDKs, Debug/Release consumer, API/DocC/scripts |

The original delayed-response reproducer is retained at
`/private/tmp/stream-current-review.Tf9RNq/`; immediate controls make one request,
delayed 200/429 cases make two. That bug predates the latest LRU correction.
New logs will be retained under `.build/iterative-hardening/`.
Remote CI, publication, Xcode 26, physical-device background/locked-storage and
real DRM/CDN/exporter acceptance are not substituted by local fixture success.
