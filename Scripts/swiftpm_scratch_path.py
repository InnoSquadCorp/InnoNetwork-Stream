#!/usr/bin/env python3
"""Resolve an isolated, reusable SwiftPM root without changing old caches."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def scoped_path(package_root: Path, base: Path, toolchain: str, sdk: str) -> Path:
    context = json.dumps({"root": str(package_root.resolve()), "toolchain": toolchain, "sdk": sdk}, sort_keys=True)
    token = hashlib.sha256(context.encode()).hexdigest()[:24]
    return base.resolve() / f"scope-{token}"


def command(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True, stderr=subprocess.STDOUT).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package_root", type=Path)
    parser.add_argument("--base", type=Path)
    parser.add_argument("--sdk", type=Path)
    arguments = parser.parse_args()
    root = arguments.package_root.resolve(strict=True)
    if not (root / "Package.swift").is_file():
        parser.error("package root must contain Package.swift")
    sdk = (arguments.sdk or Path(command("xcrun", "--sdk", "macosx", "--show-sdk-path"))).resolve(strict=True)
    settings = sdk / "SDKSettings.json"
    sdk_identity = str(sdk) + (hashlib.sha256(settings.read_bytes()).hexdigest() if settings.is_file() else "")
    toolchain = str(Path(command("xcrun", "--find", "swift")).resolve()) + command("xcrun", "swift", "--version")
    print(scoped_path(root, arguments.base or root / ".build/swiftpm", toolchain, sdk_identity))


if __name__ == "__main__":
    main()
