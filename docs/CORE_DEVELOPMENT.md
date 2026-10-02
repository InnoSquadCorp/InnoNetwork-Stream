# Core branch development

Stream development uses the remote Core branch `codex/core-stream-followup`,
in [Core PR #141](https://github.com/InnoSquadCorp/InnoNetwork/pull/141), stacked
on `codex/encoded-request-contract` (Core PR #132). The root package and
the aggregate/individual external consumer select the same branch. The root
`Package.resolved` records the exact commit verified with Stream.
The initial development lock is `91b4b417ca134d0f837f8e000846cd0478e7d439`.

`bash Scripts/check_innonetwork_dependency.sh --development` verifies the
manifest branch, lock, active dependency graph, actual checkout revisions and
Git object availability. Transitive dependencies retain versioned locks. A
local path, another branch, a stale checkout or a mutated lock fails the check.
Updating the remote branch does not automatically upgrade Stream's lock.

For normal development:

```bash
bash Scripts/check_innonetwork_dependency.sh --development
bash Scripts/run_local_release_preflight.sh --quick --development
```

At an integration milestone, run the full development preflight with
`--full --development`; this includes bounded HLS fixtures, supported AVPlayer
and audio runtime probes, Apple HLS conformance and five SDK builds. Use the
macro-first aggregate and individual consumers in Debug and Release. Focused
tests remain the inner development loop.

Release validation remains version-only. The default dependency gate and the
unchanged Release workflow reject this branch lock. When Core is published,
update both manifests to its compatible version requirement, resolve the lock,
restore version-only CI checks, and run the full release preflight and clean
external consumer against the published tag.

The next Stream quality work covers actual HLS transfer, cancellation, retries,
live/DVR ownership and native adapters against this Core revision. Dedicated
FairPlay service, locked-device restoration and production CDN acceptance still
require the application owner's environment.
