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
gate_arguments=()
if jq -e '.pins[] | select(.identity == "innonetwork") | .state.branch != null' \
  "$repo_root/Package.resolved" >/dev/null; then
  gate_arguments=(--development)
  if env -u INNONETWORK_LOCAL_PATH bash "$gate" "$scratch" \
    > "$scratch/release-rejects-branch.log" 2>&1; then
    echo "dependency test: release validation accepted a development branch" >&2
    exit 1
  fi
  grep -Fq "one published InnoNetwork pin" "$scratch/release-rejects-branch.log"
  # Direct API/SDK entry points remain published-only unless explicitly opted in.
  if env -u INNONETWORK_LOCAL_PATH bash "$repo_root/Scripts/check_public_api_contract.sh" \
    > "$scratch/api-rejects-branch.log" 2>&1; then
    echo "dependency test: API release validation accepted a development branch" >&2
    exit 1
  fi
  grep -Fq "one published InnoNetwork pin" "$scratch/api-rejects-branch.log"
  if env -u INNONETWORK_LOCAL_PATH bash "$repo_root/Scripts/build_apple_platform_targets.sh" \
    macOS macosx arm64-apple-macos14.0 \
    > "$scratch/sdk-rejects-branch.log" 2>&1; then
    echo "dependency test: SDK release validation accepted a development branch" >&2
    exit 1
  fi
  grep -Fq "one published InnoNetwork pin" "$scratch/sdk-rejects-branch.log"
fi

# Populate SwiftPM's workspace before testing stale or inconsistent lock data.
env -u INNONETWORK_LOCAL_PATH bash "$gate" ${gate_arguments[@]+"${gate_arguments[@]}"} "$scratch"

jq '.pins |= map(select(.identity != "innonetwork"))' \
  "$repo_root/Package.resolved" > "$scratch/Package.resolved"
if env -u INNONETWORK_LOCAL_PATH bash "$gate" ${gate_arguments[@]+"${gate_arguments[@]}"} "$scratch" \
  > "$scratch/missing-pin.log" 2>&1; then
  echo "dependency test: missing remote pin unexpectedly passed" >&2
  exit 1
fi
grep -Fq "InnoNetwork pin with the expected version/branch and revision" \
  "$scratch/missing-pin.log"

jq '(.pins[] | select(.identity == "innonetwork") | .state.revision) = "0000000000000000000000000000000000000000"' \
  "$repo_root/Package.resolved" > "$scratch/Package.resolved"
if env -u INNONETWORK_LOCAL_PATH bash "$gate" ${gate_arguments[@]+"${gate_arguments[@]}"} "$scratch" \
  > "$scratch/wrong-revision.log" 2>&1; then
  echo "dependency test: mismatched revision unexpectedly passed" >&2
  exit 1
fi

jq '(.pins[] | select(.identity == "swift-http-types") | .state.revision) = "0000000000000000000000000000000000000000"' \
  "$repo_root/Package.resolved" > "$scratch/Package.resolved"
if env -u INNONETWORK_LOCAL_PATH bash "$gate" ${gate_arguments[@]+"${gate_arguments[@]}"} "$scratch" \
  > "$scratch/wrong-transitive-revision.log" 2>&1; then
  echo "dependency test: mismatched transitive revision unexpectedly passed" >&2
  exit 1
fi

cp "$repo_root/Package.resolved" "$scratch/Package.resolved"
# A correct HEAD alone does not prove a relocated alternate object store exists.
dependency_path="$(cd "$scratch" && bash "$repo_root/Scripts/swiftpm.sh" package \
  --force-resolved-versions show-dependencies --format json \
  | jq -r '.dependencies[] | select(.identity == "innonetwork") | .path')"
alternate="$(git -C "$dependency_path" rev-parse --git-path objects/info/alternates)"
[[ "$alternate" == /* ]] || alternate="$dependency_path/$alternate"
[[ -f "$alternate" ]] || { echo "dependency test: expected local SwiftPM alternate" >&2; exit 1; }
cp "$alternate" "$scratch/alternate.before"
printf '%s\n' "$scratch/missing-object-store" > "$alternate"
if env -u INNONETWORK_LOCAL_PATH bash "$gate" ${gate_arguments[@]+"${gate_arguments[@]}"} "$scratch" \
  > "$scratch/broken-alternate.log" 2>&1; then
  echo "dependency test: missing alternate object store unexpectedly passed" >&2
  exit 1
fi
grep -Fq "dependency cache integrity failed" "$scratch/broken-alternate.log"
cp "$scratch/alternate.before" "$alternate"

if INNONETWORK_LOCAL_PATH="$repo_root" bash "$gate" ${gate_arguments[@]+"${gate_arguments[@]}"} "$scratch" \
  > "$scratch/local-override.log" 2>&1; then
  echo "dependency test: local override unexpectedly passed" >&2
  exit 1
fi
grep -Fq "unset INNONETWORK_LOCAL_PATH" "$scratch/local-override.log"

if [[ ${#gate_arguments[@]} -gt 0 ]]; then
  jq '(.pins[] | select(.identity == "innonetwork") | .state.branch) = "main"' \
    "$repo_root/Package.resolved" > "$scratch/Package.resolved"
  if env -u INNONETWORK_LOCAL_PATH bash "$gate" --development "$scratch" \
    > "$scratch/wrong-branch.log" 2>&1; then
    echo "dependency test: an unrelated development branch passed" >&2
    exit 1
  fi
  cp "$repo_root/Package.resolved" "$scratch/Package.resolved"
  sed 's/codex\/core-stream-followup/codex\/unapproved-core/' \
    "$repo_root/Package.swift" > "$scratch/Package.swift"
  if env -u INNONETWORK_LOCAL_PATH bash "$gate" --development "$scratch" \
    > "$scratch/wrong-manifest.log" 2>&1; then
    echo "dependency test: an unrelated manifest branch passed" >&2
    exit 1
  fi
  grep -Fq "manifest does not match" "$scratch/wrong-manifest.log"
  cp "$repo_root/Package.swift" "$scratch/Package.swift"
fi

env -u INNONETWORK_LOCAL_PATH bash "$gate" ${gate_arguments[@]+"${gate_arguments[@]}"} "$scratch"
echo "innonetwork-dependency tests: OK (cached graph, direct/transitive pins, object integrity, local override, branch/manifest contract, publication boundary)"
