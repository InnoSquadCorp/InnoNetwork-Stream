#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


MODULES = {
    "InnoNetworkHLS",
    "InnoNetworkHLSLive",
    "InnoNetworkHLSAVFoundation",
    "InnoNetworkHLSAudio",
}

KINDS = {
    "swift.actor",
    "swift.associatedtype",
    "swift.class",
    "swift.enum",
    "swift.enum.case",
    "swift.func",
    "swift.init",
    "swift.method",
    "swift.macro",
    "swift.property",
    "swift.protocol",
    "swift.struct",
    "swift.type.method",
    "swift.type.property",
    "swift.typealias",
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Collect InnoNetwork-Stream public symbol-graph rows."
    )
    parser.add_argument("repo_root", type=Path)
    args = parser.parse_args()

    candidates = [
        path
        for path in (args.repo_root / ".build").glob("*/symbolgraph")
        if path.is_dir()
    ]
    if not candidates:
        raise SystemExit("No Swift symbol graph directory was generated.")
    symbolgraph_dir = max(candidates, key=lambda path: path.stat().st_mtime)

    rows: set[str] = set()
    seen_modules: set[str] = set()
    for path in sorted(symbolgraph_dir.glob("*.symbols.json")):
        if "@" in path.name:
            continue
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
        module = data.get("module", {}).get("name")
        if module not in MODULES:
            continue
        seen_modules.add(module)
        swift_usr_prefix = f"s:{len(module)}{module}"
        for symbol in data.get("symbols", []):
            if symbol.get("accessLevel") != "public":
                continue
            if symbol.get("kind", {}).get("identifier") not in KINDS:
                continue
            precise = symbol.get("identifier", {}).get("precise", "")
            if not precise.startswith(swift_usr_prefix):
                continue
            components = symbol.get("pathComponents") or []
            if not components:
                continue
            kind = symbol["kind"]["identifier"]
            rows.add(f"{module}\t{kind}\t{'.'.join(components)}")

    missing = sorted(MODULES - seen_modules)
    if missing:
        raise SystemExit(f"Missing required symbol graphs: {', '.join(missing)}")

    for row in sorted(rows):
        print(row)


if __name__ == "__main__":
    main()
