# Optional metadata catalog (Draft)

`@HLSCatalogDefinition` validates count/encoded-byte budgets. Its generated
`makeCatalog(persistence:)` performs no effects. Explicit `restore`, `upsert`,
`remove` and `reconcile` perform bounded metadata transactions.

Records contain a typed UUID, an ownership class, a maximum-128-byte opaque
ASCII identifier and availability. Resolve that identifier in the application,
not in this package. URLs, paths, tokens and keys are not catalog fields.
Reconciliation reports missing assets without removing records or media.
All three ownership classes remain application/system-owned.

Storage is opt-in and app-owned. `read(maximumBytes:)` must bound allocation
before reading. `stage` creates metadata staging without touching existing
metadata. `commit` must atomically publish or throw without changing existing
metadata; successful publication wins late cancellation. `discard` is idempotent
and removes staging only. One store must serialize all writers across catalog
instances/processes. The coordinator rejects reentrant mutations, and exposes
old metadata until successful commit.

No default filesystem adapter, native asset deletion or persistent-key access
is provided. Local tests validate transaction orchestration against explicit
staging/commit barriers; an application's actual storage durability and
multi-process serialization remain that adapter's acceptance obligations.

The bounded JSON envelope is version 1. The explicitly defined pre-release v0
fixture omits availability and migrates to `.unknown`; restore does not rewrite
it automatically. The next explicit mutation writes v1 with sorted keys and
identities. Corruption, duplicate IDs, unknown versions and oversized snapshots
leave current state unchanged. This is a new optional format; existing offline
package and DVR checkpoint formats are unchanged.
