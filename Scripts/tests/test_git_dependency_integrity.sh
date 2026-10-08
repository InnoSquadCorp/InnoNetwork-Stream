#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/innostream-git-integrity.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
origin="$scratch/fixture-origin"
borrower="$scratch/fixture-borrower"
git init -q "$origin"
printf 'dependency integrity fixture\n' > "$origin/fixture.txt"
git -C "$origin" add fixture.txt
git -C "$origin" -c user.name='Integrity Fixture' -c user.email='fixture@example.invalid' \
  commit -qm 'Create isolated object-store fixture'
git clone --quiet --shared "$origin" "$borrower"
expected="$(git -C "$borrower" rev-parse --verify HEAD)"
alternate="$borrower/.git/objects/info/alternates"
[[ -f "$alternate" ]] || { echo "dependency integrity test: missing fixture alternate" >&2; exit 1; }
# SwiftPM may expose read-only checkout metadata. Simulate that on our own
# disposable fixture; no Core checkout or shared cache permissions are changed.
chmod a-w "$alternate"
before="$(shasum -a 256 "$alternate")"
gate="$repo_root/Scripts/check_git_dependency_integrity.sh"
bash "$gate" "$borrower"
# Relocate only the synthetic store. The read-only alternates file is untouched.
mv "$origin/.git/objects" "$scratch/fixture-objects"
[[ "$(git -C "$borrower" rev-parse --verify HEAD)" == "$expected" ]]
if bash "$gate" "$borrower" > "$scratch/broken-store.log" 2>&1; then
  echo "dependency integrity test: missing borrowed object store passed" >&2
  exit 1
fi
[[ "$(shasum -a 256 "$alternate")" == "$before" ]]
mv "$scratch/fixture-objects" "$origin/.git/objects"
bash "$gate" "$borrower"
[[ "$(shasum -a 256 "$alternate")" == "$before" ]]
echo "git-dependency-integrity tests: OK (read-only metadata, missing store, restored store)"
