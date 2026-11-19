"""Isolated proxy discovery and CONNECT checks; no real network or accounts."""
import importlib.util
import json
from pathlib import Path
from unittest.mock import Mock, patch
import unittest

spec = importlib.util.spec_from_file_location(
    "steam_proxy_bridge_tested", Path(__file__).with_name("steam_proxy_bridge.py"))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        bridge._cached_route = None

    def test_only_core_loopback_listeners_are_candidates(self):
        processes = '"core.exe","37848","Console","1","1 K"\n"other.exe","4","Console","1","1 K"\n'
        sockets = ('TCP 127.0.0.1:20874 0.0.0.0:0 LISTENING 37848\n'
                   'TCP 127.0.0.1:22365 0.0.0.0:0 LISTENING 37848\n'
                   'TCP 0.0.0.0:18000 0.0.0.0:0 LISTENING 37848\n'
                   'TCP 127.0.0.1:7890 0.0.0.0:0 LISTENING 4\n'
                   'TCP 127.0.0.1:20874 127.0.0.1:33333 ESTABLISHED 37848\n')
        self.assertEqual(bridge.candidate_ports(tasklist=processes, netstat=sockets), [20874, 22365])

    def test_port_change_is_found_on_next_connection(self):
        attempts = []
        def connect(port, address=None, **kwargs):
            attempts.append(port)
            if port == 20874:
                raise OSError("old port closed")
            return Mock()
        bridge._cached_route = (20874, "23.63.77.13", float("inf"))
        with patch.object(bridge, "candidate_ports", return_value=[22365]), \
             patch.object(bridge, "discover_route", return_value=(22365, "23.63.77.13", float("inf"))), \
             patch.object(bridge, "connect_proxy", side_effect=connect):
            port, _ = bridge.current_proxy()
        self.assertEqual(port, 22365)
        self.assertEqual(attempts, [20874, 22365])

    def test_cached_verified_route_uses_one_connect_without_system_scan(self):
        bridge._cached_route = (20874, "23.63.77.13", float("inf"))
        with patch.object(bridge, "candidate_ports") as scan, \
             patch.object(bridge, "discover_route") as discover, \
             patch.object(bridge, "connect_proxy", return_value=Mock()) as connect:
            for _ in range(100):
                self.assertEqual(bridge.current_proxy()[0], 20874)
        self.assertEqual(connect.call_count, 100)
        scan.assert_not_called()
        discover.assert_not_called()

    def test_dns_expiry_revalidates_same_port_without_full_scan(self):
        bridge._cached_route = (20874, "23.63.77.13", 0)
        with patch.object(bridge, "candidate_ports") as scan, \
             patch.object(bridge, "discover_route", return_value=(20874, "23.35.100.199", float("inf"))) as refresh, \
             patch.object(bridge, "connect_proxy", return_value=Mock()) as connect:
            bridge.current_proxy()
        refresh.assert_called_once()
        scan.assert_not_called()
        self.assertEqual(connect.call_args.args, (20874, "23.35.100.199"))

    def test_connect_success_without_official_tls_rejection_is_not_a_route(self):
        with patch.object(bridge, "resolve_steam", return_value=[("23.63.77.13", 10)]), \
             patch.object(bridge, "verify_route", side_effect=OSError("certificate failed")) as verify:
            with self.assertRaises(OSError):
                bridge.discover_route(20874, bridge.time.monotonic() + 10)
        self.assertEqual(verify.call_count, 2)

    def test_dns_provider_failure_uses_second_provider(self):
        with patch.object(bridge, "resolve_steam", side_effect=[OSError("dns failed"), [("23.63.77.13", 10)]]) as resolve, \
             patch.object(bridge, "verify_route") as verify:
            route = bridge.discover_route(20874, bridge.time.monotonic() + 10)
        self.assertEqual(route[:2], (20874, "23.63.77.13"))
        self.assertEqual(resolve.call_count, 2)
        verify.assert_called_once()

    def test_dns_rejects_wrong_owner_nonpublic_and_invalid_records(self):
        for address, owner, ttl in (("127.0.0.1", "steamcommunity.com.", 5),
                                    ("198.18.0.1", "steamcommunity.com.", 5),
                                    ("23.63.77.13", "other.example.", 5),
                                    ("23.63.77.13", "steamcommunity.com.", -1),
                                    ("::1", "steamcommunity.com.", 5)):
            raw = json.dumps({"Status": 0, "Answer": [{"name": owner, "type": 1, "data": address, "TTL": ttl}]}).encode()
            with self.assertRaises(ValueError):
                bridge.dns_answers(raw)
        with self.assertRaises(ValueError):
            bridge.dns_answers(b" " * 8193)

    def test_dns_ttl_and_answer_count_are_bounded(self):
        raw = json.dumps({"Status": 0, "Answer": [{"name": "steamcommunity.com.", "type": 1,
                          "data": "23.63.77.13", "TTL": 120}]}).encode()
        self.assertEqual(bridge.dns_answers(raw), [("23.63.77.13", 60)])

    def test_verified_route_never_disables_certificate_or_hostname_check(self):
        stream = Mock(); stream.__enter__ = Mock(return_value=stream); stream.__exit__ = Mock(return_value=False)
        context = Mock()
        context.wrap_socket.side_effect = bridge.ssl.SSLCertVerificationError("bad certificate")
        with patch.object(bridge, "connect_proxy", return_value=stream), \
             patch.object(bridge.ssl, "create_default_context", return_value=context):
            with self.assertRaises(bridge.ssl.SSLCertVerificationError):
                bridge.verify_route(20874, "23.63.77.13", bridge.time.monotonic() + 10)
        self.assertEqual(context.wrap_socket.call_args.kwargs["server_hostname"], "steamcommunity.com")

    def test_discovery_deadline_refuses_more_network_calls(self):
        with patch.object(bridge, "resolve_steam", side_effect=OSError("down")) as resolve:
            with self.assertRaises(TimeoutError):
                bridge.discover_route(20874, bridge.time.monotonic() - 1)
        self.assertEqual(resolve.call_count, 1)

    def test_connect_request_has_only_official_fixed_target(self):
        stream = Mock()
        stream.recv.return_value = b"HTTP/1.1 200 Connection established\r\n\r\n"
        with patch.object(bridge.socket, "create_connection", return_value=stream) as dial:
            self.assertIs(bridge.connect_proxy(20874), stream)
        self.assertEqual(dial.call_args.args[0], ("127.0.0.1", 20874))
        request = stream.sendall.call_args.args[0]
        self.assertEqual(request.count(b"steamcommunity.com:443"), 2)
        self.assertNotIn(b"https://", request)

    def test_proxy_auth_or_redirect_never_passes_tunnel_bytes(self):
        for response in (b"HTTP/1.1 407 Proxy Authentication Required\r\n\r\n",
                         b"HTTP/1.1 302 Found\r\n\r\n",
                         b"HTTP/1.1 200 OK\r\n\r\nextra"):
            stream = Mock(); stream.recv.return_value = response
            with patch.object(bridge.socket, "create_connection", return_value=stream):
                with self.assertRaises(OSError):
                    bridge.connect_proxy(20874)
            stream.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
