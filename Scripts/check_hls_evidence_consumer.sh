#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ "${INNONETWORK_LOCAL_PATH+x}" != x ]] || { echo 'Evidence exporter requires published Core' >&2; exit 64; }
mode="${1:-prepare}"
[[ $# -le 1 && ( "$mode" == prepare || "$mode" == verify ) ]] || {
  echo 'Usage: check_hls_evidence_consumer.sh [prepare|verify]' >&2; exit 64;
}
graph=.build/release-evidence-consumer-graph.json
prepared=.build/release-evidence-prepared.json
provenance=.build/release-evidence-consumer-provenance.json
if [[ "$mode" == prepare ]]; then
  # Nested packages do not inherit their local dependency's lock.
  cp Package.resolved Tests/HLSReleaseEvidence/Package.resolved
  bash Scripts/swiftpm.sh package --package-path Tests/HLSReleaseEvidence \
    --scratch-path .build/release-evidence-exporter resolve
  python3 - <<'PY'
import json
from pathlib import Path
expected=json.loads(Path('Package.resolved').read_text())['pins']
actual=json.loads(Path('Tests/HLSReleaseEvidence/Package.resolved').read_text())['pins']
if sorted(expected,key=lambda p:p['identity']) != sorted(actual,key=lambda p:p['identity']):
    raise SystemExit('Evidence exporter resolved a different dependency graph; align locks deliberately')
PY
  bash Scripts/swiftpm.sh package --package-path Tests/HLSReleaseEvidence \
    --scratch-path .build/release-evidence-exporter --force-resolved-versions show-dependencies --format json > "$graph"
  python3 Scripts/check_hls_evidence_graph.py --root "$repo_root" --graph "$graph" > "$provenance"
  bash Scripts/swiftpm.sh build --package-path Tests/HLSReleaseEvidence \
    --scratch-path .build/release-evidence-exporter --configuration release --force-resolved-versions
  binary_directory="$(bash Scripts/swiftpm.sh build --package-path Tests/HLSReleaseEvidence \
    --scratch-path .build/release-evidence-exporter --configuration release --force-resolved-versions --show-bin-path)"
  python3 Scripts/check_hls_evidence_graph.py --root "$repo_root" --graph "$graph" \
    --binary "$binary_directory/HLSReleaseEvidence" > "$prepared"
  cp "$prepared" "$provenance"
else
  # Verification does not resolve, build, seed locks or repair checkouts.
  python3 Scripts/check_hls_evidence_graph.py --root "$repo_root" --graph "$graph" \
    --prepared "$prepared" > "$provenance"
fi
