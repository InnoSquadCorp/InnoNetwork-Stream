#!/usr/bin/env bash
# Compile the real UIKit delegate signature on both CI Swift toolchains.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
bash Scripts/check_innonetwork_dependency.sh
sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
bash Scripts/swiftpm.sh build \
  --package-path "$repo_root" \
  --force-resolved-versions \
  --scratch-path "$repo_root/.build/uikit-background-consumer" \
  --triple arm64-apple-ios16.0-simulator \
  --sdk "$sdk_path" \
  --target HLSUIKitBackgroundSessionCompileFixture
echo "uikit-background-consumer: OK (actual UIApplicationDelegate signature)"
