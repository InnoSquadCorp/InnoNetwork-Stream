#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_tag="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
tag_ref="${RELEASE_TAG_REF:-${GITHUB_REF:-refs/tags/$release_tag}}"
remote="${RELEASE_REMOTE:-origin}"
main_remote_ref="${RELEASE_MAIN_REMOTE_REF:-refs/heads/main}"
main_ref="${RELEASE_MAIN_REF:-refs/remotes/$remote/main}"
fetch_main="${RELEASE_FETCH_MAIN:-1}"

fail() {
  echo "release-ref: $1" >&2
  exit 1
}

numeric_identifier='(0|[1-9][0-9]*)'
prerelease_identifier='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
semver_pattern="^${numeric_identifier}\\.${numeric_identifier}\\.${numeric_identifier}(-${prerelease_identifier}(\\.${prerelease_identifier})*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$"
[[ "$release_tag" =~ $semver_pattern ]] \
  || fail "an unprefixed SemVer 2.0.0 tag is required"

git -C "$repo_root" check-ref-format "$tag_ref" >/dev/null 2>&1 \
  || fail "invalid tag ref: $tag_ref"
git -C "$repo_root" check-ref-format "$main_ref" >/dev/null 2>&1 \
  || fail "invalid main ref: $main_ref"
git -C "$repo_root" check-ref-format "$main_remote_ref" >/dev/null 2>&1 \
  || fail "invalid remote main ref: $main_remote_ref"

if [[ "$fetch_main" == "1" ]]; then
  git -C "$repo_root" fetch --no-tags "$remote" \
    "+$main_remote_ref:$main_ref" \
    || fail "could not refresh canonical main"
elif [[ "$fetch_main" != "0" ]]; then
  fail "RELEASE_FETCH_MAIN must be 0 or 1"
fi

[[ "$(git -C "$repo_root" cat-file -t "$tag_ref" 2>/dev/null || true)" == "tag" ]] \
  || fail "$tag_ref must be an annotated tag"

declared_tag="$(git -C "$repo_root" cat-file -p "$tag_ref" | sed -n 's/^tag //p' | head -n 1)"
[[ "$declared_tag" == "$release_tag" ]] \
  || fail "annotated tag declares $declared_tag, not $release_tag"

tag_commit="$(git -C "$repo_root" rev-parse "${tag_ref}^{commit}")"
main_commit="$(git -C "$repo_root" rev-parse "${main_ref}^{commit}")"
[[ "$tag_commit" == "$main_commit" ]] \
  || fail "tagged commit must exactly match canonical main"

notes="docs/releases/$release_tag.md"
[[ "$(git -C "$repo_root" show "$tag_commit:$notes" 2>/dev/null | sed -n '1p')" == '<!-- release-status: ready -->' ]] \
  || fail "$notes must exist and begin with the ready marker"

if [[ "$release_tag" == "1.0.0" ]]; then
  bash "$repo_root/Scripts/validate_docs_release_state.sh" \
    --expect ready \
    --ref "$tag_commit"
fi

echo "release-ref: OK ($release_tag at $tag_commit)"
