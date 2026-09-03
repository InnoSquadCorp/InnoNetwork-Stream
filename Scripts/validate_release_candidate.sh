#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
candidate_ref="${RELEASE_CANDIDATE_REF:-HEAD}"
remote="${RELEASE_REMOTE:-origin}"
main_ref="${RELEASE_MAIN_REF:-refs/remotes/$remote/main}"
fetch_main="${RELEASE_FETCH_MAIN:-1}"

fail() {
  echo "release-candidate: $1" >&2
  exit 1
}

if [[ "$fetch_main" == "1" ]]; then
  git -C "$repo_root" fetch --no-tags "$remote" \
    "+refs/heads/main:$main_ref" \
    || fail "could not refresh canonical main"
elif [[ "$fetch_main" != "0" ]]; then
  fail "RELEASE_FETCH_MAIN must be 0 or 1"
fi

candidate_commit="$(git -C "$repo_root" rev-parse "${candidate_ref}^{commit}")"
main_commit="$(git -C "$repo_root" rev-parse "${main_ref}^{commit}")"
[[ "$candidate_commit" == "$main_commit" ]] \
  || fail "candidate commit must exactly match canonical main"

bash "$repo_root/Scripts/validate_docs_release_state.sh" --ref "$candidate_commit"
echo "release-candidate: OK ($candidate_commit)"
