#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/innostream-network-lock.XXXXXX")"
cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

cp "$repo_root/Package.swift" "$repo_root/Package.resolved" "$scratch/"
ln -s "$repo_root/Sources" "$scratch/Sources"
ln -s "$repo_root/Tests" "$scratch/Tests"
gate="$repo_root/Scripts/check_innonetwork_dependency.sh"

# Populate SwiftPM's workspace before testing stale or inconsistent lock data.
env -u INNONETWORK_LOCAL_PATH bash "$gate" "$scratch"

jq '.pins |= map(select(.identity != "innonetwork"))' \
  "$repo_root/Package.resolved" > "$scratch/Package.resolved"
if env -u INNONETWORK_LOCAL_PATH bash "$gate" "$scratch" \
  > "$scratch/missing-pin.log" 2>&1; then
  echo "dependency test: missing remote pin unexpectedly passed" >&2
  exit 1
fi
grep -Fq "lock must contain one published InnoNetwork 6 version and revision" \
  "$scratch/missing-pin.log"

jq '(.pins[] | select(.identity == "innonetwork") | .state.revision) = "0000000000000000000000000000000000000000"' \
  "$repo_root/Package.resolved" > "$scratch/Package.resolved"
if env -u INNONETWORK_LOCAL_PATH bash "$gate" "$scratch" \
  > "$scratch/wrong-revision.log" 2>&1; then
  echo "dependency test: mismatched revision unexpectedly passed" >&2
  exit 1
fi

jq '(.pins[] | select(.identity == "swift-http-types") | .state.revision) = "0000000000000000000000000000000000000000"' \
  "$repo_root/Package.resolved" > "$scratch/Package.resolved"
if env -u INNONETWORK_LOCAL_PATH bash "$gate" "$scratch" \
  > "$scratch/wrong-transitive-revision.log" 2>&1; then
  echo "dependency test: mismatched transitive revision unexpectedly passed" >&2
  exit 1
fi

cp "$repo_root/Package.resolved" "$scratch/Package.resolved"
if INNONETWORK_LOCAL_PATH="$repo_root" bash "$gate" "$scratch" \
  > "$scratch/local-override.log" 2>&1; then
  echo "dependency test: local override unexpectedly passed" >&2
  exit 1
fi
grep -Fq "unset INNONETWORK_LOCAL_PATH" "$scratch/local-override.log"

env -u INNONETWORK_LOCAL_PATH bash "$gate" "$scratch"
echo "innonetwork-dependency tests: OK (cached workspace, missing pin, direct/transitive revision mismatch, local override, restored lock)"
