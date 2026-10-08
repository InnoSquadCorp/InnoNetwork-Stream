"""Dependency integrity controls must not mutate SwiftPM checkout metadata."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DependencyIntegrityTests(unittest.TestCase):
    def test_read_only_alternate_detects_missing_and_restored_fixture_store(self):
        result = subprocess.run(
            ['bash', str(ROOT / 'Scripts/tests/test_git_dependency_integrity.sh')],
            cwd=ROOT, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('read-only metadata, missing store, restored store', result.stdout)


if __name__ == '__main__':
    unittest.main()
