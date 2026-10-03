"""Exercise fixture startup with broken DNS and real loopback HTTP requests."""
import functools
import http.server
import importlib.util
from pathlib import Path
import socket
import threading
import unittest
from unittest.mock import patch
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    'runtime_server', ROOT / 'Scripts/serve_hls_runtime_fixtures.py')
server_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)


class RuntimeServerTests(unittest.TestCase):
    def test_standard_server_control_depends_on_reverse_dns(self):
        with patch.object(socket, 'getfqdn', side_effect=OSError('DNS unavailable')):
            with self.assertRaisesRegex(OSError, 'DNS unavailable'):
                http.server.ThreadingHTTPServer(
                    ('127.0.0.1', 0), http.server.SimpleHTTPRequestHandler)

    def test_fixture_starts_and_serves_without_dns(self):
        handler = functools.partial(server_module.FixtureRequestHandler,
                                    directory=str(ROOT / 'Tests/Fixtures/HLSRuntime'))
        with patch.object(socket, 'getfqdn', side_effect=OSError('DNS unavailable')) as dns:
            with server_module.LoopbackHTTPServer(('127.0.0.1', 0), handler) as server:
                self.assertEqual(server.server_name, '127.0.0.1')
                self.assertGreater(server.server_port, 0)
                thread = threading.Thread(target=server.serve_forever,
                                          kwargs={'poll_interval': 0.01})
                thread.start()
                try:
                    with urlopen(f'http://127.0.0.1:{server.server_port}/audio-fmp4/index.m3u8',
                                 timeout=5) as response:
                        self.assertEqual(response.status, 200)
                        self.assertIn(b'#EXT-X-ENDLIST', response.read())
                    dns.assert_not_called()
                finally:
                    server.shutdown()
                    thread.join(timeout=5)
                    self.assertFalse(thread.is_alive())


if __name__ == '__main__':
    unittest.main()
