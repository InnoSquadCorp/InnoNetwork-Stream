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
  RELEASE_FETCH_MAIN=0 RELEASE_VERIFY_REMOTE=0 \
  bash "$scratch/Scripts/validate_release_ref.sh" >/dev/null 2>&1; then
  echo "release-ref test: lightweight tag unexpectedly passed" >&2
  exit 1
fi

git -C "$scratch" tag -a 1.0.0 -m fixture
if RELEASE_TAG=1.0.0 RELEASE_TAG_REF=refs/tags/1.0.0 \
  RELEASE_FETCH_MAIN=0 RELEASE_VERIFY_REMOTE=0 \
  bash "$scratch/Scripts/validate_release_ref.sh" >/dev/null 2>&1; then
  echo "release-ref test: draft release unexpectedly passed" >&2
  exit 1
fi

# A ready annotated tag must bind checkout, canonical main and remote identity.
mkdir -p "$scratch/docs/releases"
printf '%s\n' '<!-- release-status: ready -->' > "$scratch/docs/releases/9.9.9.md"
git -C "$scratch" add docs/releases/9.9.9.md
git -C "$scratch" -c commit.gpgsign=false commit --quiet -m ready
ready="$(git -C "$scratch" rev-parse HEAD)"
git -C "$scratch" -c tag.gpgsign=false tag -a 9.9.9 -m ready
tag_object="$(git -C "$scratch" rev-parse refs/tags/9.9.9)"
git -C "$scratch" update-ref refs/remotes/origin/main "$ready"
git init --bare --quiet "$scratch/remote.git"
git -C "$scratch" remote add origin "$scratch/remote.git"
git -C "$scratch" push --quiet origin refs/tags/9.9.9
verify() {
  RELEASE_TAG=9.9.9 RELEASE_TAG_REF=refs/tags/9.9.9 RELEASE_FETCH_MAIN=0 \
    RELEASE_EXPECTED_SHA="$ready" RELEASE_EXPECTED_TAG_OBJECT="$tag_object" \
    bash "$scratch/Scripts/validate_release_ref.sh"
}
verify >/dev/null
# A matching tag/main cannot validate a different checkout.
git -C "$scratch" checkout --quiet --detach "$commit"
# Restore the current validator in the older checkout for this negative fixture.
cp "$repo_root/Scripts/validate_release_ref.sh" "$scratch/Scripts/"
if verify >/dev/null 2>&1; then echo 'wrong checkout accepted' >&2; exit 1; fi
git -C "$scratch" checkout --quiet --detach --force "$ready"
# A retag to the same commit still changes the validated annotated identity.
git -C "$scratch" -c tag.gpgsign=false tag -f -a 9.9.9 -m changed "$ready" >/dev/null
git -C "$scratch" push --quiet --force origin refs/tags/9.9.9
if verify >/dev/null 2>&1; then echo 'retagged release accepted' >&2; exit 1; fi
# Restore local identity only: remote mismatch must independently fail.
git -C "$scratch" update-ref refs/tags/9.9.9 "$tag_object"
if verify >/dev/null 2>&1; then echo 'remote tag move accepted' >&2; exit 1; fi
git -C "$scratch" push --quiet --force origin refs/tags/9.9.9
verify >/dev/null

echo "release-ref tests: OK"
