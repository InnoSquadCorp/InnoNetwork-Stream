#!/usr/bin/env bash
# Incremental local feedback, not a substitute for complete CI/release gates.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
base=""
dry_run=0
full=0
stdin_paths=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) [[ $# -ge 2 ]] || exit 64; base="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --full) full=1; shift ;;
    --changed-paths-stdin) stdin_paths=1; shift ;;
    *) echo "Usage: $0 --base <commit> [--dry-run] | --full | --changed-paths-stdin [--dry-run]" >&2; exit 64 ;;
  esac
done
if (( full )); then
  paths="Package.swift"
elif (( stdin_paths )); then
  paths="$(</dev/stdin)"
else
  [[ -n "$base" ]] || { echo "affected-tests: explicit baseline required" >&2; exit 64; }
  git rev-parse --verify "${base}^{commit}" >/dev/null
  paths="$(git diff --name-only "$base" --; git ls-files --others --exclude-standard -- Sources Tests Scripts docs .github)"
fi
macro=0; hls=0; live=0; av=0; audio=0; consumer=0
while IFS= read -r path; do
  case "$path" in
    "") ;;
    Package.swift|Package.resolved|Scripts/*|.github/*|.swift-format) full=1; consumer=1 ;;
    Sources/InnoNetworkHLS/*) full=1 ;;
    Sources/InnoNetworkStreamMacros/*) macro=1; hls=1; live=1; av=1; consumer=1 ;;
    Sources/InnoNetworkHLSLive/*) live=1; av=1 ;;
    Sources/InnoNetworkHLSAVFoundation/*) av=1 ;;
    Sources/InnoNetworkHLSAudio/*) audio=1 ;;
    Tests/InnoNetworkStreamMacroTests/*) macro=1 ;;
    Tests/InnoNetworkHLSTests/*) hls=1 ;;
    Tests/InnoNetworkHLSLiveTests/*) live=1 ;;
    Tests/InnoNetworkHLSAVFoundationTests/*) av=1 ;;
    Tests/InnoNetworkHLSAudioTests/*) audio=1 ;;
    Tests/PackageIdentity/*|Tests/FairPlayAcceptance/*|docs/*|README*|API_STABILITY.md|CHANGELOG.md) consumer=1 ;;
    *) full=1 ;;
  esac
done <<< "$paths"
filter=""
if (( full )); then
  selection="full"
else
  targets=()
  (( macro )) && targets+=(InnoNetworkStreamMacroTests)
  (( hls )) && targets+=(InnoNetworkHLSTests)
  (( live )) && targets+=(InnoNetworkHLSLiveTests)
  (( av )) && targets+=(InnoNetworkHLSAVFoundationTests)
  (( audio )) && targets+=(InnoNetworkHLSAudioTests)
  filter="$(IFS='|'; printf '%s' "${targets[*]-}")"
  selection="${filter:-none}"
fi
echo "affected-tests: selection=$selection consumer=$consumer (local feedback only)"
(( dry_run )) && exit 0
if (( full )); then
  xcrun swift test --force-resolved-versions --parallel
elif [[ -n "$filter" ]]; then
  xcrun swift test --force-resolved-versions --filter "$filter"
fi
if (( consumer )); then bash Scripts/tests/test_package_identity.sh; fi
