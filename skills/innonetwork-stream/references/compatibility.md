# Version and package contract

Checked 2026-10-10: published Stream **6.1.1** points to
`2af03b24cfc8f11442a3b9ba2fd8adcfe58d8116`. The GitHub Release was published on
2026-10-09 UTC. Stable support is `>=6.1.0 <6.2.0`; the exact validated baseline
is 6.1.1, not every patch in that range. No earlier 6.1.0 tag is assumed.

The reproducible fixture pins the release exactly:

```swift
.package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git",
         exact: "6.1.1")
```

For a stable 6.1.x consumer, retain its patch and review that revision's API and
Core constraint. Use `.upToNextMinor(from: "6.1.1")` when the caller wants this
patch line; `from:` alone permits later 6.x minors beyond this support range.
Do not downgrade an existing supported patch to the fixture baseline or apply
this guidance to 6.2+, prereleases, or a different moving branch without review.

The captured Stream manifest requires **exact Core 6.1.1**, tag commit
`44e4ca28c50c03f817231a077c0f3bdfdbc859c8`. A Stream patch support range does
not allow an independent Core 6.1.2 upgrade. Check the selected Stream manifest
first, then resolve and test the allowed pair. `INNONETWORK_LOCAL_PATH` is a
development override and must be unset for this remote evidence.

Select `.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream")`
for the aggregate, or individual products matching the four module names.
SwiftPM identity is `innonetwork-stream`; Swift imports do not use the hyphenated
repository name. Old local `InnoStream` adopters update URL/path and product
package argument; existing module names remain. No old public tag or redirect
is assumed.

Swift tools 6.2, Swift 6 language mode; Stream and Core share SwiftSyntax
604.0.x. Deployment floors: iOS/tvOS 16, macOS 14, watchOS 9, visionOS 1.
Decoded-audio APIs additionally require compiler 6.4/Xcode 27 and OS 27;
individual APIs can have narrower platform availability. Use both compiler and
runtime guards. Xcode plugin trust is separate from API correctness; preserve
normal local trust approval and do not change global trust settings.

## Immutable sources

At the [captured source](https://github.com/InnoSquadCorp/InnoNetwork-Stream/tree/2af03b24cfc8f11442a3b9ba2fd8adcfe58d8116), consult:
`Package.swift`, `README.md`, `docs/MACRO_FIRST_MIGRATION.md`,
`docs/FAILURE_AND_INCIDENT_CONTRACT.md`, `docs/MEDIA_CATALOG.md`,
`docs/DEVICE_ACCEPTANCE.md`, `Sources/` and `Tests/PackageIdentity/`.
These are the provenance for the bundled references. Read the consumer's own
resolved checkout for patch-specific signatures. A package name, version string,
main branch, release notes or passing local fixture does not prove publication.
