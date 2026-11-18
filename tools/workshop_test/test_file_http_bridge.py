"""Permanent no-network regression for the closed-test transport contract."""
import base64
import json
from pathlib import Path
import random
import sys
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent))
import file_http_bridge as bridge


class Files:
    def __init__(self):
        self.published, self.retired = [], []
    def publish(self, *args):
        self.published.append(args)
        return []
    def retire(self, paths):
        self.retired.append(paths)
    def close(self):
        pass
    def arm(self, nonce):
        self.next_nonce = nonce


class Tests(unittest.TestCase):
    def setUp(self):
        self.account = sorted(bridge.ACCOUNTS)[0]
        self.identity = (self.account, "closed_test_match_123")
        self.now = [100.0]
        self.clock = lambda: self.now[0]

    def job(self, path, value, headers=None):
        raw = bridge.compact(value)
        chunks = (len(raw) + 1023) // 1024
        return bridge.Job("sfb_1", 1, "POST", path, headers or {}, len(raw), chunks, 130,
                          {i + 1: raw[i * 1024:(i + 1) * 1024] for i in range(chunks)}, len(raw), True)

    def test_real_credentials_never_in_game_response_and_scope_preserved(self):
        device, token = "real_device_" + "d" * 32, "pwa1_" + "f" * 64
        calls = []
        identity = {"account_id": self.account, "match_session_id": self.identity[1]}
        def network(method, path, headers, body, timeout):
            calls.append((method, path, headers, json.loads(body)))
            if path.endswith("/start"):
                return 200, bridge.compact({"ok": True, "device_code": device, "expires_in": 600})
            if path.endswith("/poll"):
                self.assertEqual(json.loads(body)["device_code"], device)
                return 200, bridge.compact({**identity, "ok": True, "access_token": token, "expires_in": 3600})
            self.assertEqual(headers["Authorization"], "Bearer " + token)
            return 200, b'{"profile": "unchanged"}'
        transport = bridge.Transport(network, self.clock)
        _, start = transport.send(self.job("/v1/player-auth/start", identity))
        self.assertNotIn(device.encode(), start)
        alias_device = json.loads(start)["device_code"]
        _, poll = transport.send(self.job("/v1/player-auth/poll", {**identity, "device_code": alias_device}))
        alias_token = json.loads(poll)["access_token"]
        self.assertNotEqual(alias_token, token)
        self.assertRegex(alias_token, r"^pwa1_[a-f0-9]{64}$")
        self.assertNotIn(token.encode(), poll)
        status, raw = transport.send(self.job("/v1/profile", identity, {"Authorization": "Bearer " + alias_token}))
        self.assertEqual((status, raw), (200, b'{"profile": "unchanged"}'))
        with self.assertRaises(ValueError):
            transport.send(self.job("/v1/profile", {**identity, "match_session_id": "different_match"},
                                    {"Authorization": "Bearer " + alias_token}))
        self.assertEqual(len(calls), 3)

    def test_vault_expiry_capacity_and_kind(self):
        vault = bridge.Vault(self.clock)
        alias = vault.store("device", "x" * 32, self.identity, 1)
        with self.assertRaises(ValueError):
            vault.resolve(alias, "token", self.identity)
        self.now[0] += 2
        with self.assertRaises(ValueError):
            vault.resolve(alias, "device", self.identity)
        for _ in range(64):
            vault.store("token", "y" * 32, self.identity, 60)
        with self.assertRaises(ValueError):
            vault.store("token", "z" * 32, self.identity, 60)

    def test_no_network_for_wrong_identity_or_raw_token(self):
        network = mock.Mock(side_effect=AssertionError("network forbidden"))
        transport = bridge.Transport(network, self.clock)
        for body, headers in (({"account_id": "1", "match_session_id": self.identity[1]}, {}),
                              ({"account_id": self.account, "match_session_id": self.identity[1]},
                               {"Authorization": "Bearer pwa1_" + "e" * 64})):
            with self.assertRaises(ValueError):
                transport.send(self.job("/v1/profile", body, headers))
        network.assert_not_called()

    def test_engine_exactly_once_and_epoch_ack(self):
        files = Files()
        transport = mock.Mock()
        transport.send.return_value = (200, b"OK")
        engine = bridge.Engine("a" * 32, files, transport, self.clock)
        def event(kind, **fields):
            engine.event({"nonce": "a" * 32, "epoch": "sfb_1", "event": kind, **fields})
        try:
            event("ready", protocol=1, tools=False)
            metadata = dict(id=1, method="GET", path="/health", headers=[], bytes=0, chunks=0, timeout_ms=1000)
            event("request", **metadata); event("request", **metadata)
            for _ in range(100):
                engine.tick()
                if files.published:
                    break
                time.sleep(.002)
            self.assertEqual(transport.send.call_count, 1)
            self.assertEqual(len(files.published), 1)
            engine.event({"nonce": "b" * 32, "epoch": "sfb_1", "event": "ack", "serial": 1, "id": 1})
            self.assertIsNotNone(engine.active)
            event("ack", serial=1, id=1)
            self.assertIsNone(engine.active)
            self.assertFalse(engine.jobs)
            self.assertFalse(engine.expiries.heap)
            event("request", **metadata)
            self.assertEqual(transport.send.call_count, 1)
        finally:
            engine.close()

    def test_bad_routes_chunks_and_stale_reply_never_sent(self):
        engine = bridge.Engine("a" * 32, Files(), mock.Mock(), self.clock)
        base = {"nonce": "a" * 32, "epoch": "sfb_1"}
        try:
            engine.event({**base, "event": "ready", "protocol": 1, "tools": False})
            engine.event({**base, "event": "request", "id": 1, "method": "POST", "path": "/v1/../admin",
                          "headers": {}, "bytes": 0, "chunks": 0, "timeout_ms": 1000})
            self.assertFalse(engine.jobs)
            engine.event({**base, "event": "request", "id": 2, "method": "POST", "path": "/v1/profile",
                          "headers": {}, "bytes": 10, "chunks": 1, "timeout_ms": 1000})
            engine.event({**base, "event": "body", "id": 2, "index": 1, "data": base64.b64encode(b"short").decode()})
            self.assertEqual(engine.http_count, 0)
            self.now[0] += 2
            engine.tick()
            self.assertFalse(engine.jobs)
            self.assertEqual(engine.http_count, 0)
        finally:
            engine.close()

    def test_world_reload_with_identical_epoch_gets_fresh_nonce(self):
        files = Files()
        engine = bridge.Engine("a" * 32, files, mock.Mock(), self.clock)
        ready = {"nonce": "a" * 32, "epoch": "same_epoch", "event": "ready", "protocol": 1, "tools": False}
        try:
            engine.event(ready)
            next_nonce = files.next_nonce
            engine.highest = 33
            engine.event(ready)
            self.assertEqual(engine.highest, 33, "duplicate ready must not reset the replay fence")
            engine.event({**ready, "nonce": next_nonce})
            self.assertEqual(engine.highest, 0)
            self.assertNotEqual(files.next_nonce, next_nonce)
            engine.event({**ready, "event": "request", "id": 1, "method": "GET", "path": "/health",
                          "headers": [], "bytes": 0, "chunks": 0, "timeout_ms": 1000})
            self.assertEqual(engine.http_count, 0, "previous world's nonce cannot send in the new world")
            self.assertEqual(engine.nonce, next_nonce)
        finally:
            engine.close()

    def test_indexed_deadlines_bounded_under_10000_completions(self):
        deadlines = bridge.Deadlines()
        generator = random.Random(31)
        expected = {}
        for index in range(10000):
            key, at = generator.randrange(16), generator.randrange(100)
            deadlines.put(at, key); expected[key] = at
            if index % 3 == 0:
                key = generator.randrange(16)
                deadlines.remove(key); expected.pop(key, None)
            self.assertLessEqual(len(deadlines.heap), 16)
            self.assertEqual(len(deadlines.heap), len(expected))
        self.assertEqual(list(deadlines.expired(100)), [key for key, at in sorted(expected.items(), key=lambda item: (item[1], item[0]))])

    def test_response_blocks_bound_console_lines(self):
        # Exercise actual file serialization without touching a Dota installation.
        files = bridge.Files.__new__(bridge.Files)
        files.nonce, files.directory, files.cursor = "a" * 32, Path("virtual"), Path("cursor")
        writes = {}
        files.write = lambda path, data: writes.__setitem__(path, data)
        job = self.job("/v1/profile", {"account_id": self.account})
        raw = bytes(range(256)) * 64
        paths = files.publish(job, 1, 200, raw)
        decoded = []
        for path in paths:
            lines = writes[path].decode().splitlines()
            self.assertLessEqual(len(lines), 17)
            for line in lines:
                self.assertLess(len(line), 390)
                if line.startswith("survival_sfb_chunk "):
                    decoded.append(base64.b64decode(line.split()[-1], validate=True))
        self.assertEqual(b"".join(decoded), raw)
        self.assertEqual(len(paths), 6)


if __name__ == "__main__":
    unittest.main()
