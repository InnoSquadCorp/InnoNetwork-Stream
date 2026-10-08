"""Shell orchestration controls; these do not claim a SwiftPM build."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ConsumerTests(unittest.TestCase):
    def test_candidate_pins_seed_resolution_and_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Scripts').mkdir()
            (root / 'Tests/HLSReleaseEvidence').mkdir(parents=True)
            (root / '.build').mkdir()
            lock = '{"version":3,"pins":[{"identity":"fixture","state":{"version":"1.0.0"}}]}'
            (root / 'Package.resolved').write_text(lock)
            shutil.copyfile(ROOT / 'Scripts/check_hls_evidence_consumer.sh', root / 'Scripts/check_hls_evidence_consumer.sh')
            (root / 'Scripts/check_hls_evidence_graph.py').write_text('print("{}")\n')
            (root / 'Scripts/swiftpm.sh').write_text('''set -eu
case "$*" in
  *resolve)
    cmp Package.resolved Tests/HLSReleaseEvidence/Package.resolved
    if [ "${TEST_DRIFT:-0}" = 1 ]; then
      printf '{"pins":[]}' > Tests/HLSReleaseEvidence/Package.resolved
    fi ;;
  *show-dependencies*) printf '{}' ;;
  build*) touch built ;;
esac
''')
            env = dict(os.environ)
            env.pop('INNONETWORK_LOCAL_PATH', None)
            for stale in (False, True):
                if stale:
                    (root / 'Tests/HLSReleaseEvidence/Package.resolved').write_text('{"pins":[]}')
                result = subprocess.run(['bash', 'Scripts/check_hls_evidence_consumer.sh'], cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue((root / 'built').exists())
                (root / 'built').unlink()
            env['TEST_DRIFT'] = '1'
            result = subprocess.run(['bash', 'Scripts/check_hls_evidence_consumer.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('different dependency graph', result.stderr)
            self.assertFalse((root / 'built').exists())
