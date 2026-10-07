#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/innostream-release-candidate.XXXXXX")"
cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

git -C "$scratch" init --quiet
git -C "$scratch" config user.name "InnoStream Tests"
git -C "$scratch" config user.email "tests@example.invalid"
mkdir -p "$scratch/Scripts" "$scratch/docs/releases"
cp "$repo_root/Scripts/validate_docs_release_state.sh" "$scratch/Scripts/"
cp "$repo_root/Scripts/validate_release_candidate.sh" "$scratch/Scripts/"
python3 "$repo_root/Scripts/tests/make_release_state_fixture.py" "$scratch" draft
git -C "$scratch" add .
git -C "$scratch" commit --quiet -m fixture
head="$(git -C "$scratch" rev-parse HEAD)"

RELEASE_CANDIDATE_REF="$head" \
RELEASE_MAIN_REF="$head" \
RELEASE_FETCH_MAIN=0 \
  bash "$scratch/Scripts/validate_release_candidate.sh"

if RELEASE_CANDIDATE_REF="$head" \
  RELEASE_MAIN_REF="$head^" \
  RELEASE_FETCH_MAIN=0 \
  bash "$scratch/Scripts/validate_release_candidate.sh" >/dev/null 2>&1; then
  echo "release-candidate test: off-main candidate unexpectedly passed" >&2
  exit 1
fi

echo "release-candidate tests: OK"
