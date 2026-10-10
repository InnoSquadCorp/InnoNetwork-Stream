#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/innostream-state-fixtures.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
for state in draft ready; do
  fixture="$scratch/$state"
  python3 "$repo_root/Scripts/tests/make_release_state_fixture.py" "$fixture" "$state"
  git -C "$fixture" init --quiet
  git -C "$fixture" add .
  git -C "$fixture" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --quiet -m "$state"
  bash "$fixture/Scripts/validate_docs_release_state.sh" --expect "$state"
  bash "$fixture/Scripts/validate_docs_release_state.sh" --expect "$state" --ref HEAD
  other=ready; [[ "$state" != ready ]] || other=draft
  if bash "$fixture/Scripts/validate_docs_release_state.sh" --expect "$other" >/dev/null 2>&1; then
    echo 'wrong release state accepted' >&2; exit 1
  fi
  if [[ "$state" == ready ]]; then
    cp "$fixture/README.md" "$scratch/original-readme"
    printf '[Roadmap](docs/ROADMAP.md)\n`6.1.1` is published.\nhttps://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1\n' > "$fixture/README.md"
    bash "$fixture/Scripts/validate_docs_release_state.sh" --expect ready
    sed 's@/tag/6.1.1@/tag/6.1.0@' "$fixture/README.md" > "$scratch/wrong-tag"
    cp "$scratch/wrong-tag" "$fixture/README.md"
    if bash "$fixture/Scripts/validate_docs_release_state.sh" --expect ready >/dev/null 2>&1; then
      echo 'published README with wrong tag accepted' >&2; exit 1
    fi
    sed 's@/tag/6.1.0@/tag/6.1.10@' "$fixture/README.md" > "$scratch/prefix-collision"
    cp "$scratch/prefix-collision" "$fixture/README.md"
    if bash "$fixture/Scripts/validate_docs_release_state.sh" --expect ready >/dev/null 2>&1; then
      echo 'published README with prefix-collision tag accepted' >&2; exit 1
    fi
    cp "$scratch/original-readme" "$fixture/README.md"
  fi
  cp "$fixture/docs/releases/6.1.1.md" "$scratch/original-notes"
  printf '\nStatus: contradictory\n' >> "$fixture/docs/releases/6.1.1.md"
  if bash "$fixture/Scripts/validate_docs_release_state.sh" >/dev/null 2>&1; then
    echo 'contradictory status accepted' >&2; exit 1
  fi
  cp "$scratch/original-notes" "$fixture/docs/releases/6.1.1.md"
  printf '\n<!-- release-status: %s -->\n' "$state" >> "$fixture/docs/releases/6.1.1.md"
  if bash "$fixture/Scripts/validate_docs_release_state.sh" >/dev/null 2>&1; then
    echo 'duplicate marker accepted' >&2; exit 1
  fi
done
# The real checkout may coherently be a candidate or ready; do not pin it to draft.
bash "$repo_root/Scripts/validate_docs_release_state.sh"
echo 'docs release-state tests: OK (isolated draft + ready + negative controls)'
