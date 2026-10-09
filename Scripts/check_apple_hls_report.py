#!/usr/bin/env python3
"""Reject unsupported Apple HLS output and blocking validator/report issues."""

from __future__ import annotations

import argparse
import json
import re
from html.parser import HTMLParser
from pathlib import Path

# The collector explicitly requests --compatible-output=v1.x. Expand this only
# after testing a real tool's new JSON/report structure, not just its exit code.
SUPPORTED_DATA_VERSIONS = frozenset((1.3,))
MAX_BYTES = 64 * 1024 * 1024


class TextCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []
        self.sections: list[tuple[str, list[str]]] = []
        self.heading: list[str] | None = None
        self.ignored_depth = 0

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag in ("script", "style"):
            self.ignored_depth += 1
        elif not self.ignored_depth and tag in ("h1", "h2", "h3"):
            self.heading = []

    def handle_endtag(self, tag: str) -> None:
        if tag in ("script", "style"):
            self.ignored_depth = max(0, self.ignored_depth - 1)
        elif tag in ("h1", "h2", "h3") and self.heading is not None:
            self.sections.append((" ".join(self.heading), []))
            self.heading = None

    def handle_data(self, data: str) -> None:
        if self.ignored_depth:
            return
        value = " ".join(data.split())
        if value:
            self.parts.append(value)
            if self.heading is not None:
                self.heading.append(value)
            elif self.sections:
                self.sections[-1][1].append(value)


def fail(message: str) -> None:
    raise SystemExit(f"apple-hls-report: {message}")


def parse_report(path: Path) -> TextCollector:
    if not path.is_file():
        fail(f"report is missing: {path}")
    if not 0 < path.stat().st_size <= MAX_BYTES:
        fail(f"report is empty or oversized: {path}")
    parser = TextCollector()
    try:
        parser.feed(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as error:
        fail(f"cannot read {path}: {error}")
    return parser


def visible_text(path: Path) -> str:
    return " ".join(parse_report(path).parts)


def read_validation_json(path: Path) -> object:
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                fail("duplicate validator JSON key")
            result[key] = value
        return result
    try:
        if not path.is_file() or not 0 < path.stat().st_size <= MAX_BYTES:
            fail("missing, empty or oversized validation JSON")
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)
    except (OSError, UnicodeError, ValueError, RecursionError) as error:
        fail(f"cannot read validation JSON: {error}")


def validate_data(data: object) -> float:
    if not isinstance(data, dict) or type(data.get("dataVersion")) not in (int, float):
        fail("missing or invalid validator dataVersion")
    version = data["dataVersion"]
    if version not in SUPPORTED_DATA_VERSIONS:
        fail(f"unsupported validator JSON schema: {version}")
    if (data.get("validatorName") != "mediastreamvalidator"
            or not isinstance(data.get("validatorVersion"), str) or not data["validatorVersion"]
            or data.get("playlistKind") not in ("media", "multivariant")
            or not isinstance(data.get("messages"), list)
            or type(data.get("dataStatus")) is not int or data["dataStatus"] != 1):
        fail("unrecognized validator JSON structure")
    content_key = "discontinuities" if data["playlistKind"] == "media" else "variants"
    content = data.get(content_key)
    if not isinstance(content, list) or not content or not all(isinstance(item, dict) for item in content):
        fail("validator JSON contains no recognized media/presentation data")
    if data["playlistKind"] == "media":
        if type(data.get("processedSegmentsCount")) is not int or data["processedSegmentsCount"] <= 0:
            fail("validator JSON contains no processed segments")
        if any(not isinstance(item.get("segments"), list) or not item["segments"]
               or not all(isinstance(segment, dict) for segment in item["segments"]) for item in content):
            fail("validator JSON contains no recognized segment data")
    stack = [data]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            if "messages" in node:
                if not isinstance(node["messages"], list):
                    fail("unrecognized validator message structure")
                for message in node["messages"]:
                    if not isinstance(message, dict) or type(message.get("errorStatusCode")) is not int:
                        fail("missing validator message severity code")
                    code = message["errorStatusCode"]
                    if not 100000 <= code < 800000:
                        fail(f"unrecognized validator severity code: {code}")
                    if code >= 400000:
                        fail(f"validator reported a blocking issue: {code}")
            stack.extend(value for key, value in node.items()
                         if key != "messages" and isinstance(value, (dict, list)))
        elif isinstance(node, list):
            stack.extend(node)
    return version


def validate(path: Path, validation_data: object = None) -> None:
    parser = parse_report(path)
    report_text = " ".join(parser.parts)
    information = [" ".join(parts) for heading, parts in parser.sections
                   if re.fullmatch(r"report\s+information", heading, re.I)]
    if (len(information) != 1 or not any(re.match(r"HLS\s+Validation\s+Report", heading, re.I)
                                       for heading, _ in parser.sections)):
        fail(f"report format is unrecognized: {path}")
    if re.search(r"not\s+understood|unsupported|unrecognized|cannot\s+(?:read|process)", report_text, re.I):
        fail(f"report contains unsupported-format notice: {path}")
    versions = re.findall(r"JSON\s+format\s+version:\s*(\d+(?:\.\d+)+)(?![\w.])", information[0], re.I)
    if len(versions) != 1 or versions[0] != "1.3":
        fail(f"missing or unsupported report JSON format version: {path}")
    if validation_data is not None and validate_data(validation_data) != float(versions[0]):
        fail(f"report and validator JSON format versions differ: {path}")
    for heading, parts in parser.sections:
        if not re.search(r"must\s+fix\s+issues", heading, re.I):
            continue
        section = " ".join(parts).strip(" \t\r\n:.-")
        if not re.fullmatch(r"(?:none|no\s+(?:must\s+fix\s+)?issues(?:\s+found)?)", section, re.I):
            fail(f"Must Fix issues found in {path}: {section}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path, nargs="?")
    parser.add_argument("--validation-json", type=Path)
    arguments = parser.parse_args()
    validation_data = None
    if arguments.validation_json:
        validation_data = read_validation_json(arguments.validation_json)
        validate_data(validation_data)
    if arguments.report:
        validate(arguments.report.resolve(), validation_data)
        print(f"apple-hls-report: OK ({arguments.report})")
    elif validation_data is None:
        parser.error("report or --validation-json is required")


if __name__ == "__main__":
    main()
