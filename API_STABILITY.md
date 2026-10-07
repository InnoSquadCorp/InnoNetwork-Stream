# API Stability (1.0 Draft)

InnoNetwork-Stream preserves the HLS product and module names that previously shipped
from InnoNetwork. No `1.0.0` tag exists yet, so `main` is a development
snapshot rather than a released dependency.

## Stable package boundary

The following package-level decisions are intended to become Stable at 1.0.0:

- the `innonetwork-stream` package identity and `InnoNetwork-Stream` display
  name, repository name, and all-in-one library product
- the `InnoNetworkHLS`, `InnoNetworkHLSLive`,
  `InnoNetworkHLSAVFoundation`, and `InnoNetworkHLSAudio` product and module
  names
- Apple-only platform support with iOS 16, macOS 14, tvOS 16, watchOS 9, and
  visionOS 1 minimum deployment targets
- a dependency on the InnoNetwork 6 major line for bounded transport, URL
  admission, retry, trust, and observability contracts

Removing a product, renaming a module, raising a deployment floor, or moving
to a new InnoNetwork major requires an InnoNetwork-Stream major release.

The package was called `InnoStream` before its first release. Local consumers
must change their package path/URL and `package:` argument; the four module
imports remain unchanged. The all-in-one product groups those modules but does
not introduce a hyphenated Swift module or re-export wrapper.

## Provisionally Stable declarations

The initial baseline's 1,867 inherited declarations are Provisionally Stable candidates for the
initial 1.x line. There is no published Stream 1.0 contract yet: the authorized
macro-first redesign may change pre-release APIs with explicit migration
evidence. After stabilization, minor releases may add declarations, add cases
to non-frozen enums, and refine behavior with release notes, but must not
remove or rename public declarations. Consumers that exhaustively switch over
public enums should include `@unknown default`.

The checked snapshots in `Scripts/symbols/*.allowlist` are the source of truth:

| Module | Public declarations |
| --- | ---: |
| `InnoNetworkHLS` | 1,036 |
| `InnoNetworkHLSLive` | 334 |
| `InnoNetworkHLSAVFoundation` | 714 |
| `InnoNetworkHLSAudio` | 65 |
| **Total** | **2,149** |

The 283 new name rows (macro, validated settings, workflow protocol,
download task/observation contracts and pure discriminated documents) are
**Draft**, not automatically promoted
to Provisionally Stable by an allowlist update. Macro expansion/diagnostics,
external Debug/Release consumers, runtime ownership controls and the final
supported-toolchain/platform gates must pass before promotion. See
[the macro-first execution plan](docs/MACRO_FIRST_REDESIGN.md).

The net increase of 282 name rows reflects documented families. One inherited
flat playlist constructor is internal; 1,866 inherited rows remain. Typed
selector overloads share name rows and require the semantic signature gate. The collector
now includes `swift.macro`, so the primary declarative surface is gated too.

`Scripts/check_public_api_contract.sh` regenerates Swift symbol graphs and
checks `public-signatures.tsv` with the approved distinct semantic signatures as well as 2,149
name rows. Signatures include overload USRs, typed declaration fragments,
async/throws, actor attributes, generics, availability and explicit conformance
relationships. Locations/comments do not affect the snapshot. Regenerate only
after intentional semantic review; drift is never automatically accepted.
The nine offline-owner additions expose `start`, bounded independent `events`
and `receipt` observations, explicit cancellation, state and redacted failure
reporting. Releasing the owner cancels unfinished work; cancelling an observer
does not. Existing caller-owned async and legacy stream ownership are unchanged.
The initial snapshot is generated on Xcode 27/Swift 6.4. Xcode 26 parity is an
external gate, not inferred from a declaration count. Fixture controls verify
that removing semantic fields changes the result without source-location noise.

The name-based allowlist also
rejects undeclared additions, removals, and renames. An intentional public API
change must update the owning allowlist, its budget, this document, and the
changelog in the same commit.

## Background restoration pre-release correction

`HLSAssetDownloadSession` adds a main-actor initializer accepting the host
application's ordinary background completion closure before the native session
starts. `init(configuration:)` remains available. The postconstruction
`handleBackgroundSessionCompletion(_:completion:)` method is now main-actor
isolated and accepts UIKit's ordinary escaping completion directly. This is an
intentional pre-release concurrency-contract change; the restoration overload
is Draft. A real `UIApplicationDelegate` fixture is compiled for iOS on both
supported toolchain lanes. The Xcode 27 semantic snapshot generated for
`405c714` was reviewed against these three declarations and checked in;
unrelated signatures are unchanged. Exact-head API and consumer CI must still
pass before this change's validation gate is considered complete.

## Internal and operational surfaces

Package-internal declarations, test fixtures, scripts, workflow layout, and
the concrete implementation behind public protocols are not compatibility
contracts. Release gates may evolve without a major version when their
observable package behavior remains compatible.

## Version pinning

After 1.0.0 is published, applications using Provisionally Stable declarations
should prefer a minor-bound range:

```swift
.package(
    url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git",
    .upToNextMinor(from: "1.0.0")
)
```

Use `exact: "1.0.0"` for reproducible release builds that must not accept a
minor update automatically.
