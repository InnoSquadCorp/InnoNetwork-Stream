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
