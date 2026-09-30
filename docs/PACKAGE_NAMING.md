# Package and repository naming

The unreleased `InnoStream` package is now named `InnoNetwork-Stream`.
The canonical public GitHub repository URL is:

```text
https://github.com/InnoSquadCorp/InnoNetwork-Stream.git
```

Its SwiftPM package display name and all-in-one library product are
`InnoNetwork-Stream`. The canonical package identity is `innonetwork-stream`.
The package is independently versioned; its first release remains `1.0.0`
and consumes the published InnoNetwork `6.0.0` dependency.

## Consumer contract

Select all four modules with:

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream")
```

Alternatively, select any of the unchanged individual products with the new
package owner:

```swift
.product(name: "InnoNetworkHLS", package: "InnoNetwork-Stream")
```

Swift source imports `InnoNetworkHLS`, `InnoNetworkHLSLive`,
`InnoNetworkHLSAVFoundation`, and `InnoNetworkHLSAudio` as before. A hyphen is
not valid in a Swift module name, so `import InnoNetwork-Stream` is not an
import contract. There is no re-export wrapper or renamed public declaration.

Local consumers of the former checkout must change its path/URL and their
`package:` argument. The repository directory was moved from `InnoStream` to
`InnoNetwork-Stream`; its Git history, pre-existing generated Xcode project,
and `Derived/` files were preserved. Those generated files were not renamed
or regenerated as part of the package change.

## Validation

`Scripts/tests/test_package_identity.sh` checks the package/product manifest
and builds a real external consumer in both aggregate and individual-product
modes. It also verifies the application-owned FairPlay fixture's package
reference without running credential-dependent live acceptance.

The script is included in CI, release script validation, and local preflight.
Post-rename build/API/test and naming evidence is retained under
`.build/package-rename-evidence/`. Earlier five-platform and HLS-tool evidence
is distinguished in [the dependency compatibility record](INNONETWORK_6_COMPATIBILITY.md).

Original post-rename checks on Xcode 27 / Swift 6.4, 2026-09-30 (before macro-first redesign):

- Both consumer modes built and ran; the resolved local package identity was
  `innonetwork-stream` with display name `InnoNetwork-Stream`.
- Full Swift tests passed: 587 registered, 579 ordinary passes, six runtime
  skips and two Audio fixture cancellations, all eight subsequently exercised
  successfully with loopback HLS fixtures.
- Four module symbol contracts remained unchanged at 1,867 declarations.
- Runtime smoke and three Apple HLS playlist conformance reports passed.
- Package/dependency/release-script fixtures, formatting, workflow lint, and
  quick release preflight passed. The InnoNetwork 6.0.0 pin and all original
  transitive pins remained unchanged through the rename.
- Xcode discovered `InnoNetwork-Stream` and `InnoNetwork-Stream-Package`
  schemes in an isolated package view without the pre-existing generated
  Xcode project.

A subsequent isolated Xcode macOS build stopped at InnoNetwork's macro trust
approval (`InnoNetworkMacros must be enabled before it can be used`). The same
command with the byte-identical original manifest at `79489f4` stopped at the
same approval check. This is not a successful Xcode build or evidence of a
rename-specific failure. Both logs are retained; no macro validation bypass
or global Xcode trust setting was applied.

Remote CI and the Xcode 26 matrix remain unexecuted. This local naming
validation is not publication or live FairPlay acceptance evidence.

## Remote publication boundary

During the local rename on 2026-09-30, this checkout had no Git remote and the
company account could not access either candidate repository. Following the
user's separate authorization, `InnoSquadCorp/InnoNetwork-Stream` was created
as a public repository and connected as `origin`. The existing MIT license
and `Copyright (c) 2026 InnoSquad` notice were preserved.

Repository creation and source publication do not create a stable `1.0.0`
tag or Release. That release remains Draft, pending the documented remote
CI/platform gates. No old `InnoStream` repository redirect is assumed.
