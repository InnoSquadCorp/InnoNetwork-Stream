#!/usr/bin/env python3
"""Canonical semantic API snapshot; generated metadata, never source locations."""
import argparse
import difflib
import json
from pathlib import Path

from collect_public_symbols import KINDS, MODULES


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def signature_rows(graph):
    module = graph.get("module", {}).get("name")
    if module not in MODULES:
        return []
    prefix = f"s:{len(module)}{module}"
    relationships = {}
    for relation in graph.get("relationships", []):
        if relation.get("kind") in {"conformsTo", "inheritsFrom", "requirementOf", "defaultImplementationOf"}:
            relationships.setdefault(relation["source"], []).append({
                key: relation[key] for key in ("kind", "target", "swiftConstraints") if key in relation
            })
    rows = []
    for symbol in graph.get("symbols", []):
        precise = symbol.get("identifier", {}).get("precise", "")
        kind = symbol.get("kind", {}).get("identifier")
        if symbol.get("accessLevel") != "public" or kind not in KINDS or not precise.startswith(prefix):
            continue
        path = symbol.get("pathComponents") or []
        if not path:
            continue
        # Fragments retain type identity, async/throws, mutability and actor
        # attributes. USR retains distinct overloads, unlike the name-only gate.
        payload = {
            "declaration": symbol.get("declarationFragments", []),
            "generics": symbol.get("swiftGenerics", {}),
            "availability": sorted(symbol.get("availability", []), key=canonical),
            "relationships": sorted(relationships.get(precise, []), key=canonical),
        }
        rows.append("\t".join((module, kind, ".".join(path), precise, canonical(payload))))
    return sorted(set(rows))


def collect(root, build_root=None):
    candidates = [path for path in (build_root or root / ".build").glob("*/symbolgraph") if path.is_dir()]
    if not candidates:
        raise SystemExit("No generated symbol graphs; run the public API gate first.")
    directory = max(candidates, key=lambda path: path.stat().st_mtime)
    seen = set()
    rows = set()
    for path in sorted(directory.glob("*.symbols.json")):
        if "@" in path.name:
            continue
        graph = json.loads(path.read_text(encoding="utf-8"))
        if graph.get("module", {}).get("name") in MODULES:
            seen.add(graph["module"]["name"])
            rows.update(signature_rows(graph))
    if MODULES - seen:
        raise SystemExit(f"Missing required modules: {sorted(MODULES - seen)}")
    return "\n".join(sorted(rows)) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo_root", type=Path)
    parser.add_argument("--build-root", type=Path)
    parser.add_argument("--check", type=Path)
    parser.add_argument("--write-snapshot", type=Path, help="Explicit mechanical regeneration after semantic API review")
    args = parser.parse_args()
    if args.check and args.write_snapshot:
        parser.error("check and regeneration are mutually exclusive")
    observed = collect(args.repo_root, args.build_root)
    if args.check:
        expected = args.check.read_text(encoding="utf-8")
        if expected != observed:
            diff = list(difflib.unified_diff(expected.splitlines(), observed.splitlines(), fromfile=str(args.check), tofile="observed", lineterm=""))
            print("\n".join(diff[:80]))
            raise SystemExit("semantic-api-contract: drift (first 80 diff lines shown)")
        print(f"semantic-api-contract: OK ({len(observed.splitlines())} distinct signatures)")
    elif args.write_snapshot:
        args.write_snapshot.write_text(observed, encoding="utf-8")
        print(f"semantic-api-snapshot: generated {len(observed.splitlines())} signatures at {args.write_snapshot}")
    else:
        print(observed, end="")


if __name__ == "__main__":
    main()
