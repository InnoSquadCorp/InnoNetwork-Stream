#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
check() {
  actual="$(printf '%s\n' "$1" | bash Scripts/run_affected_tests.sh --changed-paths-stdin --dry-run)"
  [[ "$actual" == *"selection=$2 consumer=$3"* ]] || { echo "affected selection failed: $actual" >&2; exit 1; }
}
check Sources/InnoNetworkHLSAudio/Audio.swift InnoNetworkHLSAudioTests 0
check Sources/InnoNetworkHLSAVFoundation/Native.swift InnoNetworkHLSAVFoundationTests 0
check Sources/InnoNetworkHLSLive/Live.swift 'InnoNetworkHLSLiveTests|InnoNetworkHLSAVFoundationTests' 0
check Sources/InnoNetworkStreamMacros/Macro.swift 'InnoNetworkStreamMacroTests|InnoNetworkHLSTests|InnoNetworkHLSLiveTests|InnoNetworkHLSAVFoundationTests' 1
check Sources/InnoNetworkHLS/Parser.swift full 0
check Package.resolved full 1
check docs/Example.md none 1
check Sources/Unknown/New.swift full 0
echo "affected-tests-fixtures: OK (reverse dependencies and fail-closed unknown paths)"
