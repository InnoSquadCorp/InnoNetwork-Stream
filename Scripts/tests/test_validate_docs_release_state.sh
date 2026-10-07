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
