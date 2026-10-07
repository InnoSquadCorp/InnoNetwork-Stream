# InnoNetwork 6.0.0 compatibility

Validation date: 2026-09-30 (Asia/Seoul)

This is the historical published-6.0 compatibility record. Current development
pins published Core 6.1.0 and its exact tag revision; see
[Core development](CORE_DEVELOPMENT.md). The results below do not certify that
published 6.1.0 graph or authorize Stream publication.

InnoNetwork-Stream's `1.0.0` draft consumes the published InnoNetwork `6.0.0` tag at
`9d8053d5f921ebf5c38cc2f816efe90c7db4a450`. The manifest continues to admit
the InnoNetwork 6 major line. `Package.resolved` records the release revision
and retains the five previously selected transitive dependency versions.

At the original compatibility baseline, the four HLS products, deployment floors, and 1,867 public declarations were
unchanged. The existing bounded HTTP transfer, retry executor, request context,
URL admission, cancellation, and observability integrations compile and pass
their tests against the published dependency.

## Dependency validation

CI and CodeQL resolve the checked-in remote lock and no longer check out
InnoNetwork `main` as a local package. SwiftPM builds and API extraction use
`--force-resolved-versions`. Release preflight rejects any
`INNONETWORK_LOCAL_PATH` override, resolves before building, and checks the lock
again after completing its gates.

The dependency gate also checks every active remote dependency's version and
revision against the resolved graph and checkout. An isolated cached-workspace
reproducer showed
that SwiftPM 6.4's `--force-resolved-versions resolve` alone could accept the
old lock with its InnoNetwork pin missing. The explicit gate rejects that
case, direct or transitive revision mismatches, and a local override; the
restored lock passes. Unused transitive pins may remain in the lock.

Joint-development builds may still select `INNONETWORK_LOCAL_PATH` explicitly
when running `swift test`. Unset it before validating the released graph.

```bash
env -u INNONETWORK_LOCAL_PATH bash Scripts/check_innonetwork_dependency.sh
env -u INNONETWORK_LOCAL_PATH bash Scripts/run_local_release_preflight.sh --quick
```

## Original compatibility evidence (before macro-first redesign)

Toolchain: Xcode 27.0 / Swift 6.4 on macOS 27.0.1.

| Check | Result |
| --- | --- |
| Remote InnoNetwork pin | Exact `6.0.0` release revision in root and separate consumer |
| Full Swift tests | 587 registered: 579 ordinary passes, six runtime-fixture skips, two Audio fixture cancellations |
| Public API | 1,867 declarations match all four checked symbol contracts |
| Supported-runtime smoke | Six AVPlayer/offline/DVR integration tests passed with loopback fixtures; decoded-audio and audio-mix paths also passed |
| Apple HLS tools | Three playlists passed Media Stream Validator and HLS Report |
| macOS | All four products built; full tests and external consumer executed |
| iOS | All four targets built for arm64 simulator, deployment floor iOS 16 |
| tvOS | All four targets built for arm64, deployment floor tvOS 16 |
| watchOS | All four targets built for arm64_32, deployment floor watchOS 9 |
| visionOS | All four targets built for arm64, deployment floor visionOS 1 |
| External consumer | Four products imported; a public playlist request passed through InnoNetwork bounded transfer |
| Operational contracts | Dependency and release-script fixtures, Swift formatting and actionlint passed; local override rejected before build |

The six skips and two Audio fixture cancellations in the general suite were exercised separately
by `Scripts/run_hls_runtime_smoke.sh` using the local HLS fixture server.
Apple-tool reports and logs are retained under
`.build/innonetwork-6-compatibility/` in the validation checkout.

Later macro-first changes have separate fresh validation in
[the redesign execution record](MACRO_FIRST_REDESIGN.md). The original platform
builds above do not validate the added macro target or new operation contracts.

## Remaining publication evidence

These results validate the local streaming source with a published InnoNetwork
dependency, before the package rename. InnoNetwork-Stream `1.0.0` remains
unreleased. During the original validation, the checkout had no `origin`; neither
`InnoSquadCorp/InnoStream` nor `InnoSquadCorp/InnoNetwork-Stream` was accessible
to the company GitHub account during validation. The
[package naming record](PACKAGE_NAMING.md) separates the post-rename evidence.
The canonical public repository was subsequently created and connected as
`origin`; this does not replace the missing remote CI or release evidence.

Xcode 26 was unavailable locally. The configured remote Xcode matrix, CodeQL,
protected main and final release workflow still need execution in the canonical
repository. A clean consumer using both public tags follows InnoNetwork-Stream's
publication. Live FairPlay license-server and real-device validation require
the application's acceptance environment.
