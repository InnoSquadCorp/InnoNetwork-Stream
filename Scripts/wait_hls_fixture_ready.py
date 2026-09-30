#!/usr/bin/env python3
"""Bounded fixture readiness, with retained startup evidence on failure."""
import argparse
import os
from pathlib import Path
import re
import sys
import time


def wait_for_ready(ready_file: Path, server_pid: int, server_log: Path, timeout: float = 5.0) -> str:
    if server_pid <= 0 or not 0.05 <= timeout <= 30 or not timeout < float("inf"):
        raise ValueError("invalid PID or readiness timeout (0.05...30 seconds)")
    started = time.monotonic()
    deadline = started + timeout
    reason = "fixture server readiness timed out"
    while time.monotonic() < deadline:
        if ready_file.is_file() and ready_file.stat().st_size:
            value = ready_file.read_text(encoding="utf-8").strip()
            match = re.fullmatch(r"http://127\.0\.0\.1:([1-9][0-9]{0,4})", value)
            if not match or int(match[1]) > 65535:
                reason = "fixture server published an invalid loopback URL"
                break
            return value
        try:
            os.kill(server_pid, 0)
        except ProcessLookupError:
            reason = "fixture server exited before readiness"
            break
        time.sleep(min(0.05, max(0, deadline - time.monotonic())))
    elapsed = (time.monotonic() - started) * 1000
    print(f"hls-runtime-smoke: {reason}; elapsed_ms={elapsed:.2f} pid={server_pid} python={sys.executable} log={server_log}", file=sys.stderr)
    if server_log.is_file():
        with server_log.open("r", encoding="utf-8", errors="replace") as log:
            print(log.read(65_536), file=sys.stderr)
    raise RuntimeError(reason)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ready_file", type=Path)
    parser.add_argument("server_pid", type=int)
    parser.add_argument("server_log", type=Path)
    parser.add_argument("--timeout", type=float, default=5.0)
    arguments = parser.parse_args()
    try:
        print(wait_for_ready(arguments.ready_file, arguments.server_pid, arguments.server_log, arguments.timeout))
    except (ValueError, RuntimeError, OSError) as error:
        print(f"hls-runtime-smoke: readiness failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
