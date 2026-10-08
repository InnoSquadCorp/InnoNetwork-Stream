# Security Policy

## Reporting a Vulnerability

Use the following channels in order of preference. Do **not** open a
public issue, post on a discussion thread, or share details in a pull
request before the maintainers have acknowledged the report.

1. **Preferred — GitHub Private Vulnerability Reporting (GHSA).**
   Open a private advisory at
   <https://github.com/InnoSquadCorp/InnoNetwork-Stream/security/advisories/new>.
   This routes directly to the maintainers and creates a tracking
   advisory that we can publish alongside the fix.
2. **Fallback — direct contact.** If GHSA reporting is unavailable or
   you cannot complete it, email the maintainer listed as the project's
   primary CODEOWNER. Mark the subject line with `[SECURITY]` so the
   message is triaged ahead of routine issues.

Whichever channel you use, please include:

- affected module and version (for example `InnoNetworkHLS @ 6.1.1`, or `main`
  plus the tested commit revision for an unreleased fix)
- reproduction steps (minimal failing case if possible)
- expected impact and threat model (confidentiality / integrity /
  availability, attacker preconditions)
- proof-of-concept, logs, or stack traces if available
- whether you intend to request a CVE or have a coordinated-disclosure
  timeline you would like us to honor

## Supported Versions

- No stable InnoNetwork-Stream tag exists yet. Reports against `main` are assessed as
  prerelease findings.
- After publication, the latest `6.x` minor is the actively supported line.
- HLS code previously published by InnoNetwork follows InnoNetwork's support
  policy until applications migrate to InnoNetwork-Stream.

## Disclosure

- We will validate the report, assess impact, and coordinate a fix before public disclosure.
- Release notes will identify security-relevant fixes when it is safe to do so.

## Verifying release artifacts

The release workflow publishes a source archive generated from the annotated
tag and a `SHA256SUMS` file. Verify both the tag and checksum before consuming
an archive outside SwiftPM:

```bash
version="6.1.1"
shasum -a 256 -c SHA256SUMS
git verify-tag "$version"
```

`git verify-tag` succeeds only when the maintainer has attached a verifiable
signature to the annotated tag. Until signed tags are operationally enabled,
the GitHub Release, annotated tag object, exact commit, and workflow checksum
must be reviewed together; a checksum alone does not establish publisher
identity.
