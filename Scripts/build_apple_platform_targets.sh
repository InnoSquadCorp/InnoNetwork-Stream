#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <runtime> <sdk> <target-triple> [scratch-path]" >&2
  exit 64
fi

runtime="$1"
sdk="$2"
target_triple="$3"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_path="${4:-$repo_root/.build/platform-$runtime}"

case "$runtime:$sdk:$target_triple" in
  'macOS:macosx:arm64-apple-macos14.0'|\
  'iOS:iphonesimulator:arm64-apple-ios16.0-simulator'|\
  'tvOS:appletvos:arm64-apple-tvos16.0'|\
  'watchOS:watchos:arm64_32-apple-watchos9.0'|\
  'visionOS:xros:arm64-apple-xros1.0') ;;
  *)
    echo "Unsupported Apple build tuple: $runtime / $sdk / $target_triple" >&2
    exit 64
    ;;
esac

command -v jq >/dev/null 2>&1 \
  || { echo "jq is required to discover library targets" >&2; exit 69; }
bash "$repo_root/Scripts/check_innonetwork_dependency.sh"
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

targets=()
while IFS= read -r target; do
  targets+=("$target")
done < <(
  bash "$repo_root/Scripts/swiftpm.sh" package --package-path "$repo_root" dump-package \
    | jq -r '.products[] | select(.type.library != null) | .targets[]' \
    | sort -u
)

for target in "${targets[@]}"; do
  bash "$repo_root/Scripts/swiftpm.sh" build \
    --package-path "$repo_root" \
    --force-resolved-versions \
    --scratch-path "$scratch_path" \
    --triple "$target_triple" \
    --sdk "$sdk_path" \
    --target "$target"
done

echo "apple-platform-build: OK ($runtime, ${#targets[@]} targets)"
