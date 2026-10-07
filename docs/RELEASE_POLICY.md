# Release Policy

## Versioning

- Public releases follow semantic versioning.
- Product or module removal, deployment-floor increases, and dependency moves
  to a new InnoNetwork major require an InnoNetwork-Stream major release.
- Public declaration removals or renames require a major release.
- Minor releases may add Provisionally Stable declarations or enum cases when
  the changelog documents the migration impact.
- Patch releases are limited to source-compatible fixes and documentation.

## Dependency order

InnoNetwork-Stream 1.0 pins InnoNetwork 6.1.0 exactly. The publication order is therefore:

1. publish and verify InnoNetwork `6.1.0`
2. resolve InnoNetwork-Stream without `INNONETWORK_LOCAL_PATH`
3. publish and verify InnoNetwork-Stream `1.0.0`
4. migrate downstream applications only after both tags are available

Local-path builds are useful integration evidence but cannot replace a clean
remote-tag consumer build.

CI and CodeQL use the checked-in remote dependency lock. Release preflight
requires `INNONETWORK_LOCAL_PATH` to be unset and rejects automatic dependency
resolution or lock changes. Update the lock intentionally when validating a
new supported InnoNetwork release.

`Scripts/check_innonetwork_dependency.sh` verifies the exact InnoNetwork 6.1.0 manifest and approved tag
pin and every active remote dependency's resolved graph and checkout revision. A
cached SwiftPM workspace does not substitute for a valid checked-in pin.

## Release process

1. Update `CHANGELOG.md`, `API_STABILITY.md`, and
   `docs/releases/<version>.md` together.
2. Keep the release note's first line as
   `<!-- release-status: draft -->` until every required gate passes.
3. Run `bash Scripts/run_local_release_preflight.sh --full` on the supported
   Xcode 27 environment with Apple's HLS tools installed.
4. Run the `Release` workflow manually from canonical `main` as a pre-tag
   candidate. Manual dispatch validates but does not publish.
5. Change the release status to `ready` in the same commit that finalizes the
   date and changelog entry.
6. Create an unprefixed annotated SemVer tag from the exact canonical `main`
   commit. Lightweight tags and off-main tags are rejected.
7. Let the tag-triggered workflow repeat validation, build a tagged source
   archive and SHA-256 checksum, and create the GitHub Release.
8. Verify a clean external consumer against the published tags before updating
   production applications.

Live FairPlay acceptance is required only when the release changes FairPlay
behavior and the maintainer has application-owned credentials and entitlement
context. Deterministic FairPlay adapter and workflow tests remain mandatory for
every release.
