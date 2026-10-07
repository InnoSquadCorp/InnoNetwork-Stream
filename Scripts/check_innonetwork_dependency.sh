#!/usr/bin/env bash
set -euo pipefail

dependency_mode="published"
if [[ "${1:-}" == "--development" ]]; then
  dependency_mode="development"
  shift
fi
if [[ $# -gt 1 || "${1:-}" == --* ]]; then
  echo "Usage: bash Scripts/check_innonetwork_dependency.sh [--development] [package-path]" >&2
  exit 64
fi

package_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$package_root"

fail() {
  echo "innonetwork-dependency: $1" >&2
  exit 1
}

[[ "${INNONETWORK_LOCAL_PATH+x}" != "x" ]] \
  || fail "unset INNONETWORK_LOCAL_PATH to validate the remote dependency"
command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f Package.resolved ]] || fail "missing Package.resolved"

resolved_before="$(shasum -a 256 Package.resolved)"
network_url="https://github.com/InnoSquadCorp/InnoNetwork.git"
development_branch="codex/core-stream-followup"
published_version="6.1.0"
published_revision="79ff9f535a0a15ad8b52ce49cb5a4b1ea1dfec16"

jq -e --arg url "$network_url" --arg mode "$dependency_mode" --arg branch "$development_branch" \
  --arg version "$published_version" --arg revision "$published_revision" '
  [.pins[] | select(.identity == "innonetwork")] as $pins |
  ($pins | length) == 1 and
  ($pins[0] | .kind == "remoteSourceControl" and .location == $url and
    (.state.revision | type == "string" and test("^[0-9a-f]{40}$")) and
    (if $mode == "development" then
      .state.branch == $branch and .state.version == null
    else
      .state.version == $version and .state.revision == $revision and
      .state.branch == null
    end))
' Package.resolved >/dev/null \
  || fail "lock must contain one $dependency_mode InnoNetwork pin with the expected version/branch and revision"

network_version="$(jq -r '.pins[] | select(.identity == "innonetwork") | .state.version // "unspecified"' Package.resolved)"
network_revision="$(jq -r '.pins[] | select(.identity == "innonetwork") | .state.revision' Package.resolved)"
manifest="$(bash "$script_root/swiftpm.sh" package dump-package)"
printf '%s\n' "$manifest" | jq -e --arg mode "$dependency_mode" --arg branch "$development_branch" \
  --arg version "$published_version" '
  [.dependencies[].sourceControl[]? | select(.identity == "innonetwork")] as $nodes |
  ($nodes | length) == 1 and
  (if $mode == "development" then $nodes[0].requirement.branch == [$branch]
   else $nodes[0].requirement.exact == [$version] and
     $nodes[0].requirement.branch == null and $nodes[0].requirement.revision == null end)
' >/dev/null || fail "manifest does not match the $dependency_mode dependency contract"
graph="$(bash "$script_root/swiftpm.sh" package --force-resolved-versions show-dependencies --format json)"

printf '%s\n' "$graph" | jq -e \
  --arg url "$network_url" --arg version "$network_version" '
  [.dependencies[] | select(.identity == "innonetwork")] as $nodes |
  ($nodes | length) == 1 and
  ($nodes[0] | .url == $url and .version == $version and
    (.path | type == "string" and length > 0))
' >/dev/null || fail "resolved graph does not match the remote lock"

# SwiftPM can retain a cached graph despite stale lock data. Check every active
# source-control dependency, while allowing unused pins to remain in the lock.
active_nodes="$(printf '%s\n' "$graph" | jq -c '
  [.dependencies[] | .. | objects | select(has("identity") and has("version"))]
  | unique_by([.identity, .url, .version, .path])[]
')"
while IFS= read -r node; do
  identity="$(printf '%s\n' "$node" | jq -r '.identity')"
  dependency_url="$(printf '%s\n' "$node" | jq -r '.url')"
  dependency_version="$(printf '%s\n' "$node" | jq -r '.version')"
  dependency_path="$(printf '%s\n' "$node" | jq -r '.path')"
  jq -e --arg identity "$identity" --arg url "$dependency_url" \
    --arg version "$dependency_version" --arg mode "$dependency_mode" --arg branch "$development_branch" '
    [.pins[] | select(.identity == $identity)] as $pins |
    ($pins | length) == 1 and
    ($pins[0] | .kind == "remoteSourceControl" and .location == $url and
      (.state.revision | type == "string" and test("^[0-9a-f]{40}$")) and
      (if $mode == "development" and $identity == "innonetwork" then
        .state.branch == $branch and .state.version == null and $version == "unspecified"
      else .state.version == $version and .state.branch == null and $version != "unspecified" end))
  ' Package.resolved >/dev/null \
    || fail "$identity resolved graph does not match the remote lock"
  locked_revision="$(jq -r --arg identity "$identity" '.pins[] | select(.identity == $identity) | .state.revision' Package.resolved)"
  observed_revision="$(git -C "$dependency_path" rev-parse --verify HEAD)"
  [[ "$observed_revision" == "$locked_revision" ]] \
    || fail "$identity dependency checkout does not match the locked revision"
  git -C "$dependency_path" fsck --no-reflogs --connectivity-only --no-dangling >/dev/null \
    || fail "$identity dependency cache integrity failed; preserve it and use a fresh scoped scratch path"
done <<< "$active_nodes"
[[ "$(shasum -a 256 Package.resolved)" == "$resolved_before" ]] \
  || fail "dependency lock drifted while resolving"

echo "innonetwork-dependency: OK ($dependency_mode / $network_version / $network_revision)"
