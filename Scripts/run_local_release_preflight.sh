#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mode="quick"
case "${1:-}" in
  "") ;;
  --quick) mode="quick" ;;
  --full) mode="full" ;;
  *)
    echo "Usage: bash Scripts/run_local_release_preflight.sh [--quick|--full]" >&2
    exit 64
    ;;
esac

if [[ "${INNONETWORK_LOCAL_PATH+x}" == "x" ]]; then
  echo "local-release-preflight: unset INNONETWORK_LOCAL_PATH to validate the published dependency" >&2
  exit 64
fi

swift_version="$(xcrun swift --version | sed -nE 's/^Apple Swift version ([0-9]+)\.([0-9]+).*/\1.\2/p' | head -n 1)"
swift_major="${swift_version%%.*}"
swift_minor="${swift_version##*.}"
if [[ -z "$swift_version" ]] \
  || (( swift_major < 6 || (swift_major == 6 && swift_minor < 2) )); then
  echo "local-release-preflight: Swift 6.2 or newer is required" >&2
  exit 69
fi

resolved_before="$(shasum -a 256 Package.resolved)"
bash Scripts/check_innonetwork_dependency.sh
[[ "$(shasum -a 256 Package.resolved)" == "$resolved_before" ]] \
  || { echo "local-release-preflight: dependency lock drifted" >&2; exit 1; }

bash Scripts/format.sh --lint
bash Scripts/validate_docs_release_state.sh
bash Scripts/check_public_api_contract.sh
bash Scripts/tests/test_package_identity.sh
bash -n Scripts/*.sh
python3 -m py_compile Scripts/*.py
xcrun swift test --force-resolved-versions --parallel

if [[ "$mode" == "full" ]]; then
  bash Scripts/run_hls_quality_gates.sh \
    --skip-build \
    --require-apple-tools \
    --require-runtime-smoke \
    --apple-report-root .build/local-release-preflight/apple-hls

  xcodebuild \
    -scheme InnoNetwork-Stream-Package \
    -destination 'platform=macOS' \
    -derivedDataPath .build/local-release-preflight/macos \
    CODE_SIGNING_ALLOWED=NO \
    build
  xcodebuild \
    -scheme InnoNetwork-Stream-Package \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/local-release-preflight/ios-simulator \
    CODE_SIGNING_ALLOWED=NO \
    build
  bash Scripts/build_apple_platform_targets.sh \
    tvOS appletvos arm64-apple-tvos16.0 \
    .build/local-release-preflight/tvos
  bash Scripts/build_apple_platform_targets.sh \
    watchOS watchos arm64_32-apple-watchos9.0 \
    .build/local-release-preflight/watchos
  bash Scripts/build_apple_platform_targets.sh \
    visionOS xros arm64-apple-xros1.0 \
    .build/local-release-preflight/visionos
else
  bash Scripts/run_hls_quality_gates.sh --skip-build
fi

[[ "$(shasum -a 256 Package.resolved)" == "$resolved_before" ]] \
  || { echo "local-release-preflight: dependency lock drifted" >&2; exit 1; }

echo "local-release-preflight: OK ($mode)"
