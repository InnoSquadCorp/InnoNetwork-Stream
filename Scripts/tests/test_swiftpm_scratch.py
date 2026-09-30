#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("scratch", ROOT / "Scripts/swiftpm_scratch_path.py")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ScratchTests(unittest.TestCase):
    def test_wrapper_forwards_arguments_and_scopes_explicit_base(self):
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            package = scratch / "package"
            package.mkdir()
            (package / "Package.swift").write_text("// test manifest", encoding="utf-8")
            sdk = scratch / "test.sdk"
            sdk.mkdir()
            executable = scratch / "xcrun"
            executable.write_text(
                '#!/bin/sh\ncase "$1:$2" in\n'
                ' --sdk:macosx) printf "%s\\n" "$STREAM_TEST_SDK" ;;\n'
                ' --find:swift) printf "%s\\n" "$STREAM_TEST_SWIFT" ;;\n'
                ' swift:--version) printf "Apple Swift version 6.4\\n" ;;\n'
                ' *) printf "%s\\n" "$@" > "$STREAM_TEST_ARGUMENTS" ;;\nesac\n',
                encoding="utf-8"
            )
            executable.chmod(0o755)
            arguments_file = scratch / "arguments"
            environment = dict(os.environ, PATH=str(scratch) + os.pathsep + os.environ["PATH"],
                STREAM_TEST_SDK=str(sdk), STREAM_TEST_SWIFT=str(scratch / "swift"),
                STREAM_TEST_ARGUMENTS=str(arguments_file))
            supplied = ["run", "--package-path", str(package), "--scratch-path", str(scratch / "old"),
                "Consumer", "--", "--package-path=application-argument"]
            subprocess.run(["bash", str(ROOT / "Scripts/swiftpm.sh"), *supplied], env=environment, check=True)
            observed = arguments_file.read_text().splitlines()
            self.assertEqual(observed[:3], ["swift", "run", "--scratch-path"])
            self.assertEqual(Path(observed[3]).parent, (scratch / "old").resolve())
            self.assertEqual(observed[4:], ["--package-path", str(package), "Consumer", "--", "--package-path=application-argument"])

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
