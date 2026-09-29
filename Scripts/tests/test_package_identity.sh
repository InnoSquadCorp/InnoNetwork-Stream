#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

manifest="$(xcrun swift package dump-package)"
printf '%s\n' "$manifest" | jq -e '
  .name == "InnoNetwork-Stream" and
  ([.products[] | select(.type.library != null)] | length) == 5 and
  ([.products[] | select(.name == "InnoNetwork-Stream") | .targets[]] | sort) ==
    ["InnoNetworkHLS", "InnoNetworkHLSAVFoundation", "InnoNetworkHLSAudio", "InnoNetworkHLSLive"] and
  ([.products[] | select(.name != "InnoNetwork-Stream") | .name] | sort) ==
    ["InnoNetworkHLS", "InnoNetworkHLSAVFoundation", "InnoNetworkHLSAudio", "InnoNetworkHLSLive"]
' >/dev/null || { echo "package-identity: package/product contract drifted" >&2; exit 1; }

for mode in aggregate individual; do
  INNONETWORK_STREAM_CONSUMER_MODE="$mode" xcrun swift package \
    --package-path Tests/PackageIdentity \
    --scratch-path .build/package-identity-consumer resolve
  INNONETWORK_STREAM_CONSUMER_MODE="$mode" xcrun swift run \
    --package-path Tests/PackageIdentity \
    --scratch-path .build/package-identity-consumer \
    --force-resolved-versions PackageIdentityConsumer
done

# The application-owned acceptance fixture also resolves the renamed package.
xcrun swift package --package-path Tests/FairPlayAcceptance dump-package \
  | jq -e '
    [.targets[].dependencies[] | .product? | select(.[0] == "InnoNetworkHLSAVFoundation") | .[1]]
    == ["InnoNetwork-Stream"]
  ' >/dev/null

echo "package-identity: OK (aggregate, individual products, FairPlay manifest)"
