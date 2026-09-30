#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("scratch", ROOT / "Scripts/swiftpm_scratch_path.py")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ScratchTests(unittest.TestCase):
    def test_root_sdk_toolchain_invalidation_and_stable_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = root / ".build/old-cache"
            base.mkdir(parents=True)
            sentinel = base / "original.txt"
            sentinel.write_text("preserve", encoding="utf-8")
            original = scope.scoped_path(root, base, "swift6.4", "macos27")
            self.assertEqual(original, scope.scoped_path(root, base, "swift6.4", "macos27"))
            for package, toolchain, sdk in [(root / "renamed", "swift6.4", "macos27"), (root, "swift6.2", "macos27"), (root, "swift6.4", "tvos27")]:
                self.assertNotEqual(original, scope.scoped_path(package, base, toolchain, sdk))
            self.assertEqual(original.parent, base.resolve())
            self.assertEqual(sentinel.read_text(), "preserve")
            self.assertFalse(original.exists())


if __name__ == "__main__":
    unittest.main()
