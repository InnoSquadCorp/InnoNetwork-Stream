# Tests, metadata and failure handling

Use public imports in external consumers. `@testable import` is appropriate
only for the application's own fixture target, never a release library module.
The bundled fixture uses session-scoped URLProtocol mocks with no external
server. Test completed bytes/receipts, existing-destination rejection, cancelled
operations and observer independence rather than only matching generated text.
Keep temporary directories and sessions scoped and cleaned up.

Compile macro definitions and dynamic `*Defining` equivalents. For ownership
changes add deterministic gates and failure controls; do not infer cancellation
from arbitrary sleeps. Validate the actual graph and checkout SHA as well as
`Package.resolved`: SwiftPM may reuse stale cache or omit a prebuilt SwiftSyntax
node from `show-dependencies`. The helper checks its workspace/prebuilt entry.
Unset `INNONETWORK_LOCAL_PATH`. Strict concurrency/warnings-as-errors compilation
is local consumer evidence; it is not native background, DRM or physical playback
acceptance. The fixture only constructs audio settings behind compiler/OS guards.

## Metadata catalog

Prefer `@HLSCatalogDefinition(maximumEntries: 128, maximumSnapshotBytes: 65_536)`.
`try Definition.makeCatalog(persistence: store)` is effect-free; `restore`,
`upsert`, `remove`, `reconcile` are explicit actor transactions.
`HLSMediaRecord(id: HLSMediaID(), ownership: .offlinePackage, reference: "movie-1")`
uses a bounded opaque ASCII identifier, not a URL/path/token/key. Catalog removal
removes metadata only; reconciliation marks missing media without pruning it.

Dynamic: `HLSCatalogDefining` + `HLSMediaCatalogConfiguration.validated(...)`.
An app-supplied `HLSMediaCatalogPersisting` must bound `read(maximumBytes:)` before
allocation, stage without modifying existing data, atomically commit or leave
existing data unchanged, and discard staging idempotently. Use one coordinator
per store plus exclusive writer ownership or CAS across processes. The library
does not provide a default disk adapter or guarantee app storage durability.

## Failure and incident contracts

`HLSFailureReport.classify(error, backend: ..., operationID: ...)` carries typed
category and conservative recovery advice. It does not carry arbitrary error
text/URLs/credentials and never executes a retry. Handle cancellation without
retry; authorization requires fresh application action; trust failures require
security handling. Resume advice still requires a real matching checkpoint and
enabled policy. Native restoration uses system tasks. Do not recursively unwrap
unknown error chains to invent transport semantics.

`HLSBackendCapabilities.forBackend(...)` describes lifetime/recovery, not whether
an arbitrary stream can execute. `HLSIncidentBuffer` is bounded application-side
scalar metadata, not a network interceptor or raw event log. Preserve its typed
fields; do not add URL/path/header/body/key data or invoke its actor on realtime
audio callbacks.
