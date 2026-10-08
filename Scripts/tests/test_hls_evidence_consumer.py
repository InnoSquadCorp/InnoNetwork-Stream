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
  *--show-bin-path*) printf '%s/.build' "$PWD" ;;
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
            # The verify path must not call SwiftPM or recreate the build marker.
            (root / 'Scripts/swiftpm.sh').write_text('exit 99\n')
            result = subprocess.run(['bash', 'Scripts/check_hls_evidence_consumer.sh', 'verify'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / 'built').exists())
            (root / 'Scripts/swiftpm.sh').write_text('''set -eu
printf '{"pins":[]}' > Tests/HLSReleaseEvidence/Package.resolved
''')
            env['TEST_DRIFT'] = '1'
            result = subprocess.run(['bash', 'Scripts/check_hls_evidence_consumer.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('different dependency graph', result.stderr)
            self.assertFalse((root / 'built').exists())

class GenerationTests(unittest.TestCase):
    def test_generation_prepares_once_then_executes_binary_and_verifies(self):
        import importlib.util
        import json
        from unittest.mock import patch
        spec=importlib.util.spec_from_file_location('evidence',ROOT/'Scripts/apple_hls_evidence.py')
        evidence=importlib.util.module_from_spec(spec);spec.loader.exec_module(evidence)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/'repo';bundle=Path(directory)/'bundle'
            (root/'Tests/Fixtures/HLSRuntime/audio-fmp4').mkdir(parents=True)
            (root/'Tests/Fixtures/HLSRuntime/audio-fmp4/index.m3u8').write_text('#EXTM3U\n')
            (root/'Tests/HLSReleaseEvidence').mkdir(parents=True)
            (root/'.build').mkdir()
            for target in (root/'Package.resolved',root/'Tests/HLSReleaseEvidence/Package.resolved'):
                target.write_text('{"pins":[]}')
            (root/'.build/release-evidence-prepared.json').write_text('{"binary_path":"/synthetic/exporter"}')
            (root/'.build/release-evidence-consumer-provenance.json').write_text('{}')
            for name in ('inputs','outputs'): (bundle/name).mkdir(parents=True)
            calls=[]
            def execute(command, cwd, log, env=None, timeout=None):
                calls.append(command)
                log.write_text('synthetic orchestration control\n')
                if command[0]=='/synthetic/exporter':
                    playlists={case:case+'/index.m3u8' for case in evidence.CASES}
                    for value in playlists.values():
                        file=bundle/'outputs'/value;file.parent.mkdir()
                        file.write_text('#EXTM3U\n#EXT-X-ENDLIST\n')
                    (bundle/'outputs/playlists.json').write_text(json.dumps(playlists))
            with patch.object(evidence,'execute',side_effect=execute):
                result=evidence.generate_sdk_outputs(root,bundle)
            self.assertEqual(len(result),6)
            consumer=[c for c in calls if 'Scripts/check_hls_evidence_consumer.sh' in c]
            self.assertEqual([c[-1] for c in consumer],['prepare','verify'])
            self.assertEqual(sum(c[0]=='/synthetic/exporter' for c in calls),1)
            self.assertFalse(any('run' in c and 'Scripts/swiftpm.sh' in c for c in calls))
            self.assertFalse((bundle/'manifest.json').exists())
