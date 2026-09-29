# Changelog

## Unreleased

These changes have not been tagged. `1.0.0` remains a draft until the release
state, remote dependency, Apple-platform, and HLS conformance gates pass.

- Split the four HLS products from InnoNetwork 6 into an independently
  versioned package while preserving their module names.
- Depend on InnoNetwork's public bounded-transfer and retry-execution
  contracts instead of package-internal transport coordinators.
- Add an explicit public API snapshot, release-state contract, CI workflow,
  and tag validation process for independent publication.
- Resolve the published InnoNetwork `6.0.0` release in the dependency lock,
  CI, CodeQL, and local release preflight. Preserve the existing transitive
  dependency versions and reject local-path overrides during release preflight.
- Check the published dependency's locked version and revision against the
  resolved graph and checkout, including when SwiftPM reuses cached state.
- Rename the unreleased repository and package to `InnoNetwork-Stream` and
  provide a matching all-in-one library product. Preserve the four existing
  individual products and Swift module imports.
- Establish the public `InnoSquadCorp/InnoNetwork-Stream` repository under
  the existing MIT license, without creating a stable release tag.
