#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mode="quick"
dependency_arguments=()
preflight_label="local-release-preflight"
apple_evidence="${APPLE_HLS_EVIDENCE_DIRECTORY:-ReleaseEvidence/apple-hls}"
for argument in "$@"; do
case "$argument" in
  --development) dependency_arguments=(--development); preflight_label="local-development-preflight" ;;
  --quick) mode="quick" ;;
  --full) mode="full" ;;
  *)
    echo "Usage: bash Scripts/run_local_release_preflight.sh [--quick|--full] [--development]" >&2
    exit 64
    ;;
esac
done

if [[ "${INNONETWORK_LOCAL_PATH+x}" == "x" ]]; then
  echo "$preflight_label: unset INNONETWORK_LOCAL_PATH to validate the remote dependency" >&2
  exit 64
fi

swift_version="$(xcrun swift --version | sed -nE 's/^Apple Swift version ([0-9]+)\.([0-9]+).*/\1.\2/p' | head -n 1)"
swift_major="${swift_version%%.*}"
swift_minor="${swift_version##*.}"
if [[ -z "$swift_version" ]] \
  || (( swift_major < 6 || (swift_major == 6 && swift_minor < 4) )); then
  echo "local-release-preflight: complete API/audio/HLS contracts require Xcode 27 / Swift 6.4; use swift test for the Swift 6.2 core lane" >&2
  exit 69
fi

# Fail early on missing/unapproved local evidence before expensive release builds.
if [[ "$mode" == "full" ]]; then
  python3 Scripts/apple_hls_evidence.py verify --bundle "$apple_evidence"
fi

resolved_before="$(shasum -a 256 Package.resolved)"
bash Scripts/check_innonetwork_dependency.sh ${dependency_arguments[@]+"${dependency_arguments[@]}"}
[[ "$(shasum -a 256 Package.resolved)" == "$resolved_before" ]] \
  || { echo "local-release-preflight: dependency lock drifted" >&2; exit 1; }

bash Scripts/format.sh --lint
bash Scripts/validate_docs_release_state.sh
ruby Scripts/check_codeql_contract.rb
ruby Scripts/tests/test_codeql_contract.rb
python3 Scripts/tests/test_hls_fixture_readiness.py
python3 Scripts/tests/test_swiftpm_scratch.py
bash Scripts/check_public_api_contract.sh ${dependency_arguments[@]+"${dependency_arguments[@]}"}
bash Scripts/check_docc.sh --skip-build
bash Scripts/tests/test_package_identity.sh
sdk_smoke="$(mktemp -d "${TMPDIR:-/tmp}/stream-sdk-smoke.XXXXXX")"
trap 'rm -rf "$sdk_smoke"' EXIT
python3 Scripts/apple_hls_evidence.py smoke --bundle "$sdk_smoke/bundle"
python3 -B -m unittest discover -s Scripts/tests -p "test_*hls_evidence*.py" -v
bash Scripts/tests/test_run_affected_tests.sh
python3 Scripts/tests/test_public_signatures.py
bash -n Scripts/*.sh
python3 -m py_compile Scripts/*.py
bash Scripts/swiftpm.sh test --force-resolved-versions --parallel

if [[ "$mode" == "full" ]]; then
  bash Scripts/run_hls_quality_gates.sh \
    --skip-build \
    --apple-evidence "$apple_evidence" \
    --require-runtime-smoke \
    --apple-report-root .build/local-release-preflight/apple-hls

  # An app-owned/generated .xcodeproj can shadow SwiftPM's implicit Xcode
  # package scheme. Compile exact package library targets against each SDK
  # without modifying that project or pretending to validate an app/signing.
  bash Scripts/build_apple_platform_targets.sh \
    ${dependency_arguments[@]+"${dependency_arguments[@]}"} \
    macOS macosx arm64-apple-macos14.0 \
    .build/local-release-preflight/swiftpm-macos
  bash Scripts/build_apple_platform_targets.sh \
    ${dependency_arguments[@]+"${dependency_arguments[@]}"} \
    iOS iphonesimulator arm64-apple-ios16.0-simulator \
    .build/local-release-preflight/swiftpm-ios-simulator
  bash Scripts/build_apple_platform_targets.sh \
    ${dependency_arguments[@]+"${dependency_arguments[@]}"} \
    tvOS appletvos arm64-apple-tvos16.0 \
    .build/local-release-preflight/tvos
  bash Scripts/build_apple_platform_targets.sh \
    ${dependency_arguments[@]+"${dependency_arguments[@]}"} \
    watchOS watchos arm64_32-apple-watchos9.0 \
    .build/local-release-preflight/watchos
  bash Scripts/build_apple_platform_targets.sh \
    ${dependency_arguments[@]+"${dependency_arguments[@]}"} \
    visionOS xros arm64-apple-xros1.0 \
    .build/local-release-preflight/visionos
else
  bash Scripts/run_hls_quality_gates.sh --skip-build
fi

[[ "$(shasum -a 256 Package.resolved)" == "$resolved_before" ]] \
  || { echo "local-release-preflight: dependency lock drifted" >&2; exit 1; }

echo "$preflight_label: OK ($mode)"
