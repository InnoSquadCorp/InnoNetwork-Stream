# Core dependency contract

The root package and `Tests/PackageIdentity/Package.swift` require published
InnoNetwork `6.1.0` exactly. The root `Package.resolved` records tag commit
`79ff9f535a0a15ad8b52ce49cb5a4b1ea1dfec16`. Stream's direct SwiftSyntax
requirement is 604.0.x, matching Core's compiler-plugin requirement; runtime
targets never import SwiftSyntax. Core 6.1.0 also requires Swift Crypto 5.x.

`bash Scripts/check_innonetwork_dependency.sh` verifies the exact manifest
requirement and approved version/revision, active graph, actual checkout
revisions, and Git object availability. A local path, branch, floating range,
unapproved version, stale checkout, or mutated lock fails the published check.
The consumer lock is generated in the ignored fixture directory and must match
the root Core revision in both aggregate and individual modes.

For normal development and CI:

```bash
env -u INNONETWORK_LOCAL_PATH bash Scripts/check_innonetwork_dependency.sh
env -u INNONETWORK_LOCAL_PATH bash Scripts/run_local_release_preflight.sh --quick
```

At an integration milestone, run the full preflight with `--full`; it includes
bounded HLS fixtures, supported AVPlayer and audio runtime probes, Apple HLS
conformance, and five SDK builds. Run macro-first aggregate and individual
consumers in Debug and Release. The full contract requires Xcode 27 / Swift 6.4;
the separate Xcode 26 / Swift 6.2 lane must also remain green.

Core publication does not publish Stream. Stream 1.0.0 and the new APIs remain
Draft, and a clean tagged Stream consumer remains a release gate. Dedicated
FairPlay service, locked-device restoration and production CDN acceptance still
require the application owner's environment.

## Historical branch evidence

The earlier Core branch `codex/core-stream-followup` and locked revision
`91b4b417ca134d0f837f8e000846cd0478e7d439` were reviewed in Core PR #141, stacked
on PR #132. Those historical checks are retained in
[Core branch validation](CORE_BRANCH_VALIDATION_2026_10_02.md). They do not certify
the published 6.1.0 graph. The explicit `--development` tooling option remains
available for reviewed branch work, but active CI uses the published-only gate.
