#!/usr/bin/env bash
# Compile the four public catalogs; warnings remain failures.
# --skip-build is only for callers that just passed the public API graph gate.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
dependency_arguments=()
skip_build=0
for argument in "$@"; do
  case "$argument" in
    --development) dependency_arguments=(--development) ;;
    --skip-build) skip_build=1 ;;
    *) echo "Usage: $0 [--development] [--skip-build]" >&2; exit 64 ;;
  esac
done
if (( ! skip_build )); then
  bash Scripts/check_public_api_contract.sh ${dependency_arguments[@]+"${dependency_arguments[@]}"}
fi
scratch_path="$(python3 Scripts/swiftpm_scratch_path.py "$repo_root")"
graphs="$scratch_path/out/symbolgraph"
[[ -d "$graphs" ]] || { echo "docc-contract: generate current symbol graphs first" >&2; exit 1; }
mkdir -p .build/docc-contract
run_root="$(mktemp -d "$repo_root/.build/docc-contract/run.XXXXXX")"
dependencies=()
for module in InnoNetworkHLS InnoNetworkHLSLive InnoNetworkHLSAVFoundation InnoNetworkHLSAudio; do
  mkdir -p "$run_root/$module-symbols"
  cp "$graphs/$module.symbols.json" "$run_root/$module-symbols/"
  # Preserve extension graphs when the toolchain emits them.
  for graph in "$graphs/$module@"*.symbols.json; do
    [[ -f "$graph" ]] || continue
    cp "$graph" "$run_root/$module-symbols/"
  done
  xcrun docc convert "Sources/$module/$module.docc" \
    --additional-symbol-graph-dir "$run_root/$module-symbols" \
    --fallback-display-name "$module" \
    --fallback-bundle-identifier "com.innosquad.$module" \
    --output-path "$run_root/$module.doccarchive" \
    --enable-experimental-external-link-support \
    ${dependencies[@]+"${dependencies[@]}"} \
    --warnings-as-errors
  dependencies+=(--dependency "$run_root/$module.doccarchive")
done
echo "docc-contract: OK (4 catalogs; archives: $run_root)"
