# Library-owned Stream skill

[`innonetwork-stream`](innonetwork-stream/SKILL.md) is the canonical skill for
InnoNetwork-Stream. This repository owns instructions, references, support data,
public consumer fixtures, validator and license notice. Update them alongside
API changes. The central
[InnoSquad plugin](https://github.com/InnoSquadCorp/innosquad-agent-skills)
collects exact snapshots and owns Codex/Claude catalogs and host evaluations.

Planned stable support: `>=6.1.0 <6.2.0` (6.1.x patches, excluding prereleases).
The exact baseline is unpublished main `bd50e877644ded1b739f66bdd8fb604908606e4b`,
intended for 6.1.1, with exact published Core 6.1.1. A later tag must be checked
and tested independently; source merge does not establish release qualification.

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
