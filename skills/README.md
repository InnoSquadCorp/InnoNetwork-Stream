# Library-owned Stream skill

[`innonetwork-stream`](innonetwork-stream/SKILL.md) is the canonical skill for
InnoNetwork-Stream. This repository owns instructions, references, support data,
public consumer fixtures, validator and license notice. Update them alongside
API changes. The central
[InnoSquad plugin](https://github.com/InnoSquadCorp/innosquad-agent-skills)
collects exact snapshots and owns Codex/Claude catalogs and host evaluations.

Stable support: `>=6.1.0 <6.2.0` (6.1.x patches, excluding prereleases).
The exact baseline is published 6.1.1 at `2af03b24cfc8f11442a3b9ba2fd8adcfe58d8116`,
with exact published Core 6.1.1. Later patches require their own consumer checks.
The helper verifies the official tag before and after the build.

For standalone use, copy the **complete** `innonetwork-stream/` directory to
`.agents/skills/innonetwork-stream` (Codex) or
`.claude/skills/innonetwork-stream` (Claude Code). Compare an existing destination
before replacing it. Automatic discovery is enabled; invoke explicitly with
`$innonetwork-stream` or `/innonetwork-stream`. Installed plugin names are
`$innosquad:innonetwork-stream` and `/innosquad:innonetwork-stream`.

```bash
python3 skills/innonetwork-stream/scripts/validate_consumer.py --scratch-path /tmp/stream-skill-validation
```

The validator needs an Apple Swift development host, Python 3 and remote package
access on a cold cache. It retains logs and evidence externally. See
[validation](validation.md) for actual coverage and remaining boundaries.

## Consumer command diagnostics

The validator parses dependency-graph JSON from stdout only. SwiftPM warnings
are retained in `graph.stderr.log`,
linked by each command's `stderr_log` evidence field. Malformed or empty stdout
and nonzero command exits still fail validation. Other commands retain combined
text logs, including Swift Testing summaries written to stderr.
