#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/innostream-release-ref.XXXXXX")"
cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

git -C "$scratch" init --quiet
git -C "$scratch" config user.name "InnoStream Tests"
git -C "$scratch" config user.email "tests@example.invalid"
mkdir -p "$scratch/Scripts" "$scratch/docs/releases"
cp "$repo_root/Scripts/validate_docs_release_state.sh" "$scratch/Scripts/"
cp "$repo_root/Scripts/validate_release_ref.sh" "$scratch/Scripts/"
cp "$repo_root/API_STABILITY.md" "$scratch/"
cp "$repo_root/README.md" "$scratch/"
cp "$repo_root/CHANGELOG.md" "$scratch/"
cp "$repo_root/SECURITY.md" "$scratch/"
cp "$repo_root/docs/ROADMAP.md" "$scratch/docs/"
cp "$repo_root/docs/releases/1.0.0.md" "$scratch/docs/releases/"
git -C "$scratch" add .
git -C "$scratch" commit --quiet -m fixture
commit="$(git -C "$scratch" rev-parse HEAD)"
git -C "$scratch" update-ref refs/remotes/origin/main "$commit"

git -C "$scratch" tag draft-lightweight
if RELEASE_TAG=1.0.0 RELEASE_TAG_REF=refs/tags/draft-lightweight \
  RELEASE_FETCH_MAIN=0 \
  bash "$scratch/Scripts/validate_release_ref.sh" >/dev/null 2>&1; then
  echo "release-ref test: lightweight tag unexpectedly passed" >&2
  exit 1
fi

git -C "$scratch" tag -a 1.0.0 -m fixture
if RELEASE_TAG=1.0.0 RELEASE_TAG_REF=refs/tags/1.0.0 \
  RELEASE_FETCH_MAIN=0 \
  bash "$scratch/Scripts/validate_release_ref.sh" >/dev/null 2>&1; then
  echo "release-ref test: draft release unexpectedly passed" >&2
  exit 1
fi

echo "release-ref tests: OK"
