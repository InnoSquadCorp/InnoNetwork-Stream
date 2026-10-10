#!/usr/bin/env python3
"""Exact current release links must match RELEASE_VERSION, not a prefix."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReadmeReleaseLinkTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='stream-readme-release-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.version = (ROOT / 'RELEASE_VERSION').read_text(encoding='utf-8').strip()
        for path in ROOT.iterdir():
            target = self.root / path.name
            if path.name == '.git':
                continue
            if path.name.startswith('README') or path.name == 'RELEASE_VERSION':
                shutil.copy2(path, target)
            elif path.name == 'Scripts':
                target.mkdir()
                for script in path.iterdir():
                    if script.name == 'check_readme_parity.py':
                        shutil.copy2(script, target / script.name)
                    else:
                        (target / script.name).symlink_to(script, target_is_directory=script.is_dir())
            else:
                target.symlink_to(path, target_is_directory=path.is_dir())

    def run_check(self):
        return subprocess.run(
            [sys.executable, str(self.root / 'Scripts/check_readme_parity.py')],
            capture_output=True, text=True, encoding='utf-8', timeout=30,
        )

    def test_current_release_passes(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_wrong_release_destinations_fail(self):
        path = self.root / 'README.ja.md'
        original = path.read_text(encoding='utf-8')
        expected = f'https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/{self.version}'
        for replacement in (expected + '0', expected + '-rc.1', expected + '/extra',
                            expected.replace('github.com', 'example.com')):
            with self.subTest(replacement=replacement):
                path.write_text(original.replace(expected, replacement), encoding='utf-8')
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('README.ja.md: missing stable release link', result.stderr)

    def test_expected_release_comes_from_version_file(self):
        major, minor, patch = self.version.split('.')
        next_version = f'{major}.{minor}.{int(patch) + 1}'
        (self.root / 'RELEASE_VERSION').write_text(next_version + '\n', encoding='utf-8')
        self.assertNotEqual(self.run_check().returncode, 0)
        for path in self.root.glob('README*.md'):
            text = path.read_text(encoding='utf-8')
            path.write_text(text.replace(f'/releases/tag/{self.version}', f'/releases/tag/{next_version}'), encoding='utf-8')
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_malformed_release_version_fails(self):
        (self.root / 'RELEASE_VERSION').write_text('6.1.1-rc.1\n', encoding='utf-8')
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('invalid RELEASE_VERSION', result.stderr)


if __name__ == '__main__':
    unittest.main()
