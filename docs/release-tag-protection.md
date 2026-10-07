# Release identity and tag protection

Release validation binds an existing remote tag to its commit and tag object.
Publication rechecks both identities and the tested checkout immediately before
creating the release. A moved tag, rewritten annotation or different checkout
fails validation. Publish corrected releases with a new version tag.

The repository also needs the active tag ruleset in
[`.github/release-tag-ruleset.json`](../.github/release-tag-ruleset.json).
It blocks updates and deletion of numeric and `v`-prefixed release tags, with no
bypass actors; creation of new tags stays available. This closes the interval
between the final identity check and GitHub release creation. Branch protection
is independent and must remain unchanged.

Repository administrators can inspect existing rulesets with:

```sh
gh api repos/InnoSquadCorp/InnoNetwork-Stream/rulesets
```

If the named ruleset is absent, install the reviewed payload once:

```sh
gh api --method POST repos/InnoSquadCorp/InnoNetwork-Stream/rulesets \
  --input .github/release-tag-ruleset.json
```

Read back `rulesets/ID` and compare `target`, `enforcement`, `conditions`, `rules`
and `bypass_actors` with the committed payload. If it already exists, inspect and
update that ruleset instead of creating a duplicate. Merging this file alone
does not install repository settings. Local Git fixtures exercise tag movement
inside temporary repositories; they do not mutate hosted release tags.
