#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ "${INNONETWORK_LOCAL_PATH+x}" != x ]] || { echo 'Evidence exporter requires published Core' >&2; exit 64; }
# A nested package does not inherit its local dependency's lock. Seed the
# candidate pins before resolving; SwiftPM may update the consumer origin hash,
# but the comparison below rejects any changed pin before build/export.
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
  --scratch-path .build/release-evidence-exporter --force-resolved-versions show-dependencies --format json \
  > .build/release-evidence-consumer-graph.json
python3 Scripts/check_hls_evidence_graph.py --root "$repo_root" \
  --graph .build/release-evidence-consumer-graph.json > .build/release-evidence-consumer-provenance.json
bash Scripts/swiftpm.sh build --package-path Tests/HLSReleaseEvidence \
  --scratch-path .build/release-evidence-exporter --configuration release --force-resolved-versions
