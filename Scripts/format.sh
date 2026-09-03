#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mode="format"
if [[ "${1:-}" == "--lint" ]]; then
  mode="lint"
elif [[ $# -gt 0 ]]; then
  echo "Usage: bash Scripts/format.sh [--lint]" >&2
  exit 64
fi

swift_files=()
while IFS= read -r file; do
  swift_files+=("$file")
done < <(
  find Sources Tests -type f -name '*.swift' \
    ! -path '*/.build/*' \
    ! -path '*/.swiftpm/*' \
    | sort
)

if [[ ${#swift_files[@]} -eq 0 ]]; then
  echo "swift-format: no Swift files found"
  exit 0
fi

if [[ "$mode" == "lint" ]]; then
  xcrun swift-format lint \
    --strict \
    --configuration .swift-format \
    "${swift_files[@]}"
  echo "swift-format: OK (${#swift_files[@]} files)"
else
  xcrun swift-format format \
    --in-place \
    --configuration .swift-format \
    "${swift_files[@]}"
  echo "swift-format: applied (${#swift_files[@]} files)"
fi
