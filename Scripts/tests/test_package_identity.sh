#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

manifest="$(bash Scripts/swiftpm.sh package dump-package)"
printf '%s\n' "$manifest" | jq -e '
  .name == "InnoNetwork-Stream" and
  ([.products[] | select(.type.library != null)] | length) == 5 and
  ([.products[] | select(.name == "InnoNetwork-Stream") | .targets[]] | sort) ==
    ["InnoNetworkHLS", "InnoNetworkHLSAVFoundation", "InnoNetworkHLSAudio", "InnoNetworkHLSLive"] and
  ([.products[] | select(.name != "InnoNetwork-Stream") | .name] | sort) ==
    ["InnoNetworkHLS", "InnoNetworkHLSAVFoundation", "InnoNetworkHLSAudio", "InnoNetworkHLSLive"]
' >/dev/null || { echo "package-identity: package/product contract drifted" >&2; exit 1; }

expected_core_revision="$(jq -er '.pins[] | select(.identity == "innonetwork") | .state.revision' Package.resolved)"
for mode in aggregate individual; do
  INNONETWORK_STREAM_CONSUMER_MODE="$mode" bash Scripts/swiftpm.sh package \
    --package-path Tests/PackageIdentity \
    --scratch-path .build/package-identity-consumer resolve
  consumer_core_revision="$(jq -er '.pins[] | select(.identity == "innonetwork") | .state.revision' Tests/PackageIdentity/Package.resolved)"
  [[ "$consumer_core_revision" == "$expected_core_revision" ]] \
    || { echo "package-identity: consumer Core lock differs from the Stream candidate; align the locks deliberately" >&2; exit 1; }
  consumer_core_path="$(INNONETWORK_STREAM_CONSUMER_MODE="$mode" bash Scripts/swiftpm.sh package \
    --package-path Tests/PackageIdentity \
    --scratch-path .build/package-identity-consumer \
    --force-resolved-versions show-dependencies --format json \
    | jq -er '.dependencies[] | select(.identity == "innonetwork") | .path')"
  [[ "$(git -C "$consumer_core_path" rev-parse --verify HEAD)" == "$expected_core_revision" ]] \
    || { echo "package-identity: active Core checkout differs from the Stream candidate" >&2; exit 1; }
  INNONETWORK_STREAM_CONSUMER_MODE="$mode" bash Scripts/swiftpm.sh run \
    --package-path Tests/PackageIdentity \
    --scratch-path .build/package-identity-consumer \
    --force-resolved-versions PackageIdentityConsumer
done

# The application-owned acceptance fixture also resolves the renamed package.
bash Scripts/swiftpm.sh package --package-path Tests/FairPlayAcceptance dump-package \
  | jq -e '
    [.targets[].dependencies[] | .product? | select(.[0] == "InnoNetworkHLSAVFoundation") | .[1]]
    == ["InnoNetwork-Stream"]
  ' >/dev/null

echo "package-identity: OK (aggregate, individual products, FairPlay manifest)"
