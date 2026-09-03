# API Stability (1.0 Draft)

InnoStream preserves the HLS product and module names that previously shipped
from InnoNetwork. No `1.0.0` tag exists yet, so `main` is a development
snapshot rather than a released dependency.

## Stable package boundary

The following package-level decisions are intended to become Stable at 1.0.0:

- the `InnoStream` package identity
- the `InnoNetworkHLS`, `InnoNetworkHLSLive`,
  `InnoNetworkHLSAVFoundation`, and `InnoNetworkHLSAudio` product and module
  names
- Apple-only platform support with iOS 16, macOS 14, tvOS 16, watchOS 9, and
  visionOS 1 minimum deployment targets
- a dependency on the InnoNetwork 6 major line for bounded transport, URL
  admission, retry, trust, and observability contracts

Removing a product, renaming a module, raising a deployment floor, or moving
to a new InnoNetwork major requires an InnoStream major release.

## Provisionally Stable declarations

All 1,867 public declarations exported by the four modules are Provisionally
Stable for the initial 1.x line. Minor releases may add declarations, add cases
to non-frozen enums, and refine behavior with release notes, but must not
remove or rename public declarations. Consumers that exhaustively switch over
public enums should include `@unknown default`.

The checked snapshots in `Scripts/symbols/*.allowlist` are the source of truth:

| Module | Public declarations |
| --- | ---: |
| `InnoNetworkHLS` | 797 |
| `InnoNetworkHLSLive` | 300 |
| `InnoNetworkHLSAVFoundation` | 705 |
| `InnoNetworkHLSAudio` | 65 |
| **Total** | **1,867** |

`Scripts/check_public_api_contract.sh` regenerates Swift symbol graphs and
rejects undeclared additions, removals, and renames. An intentional public API
change must update the owning allowlist, its budget, this document, and the
changelog in the same commit.

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
    url: "https://github.com/InnoSquadCorp/InnoStream.git",
    .upToNextMinor(from: "1.0.0")
)
```

Use `exact: "1.0.0"` for reproducible release builds that must not accept a
minor update automatically.
