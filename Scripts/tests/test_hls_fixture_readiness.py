#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SERVER = load("fixture_server", ROOT / "Scripts/serve_hls_runtime_fixtures.py")
WAIT = load("fixture_wait", ROOT / "Scripts/wait_hls_fixture_ready.py")


class FixtureReadinessTests(unittest.TestCase):
    def test_loopback_bind_never_resolves_dns(self):
        with patch("socket.getfqdn", side_effect=AssertionError("DNS must not run")):
            server = SERVER.LoopbackFixtureServer(("127.0.0.1", 0), SERVER.FixtureRequestHandler)
            try:
                self.assertEqual(server.server_name, "127.0.0.1")
                self.assertGreater(server.server_port, 0)
            finally:
                server.server_close()

    def test_standard_server_is_failing_control(self):
        with patch("socket.getfqdn", side_effect=RuntimeError("blocked DNS")):
            with self.assertRaisesRegex(RuntimeError, "blocked DNS"):
                SERVER.http.server.ThreadingHTTPServer(("127.0.0.1", 0), SERVER.FixtureRequestHandler)

    def test_ready_timeout_exit_and_invalid_url(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / "ready"
            log = Path(directory) / "server.log"
            log.write_text("startup-evidence", encoding="utf-8")
            ready.write_text("http://127.0.0.1:12345\n", encoding="utf-8")
            self.assertEqual(WAIT.wait_for_ready(ready, os.getpid(), log), "http://127.0.0.1:12345")
            ready.write_text("http://untrusted.example:12345", encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stderr(output), self.assertRaisesRegex(RuntimeError, "invalid loopback"):
                WAIT.wait_for_ready(ready, os.getpid(), log)
            self.assertIn("startup-evidence", output.getvalue())
            ready.unlink()
            ticks = [0.0]
            with patch.object(WAIT.time, "monotonic", side_effect=lambda: ticks[0]), patch.object(
                WAIT.time, "sleep", side_effect=lambda duration: ticks.__setitem__(0, ticks[0] + duration)
            ), contextlib.redirect_stderr(output), self.assertRaisesRegex(RuntimeError, "timed out"):
                WAIT.wait_for_ready(ready, os.getpid(), log, 0.1)
            self.assertIn("elapsed_ms=100.00", output.getvalue())
            self.assertTrue(log.exists())
            with patch.object(WAIT.os, "kill", side_effect=ProcessLookupError), contextlib.redirect_stderr(output), self.assertRaisesRegex(RuntimeError, "exited before readiness"):
                WAIT.wait_for_ready(ready, os.getpid(), log)
            for invalid in [float("nan"), float("inf"), -1, 31]:
                with self.assertRaises(ValueError):
                    WAIT.wait_for_ready(ready, os.getpid(), log, invalid)


if __name__ == "__main__":
    unittest.main()
