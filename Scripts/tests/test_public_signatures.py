#!/usr/bin/env python3
"""Passing controls plus independent semantic-change fixtures."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from collect_public_signatures import MODULES, collect, signature_rows


class Signatures(unittest.TestCase):
    def setUp(self):
        self.symbol = {
            "identifier": {"precise": "s:14InnoNetworkHLSFixture"},
            "accessLevel": "public", "kind": {"identifier": "swift.method"},
            "pathComponents": ["Fixture", "value(_:)"] ,
            "declarationFragments": [{"kind": "attribute", "spelling": "@MainActor"}, {"kind": "keyword", "spelling": "async throws"}],
            "swiftGenerics": {"constraints": [{"kind": "conformance", "lhs": "T", "rhs": "Sendable"}]},
            "availability": [{"domain": "macOS", "introduced": {"major": 14}}],
        }
        self.graph = {"module": {"name": "InnoNetworkHLS"}, "symbols": [self.symbol]}

    def test_overloads_do_not_coalesce(self):
        overload = copy.deepcopy(self.symbol)
        overload["identifier"]["precise"] += "Other"
        self.graph["symbols"].append(overload)
        self.assertEqual(len(signature_rows(self.graph)), 2)

    def test_semantic_drift_is_detected(self):
        before = signature_rows(self.graph)
        for field in ("declarationFragments", "swiftGenerics", "availability"):
            changed = copy.deepcopy(self.graph)
            changed["symbols"][0].pop(field)
            self.assertNotEqual(signature_rows(changed), before, field)
        changed = copy.deepcopy(self.graph)
        changed["relationships"] = [{"kind": "conformsTo", "source": self.symbol["identifier"]["precise"], "target": "s:ScA"}]
        self.assertNotEqual(signature_rows(changed), before)

    def test_source_locations_and_docs_are_not_semantics(self):
        before = signature_rows(self.graph)
        self.symbol["location"] = {"position": {"line": 100}}
        self.symbol["docComment"] = {"lines": ["changed prose"]}
        self.assertEqual(signature_rows(self.graph), before)

    def test_explicit_build_context_does_not_select_or_delete_other_graphs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            current = root / ".build/scoped/current"
            graphs = current / "out/symbolgraph"
            graphs.mkdir(parents=True)
            sentinel = root / ".build/other/symbolgraph/keep.symbols.json"
            sentinel.parent.mkdir(parents=True)
            sentinel.write_text("preserve historical diagnostics", encoding="utf-8")
            for module in MODULES:
                (graphs / f"{module}.symbols.json").write_text(
                    json.dumps(self.graph if module == "InnoNetworkHLS" else {"module": {"name": module}, "symbols": []}),
                    encoding="utf-8"
                )
            self.assertIn("Fixture.value", collect(root, current))
            self.assertEqual(sentinel.read_text(), "preserve historical diagnostics")
            with self.assertRaises(SystemExit):
                collect(root, root / ".build/missing")


if __name__ == "__main__":
    unittest.main()
