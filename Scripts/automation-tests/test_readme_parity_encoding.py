#!/usr/bin/env python3
"""Verify multilingual Markdown is read as UTF-8 independently of the locale."""
import os
from pathlib import Path
import subprocess
import sys
import unittest


class ReadmeEncodingTests(unittest.TestCase):
    def test_ascii_locale_without_python_utf8_coercion(self):
        root = Path(__file__).resolve().parents[2]
        env = dict(os.environ, LC_ALL='C', PYTHONUTF8='0', PYTHONCOERCECLOCALE='0')
        result = subprocess.run(
            [sys.executable, str(root / 'Scripts/check_readme_parity.py')],
            cwd=root, env=env, capture_output=True, text=True, encoding='utf-8',
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('readme parity: OK', result.stdout)


if __name__ == '__main__':
    unittest.main()
