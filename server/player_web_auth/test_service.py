"""Trust-boundary tests; no Steam service, real account, or WS4 database is used."""
from dataclasses import replace
from datetime import datetime, timezone
import http.client
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import sqlite3
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.parse import parse_qs, urlencode, urlsplit
from unittest.mock import patch

from .http_api import BoundedServer, handler, strict_pairs
from .run import settings_from_environment
from .service import (AuthError, BODY_LIMIT, OPENID_NS, PENDING_TTL, SESSION_TTL,
                      STEAM_ENDPOINT, Service, Settings, fixed_request, steam_check)


STEAMS = ("76561198424163156", "76561198845461206", "76561198104787442", "76561198974301984")


class ServiceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.now = 1792760000
        self.forward_calls = []
        self.verifications = []
        self.settings = Settings(Path(self.temp.name) / "auth.sqlite3", "a" * 64, "b" * 64, STEAMS)
        self.service = self.build()
        self.account = str(int(STEAMS[0]) - 76561197960265728)
        self.identity = {"account_id": self.account, "match_session_id": "test-match-session-123"}

    def build(self, settings=None):
        def forward(path, raw):
            self.forward_calls.append((path, json.loads(raw)))
            return 200, b'{"ok":true}'
        def verify(fields):
            self.verifications.append(fields)
            return True
        return Service(settings or self.settings, clock=lambda: self.now, verify_steam=verify, forward=forward)

    def tearDown(self):
        self.service.close()
        self.temp.cleanup()

    def fail_code(self, code, call):
        with self.assertRaises(AuthError) as caught:
            call()
        self.assertEqual(caught.exception.code, code)

    def start(self, identity=None):
        return self.service.start(identity or self.identity, "peer")

    def assertion(self, started, sid=None, *, steam=None, suffix="nonce-a"):
        sid, location = self.service.login(started["user_code"], sid, "peer")
        returned = parse_qs(urlsplit(location).query)["openid.return_to"][0]
        state = parse_qs(urlsplit(returned).query)["state"][0]
        claimed = "https://steamcommunity.com/openid/id/" + (steam or STEAMS[0])
        stamp = datetime.fromtimestamp(self.now, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        fields = {"state": state, "openid.ns": OPENID_NS, "openid.mode": "id_res",
                  "openid.op_endpoint": STEAM_ENDPOINT, "openid.return_to": returned,
                  "openid.claimed_id": claimed, "openid.identity": claimed,
                  "openid.response_nonce": stamp + suffix, "openid.assoc_handle": "association",
                  "openid.signed": "op_endpoint,claimed_id,identity,return_to,response_nonce,assoc_handle",
                  "openid.sig": "valid-only-in-injected-test-verifier"}
        return sid, fields

    def approved(self, identity=None, *, suffix="nonce-a"):
        started = self.start(identity)
        sid, fields = self.assertion(started, suffix=suffix)
        self.service.callback(fields, sid, "peer")
        self.service.approve({"code": started["user_code"], "csrf": self.service._derived("csrf:" + sid)},
                             sid, self.settings.origin, "peer")
        poll = dict(identity or self.identity, device_code=started["device_code"])
        return started, self.service.poll(poll, "peer"), poll

    def test_start_contains_only_public_verification_code_in_url(self):
        result = self.start()
        self.assertEqual(result["verification_uri"], self.settings.public_base + "/authorize?code=" + result["user_code"])
        self.assertNotIn(result["device_code"], result["verification_uri"])
        self.assertEqual(result["expires_in"], 600)
        self.assertEqual(self.service.poll(dict(self.identity, device_code=result["device_code"]), "peer")["status"], "pending")

    def test_fifth_account_and_unexpected_fields_rejected(self):
        self.fail_code("test_account_not_allowed", lambda: self.start(dict(self.identity, account_id="42")))
        self.fail_code("test_account_not_allowed", lambda: self.start(dict(self.identity, admin=True)))

    def test_poll_identity_binding_and_rate(self):
        started = self.start()
        poll = dict(self.identity, device_code=started["device_code"])
        self.fail_code("device_code_invalid", lambda: self.service.poll(dict(poll, match_session_id="wrong-session-123"), "peer"))
        other = str(int(STEAMS[1]) - 76561197960265728)
        self.fail_code("device_code_invalid", lambda: self.service.poll(dict(poll, account_id=other), "peer"))
        self.service.poll(poll, "peer")
        self.fail_code("slow_down", lambda: self.service.poll(poll, "peer"))
        self.now += 3
        self.assertEqual(self.service.poll(poll, "peer")["status"], "pending")

    def test_pending_expiry(self):
        started = self.start()
        self.now += PENDING_TTL
        self.fail_code("device_code_expired", lambda: self.service.poll(dict(self.identity, device_code=started["device_code"]), "peer"))

    def test_steam_state_requires_original_browser_and_is_single_use(self):
        started = self.start()
        sid, fields = self.assertion(started)
        self.fail_code("steam_state_invalid", lambda: self.service.callback(fields, "x" * 43, "peer"))
        self.assertEqual(self.service.callback(fields, sid, "peer"), started["user_code"])
        self.fail_code("steam_state_invalid", lambda: self.service.callback(fields, sid, "peer"))
        self.assertEqual(len(self.verifications), 1)

    def test_wrong_return_to_or_provider_never_reaches_steam_verifier(self):
        started = self.start()
        for changed in ({"openid.return_to": "https://evil.invalid/"},
                        {"openid.op_endpoint": "https://evil.invalid/openid"},
                        {"openid.signed": "claimed_id,identity,return_to,response_nonce,assoc_handle"},
                        {"openid.mode": "cancel"}):
            sid, fields = self.assertion(started)
            fields.update(changed)
            self.fail_code("steam_assertion_invalid", lambda: self.service.callback(fields, sid, "peer"))
        self.assertFalse(self.verifications)

    def test_claimed_identity_must_match_exact_official_url(self):
        started = self.start()
        for changed in ({"openid.identity": "https://steamcommunity.com/openid/id/" + STEAMS[1]},
                        {"openid.claimed_id": "http://steamcommunity.com/openid/id/" + STEAMS[0]}):
            sid, fields = self.assertion(started)
            fields.update(changed)
            self.fail_code("steam_identity_invalid", lambda: self.service.callback(fields, sid, "peer"))
        self.assertFalse(self.verifications)

    def test_steam_rejected_assertion_does_not_login(self):
        started = self.start()
        sid, fields = self.assertion(started)
        self.service.verify_steam = lambda fields: False
        self.fail_code("steam_assertion_rejected", lambda: self.service.callback(fields, sid, "peer"))
        self.fail_code("steam_login_required", lambda: self.service.approve(
            {"code": started["user_code"], "csrf": self.service._derived("csrf:" + sid)}, sid, self.settings.origin, "peer"))

    def test_nonce_freshness_and_replay_across_different_flows(self):
        started = self.start()
        sid, fields = self.assertion(started)
        self.service.callback(fields, sid, "peer")
        sid2, fields2 = self.assertion(started)
        self.fail_code("steam_nonce_replayed", lambda: self.service.callback(fields2, sid2, "peer"))
        for offset in (-301, 31):
            sid3, fields3 = self.assertion(started)
            fields3["openid.response_nonce"] = datetime.fromtimestamp(self.now + offset, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") + "fresh"
            self.fail_code("steam_nonce_expired", lambda: self.service.callback(fields3, sid3, "peer"))

    def test_approval_requires_explicit_csrf_and_origin(self):
        started = self.start()
        sid, fields = self.assertion(started)
        self.service.callback(fields, sid, "peer")
        values = {"code": started["user_code"], "csrf": self.service._derived("csrf:" + sid)}
        self.fail_code("origin_rejected", lambda: self.service.approve(values, sid, None, "peer"))
        self.fail_code("origin_rejected", lambda: self.service.approve(values, sid, "https://evil.invalid", "peer"))
        self.fail_code("csrf_rejected", lambda: self.service.approve(dict(values, csrf="forged"), sid, self.settings.origin, "peer"))
        self.assertEqual(self.service.poll(dict(self.identity, device_code=started["device_code"]), "peer")["status"], "pending")

    def test_steam_login_alone_does_not_authorize_and_account_must_match(self):
        started = self.start()
        sid, fields = self.assertion(started, steam=STEAMS[1])
        self.service.callback(fields, sid, "peer")
        self.fail_code("steam_account_mismatch", lambda: self.service.approve(
            {"code": started["user_code"], "csrf": self.service._derived("csrf:" + sid)}, sid, self.settings.origin, "peer"))
        self.assertEqual(self.service.poll(dict(self.identity, device_code=started["device_code"]), "peer")["status"], "pending")

    def test_approved_poll_is_retry_safe_and_secret_material_not_persisted(self):
        started, approved, poll = self.approved()
        second = self.service.poll(poll, "peer")
        self.assertEqual(approved["access_token"], second["access_token"])
        self.assertNotEqual(approved["access_token"], self.settings.upstream_bearer)
        stored = self.settings.database.read_bytes()
        for secret in (started["device_code"], approved["access_token"], self.settings.secret, self.settings.upstream_bearer):
            self.assertNotIn(secret.encode(), stored)

    def test_persistent_restart_preserves_nonce_replay_and_retry_safe_session(self):
        _, approved, poll = self.approved()
        self.service.close()
        self.service = self.build()
        self.assertEqual(self.service.poll(poll, "peer")["access_token"], approved["access_token"])
        self.service.proxy("/v1/profile", approved["access_token"], self.identity, "peer")
        self.assertEqual(len(self.forward_calls), 1)

    def test_cross_account_cross_match_and_expired_sessions_never_forward(self):
        _, approved, _ = self.approved()
        token = approved["access_token"]
        other = str(int(STEAMS[1]) - 76561197960265728)
        for payload in (dict(self.identity, account_id=other), dict(self.identity, match_session_id="other-match-123")):
            self.fail_code("player_session_identity_mismatch", lambda: self.service.proxy("/v1/profile", token, payload, "peer"))
        self.now += SESSION_TTL
        self.fail_code("player_session_expired", lambda: self.service.proxy("/v1/profile", token, self.identity, "peer"))
        self.assertFalse(self.forward_calls)

    def test_new_approval_revokes_previous_account_session_but_start_does_not(self):
        _, first, _ = self.approved()
        second_identity = dict(self.identity, match_session_id="second-match-session-123")
        self.start(second_identity)
        self.service.proxy("/v1/profile", first["access_token"], self.identity, "peer")
        _, second, _ = self.approved(second_identity, suffix="nonce-b")
        self.fail_code("player_session_expired", lambda: self.service.proxy("/v1/profile", first["access_token"], self.identity, "peer"))
        self.service.proxy("/v1/profile", second["access_token"], second_identity, "peer")

    def test_default_does_not_expose_battle_payment_rank_or_arbitrary_proxy(self):
        _, approved, _ = self.approved()
        for path in ("/v1/archive/command", "/v1/rewards/grant", "/v1/payments/create", "/v1/archive/endless-leaderboard",
                     "/v1/archive/endless-batch", "/v1/online-time/checkpoint", "/admin/pins", "https://evil.invalid/"):
            self.fail_code("player_route_not_allowed", lambda: self.service.proxy(path, approved["access_token"], self.identity, "peer"))
        self.assertFalse(self.forward_calls)

    def test_isolated_progress_flag_allows_only_fixed_extra_paths(self):
        self.service.close()
        self.service = self.build(replace(self.settings, isolated_local_progress=True))
        _, approved, _ = self.approved()
        self.assertTrue(approved["local_progress_unverified"])
        self.service.proxy("/v1/archive/command", approved["access_token"], dict(self.identity, command={"kind": "boss_kill"}), "peer")
        self.fail_code("player_route_not_allowed", lambda: self.service.proxy("/v1/payments/create", approved["access_token"], self.identity, "peer"))
        self.fail_code("player_route_not_allowed", lambda: self.service.proxy("/v1/archive/endless-leaderboard", approved["access_token"], self.identity, "peer"))
        self.fail_code("player_route_not_allowed", lambda: self.service.proxy("/v1/rewards/grant", approved["access_token"], self.identity, "peer"))
        self.assertEqual(len(self.forward_calls), 1)

    def test_consent_page_hides_raw_match_and_full_account_identifiers(self):
        started = self.start()
        _, _, page = self.service.page(started["user_code"], None)
        for private in (self.identity["match_session_id"], self.account, STEAMS[0]):
            self.assertNotIn(private.encode(), page)
        self.assertIn(started["user_code"].encode(), page)
        self.assertIn("不能上传战斗进度".encode(), page)
        self.service.close()
        self.service = self.build(replace(self.settings, isolated_local_progress=True))
        _, _, page = self.service.page(started["user_code"], None)
        self.assertIn("读取并保存".encode(), page)
        self.assertNotIn("不能上传战斗进度".encode(), page)

    def test_start_rate_limit_survives_restart(self):
        for _ in range(8):
            self.start()
        self.service.close()
        self.service = self.build()
        self.fail_code("rate_limited", self.start)

    def test_body_limit_prevents_upstream_forward(self):
        _, approved, _ = self.approved()
        self.fail_code("request_body_too_large", lambda: self.service.proxy(
            "/v1/profile", approved["access_token"], dict(self.identity, oversized="x" * BODY_LIMIT), "peer"))
        self.assertFalse(self.forward_calls)

    def test_steam_check_uses_fixed_https_and_requires_complete_positive_answer(self):
        with patch("player_web_auth.service.fixed_request", return_value=(200, ("ns:" + OPENID_NS + "\nis_valid:true\n").encode())) as request:
            self.assertTrue(steam_check({"openid.mode": "id_res", "state": "not-forwarded", "openid.op_endpoint": "https://evil.invalid"}))
            args = request.call_args[0]
            self.assertEqual(args[0], STEAM_ENDPOINT)
            outgoing = parse_qs(args[1].decode())
            self.assertEqual(outgoing["openid.mode"], ["check_authentication"])
            self.assertNotIn("state", outgoing)
        for body in (b"is_valid:true\n", b"ns:x\nis_valid:true\n", b"is_valid:true\nis_valid:false\n", b"garbage"):
            with patch("player_web_auth.service.fixed_request", return_value=(200, body)):
                self.assertFalse(steam_check({"openid.mode": "id_res"}))

    def test_settings_fail_closed_on_nonisolated_routing_and_weak_secret(self):
        for fields in ({"upstream": "http://evil.invalid:18765"}, {"bind": "0.0.0.0"},
                       {"steam_ids": STEAMS[:3]}, {"secret": "test"},
                       {"public_base": "http://pay.xiaofengnet.com/ws4-web"}):
            with self.assertRaises(ValueError):
                replace(self.settings, **fields).validate()
        with self.assertRaises(ValueError):
            settings_from_environment({"ISOLATED_LOCAL_PROGRESS": "true"})


class HttpTest(unittest.TestCase):
    build = ServiceTest.build
    start = ServiceTest.start

    def setUp(self):
        ServiceTest.setUp(self)
        self.http = BoundedServer(("127.0.0.1", 0), handler(self.service))
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join()
        ServiceTest.tearDown(self)

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.http.server_address[1], timeout=5)
        connection.request(method, path, body, headers or {})
        response = connection.getresponse()
        status, result, outgoing = response.status, response.read(), dict(response.getheaders())
        connection.close()
        return status, result, outgoing

    def test_http_body_size_duplicate_json_and_query_fields(self):
        status, result, _ = self.request("POST", "/v1/player-auth/start", "x" * (BODY_LIMIT + 1), {"Content-Type": "application/json"})
        self.assertEqual((status, json.loads(result)["error"]), (413, "request_body_too_large"))
        duplicate = '{"account_id":"' + self.account + '","account_id":"42","match_session_id":"some-session-123"}'
        self.assertEqual(self.request("POST", "/v1/player-auth/start", duplicate, {"Content-Type": "application/json"})[0], 400)
        self.assertEqual(self.request("GET", "/authorize?code=AAAAAAAA&code=BBBBBBBB")[0], 400)

    def test_http_security_headers_and_secure_cookie(self):
        started = self.start()
        status, page, headers = self.request("GET", "/authorize?code=" + started["user_code"])
        self.assertEqual(status, 200)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["Referrer-Policy"], "no-referrer")
        self.assertIn("Secure; HttpOnly; SameSite=Lax", headers["Set-Cookie"])
        self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])
        self.assertNotIn(self.settings.secret.encode(), page)
        self.assertNotIn(started["device_code"].encode(), page)

    def test_http_callback_rejects_invalid_state_without_exposing_query(self):
        status, body, _ = self.request("GET", "/steam/callback?state=" + "x" * 43 + "&openid.sig=private-signature")
        self.assertEqual(status, 403)
        self.assertNotIn(b"private-signature", body)
        self.assertNotIn(b"Traceback", body)

    def test_http_health_and_no_auth_proxy(self):
        status, body, _ = self.request("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["kind"], "WS4-PLAYER-WEB-AUTH-1")
        status, _, _ = self.request("POST", "/v1/profile", json.dumps(self.identity), {"Content-Type": "application/json"})
        self.assertEqual(status, 403)
        self.assertFalse(self.forward_calls)

    def test_http_forwarded_single_ips_get_separate_peer_quotas(self):
        started = self.start()
        with patch.object(self.service, "rate", wraps=self.service.rate) as rate:
            for address in ("198.51.100.10", "2001:db8::10"):
                status, _, _ = self.request("GET", "/authorize?code=" + started["user_code"], headers={"X-Forwarded-For": address})
                self.assertEqual(status, 200)
            peers = {call.args[1] for call in rate.call_args_list if call.args[0] == "authorize-page"}
            self.assertEqual(peers, {"198.51.100.10", "2001:db8::10"})
            self.assertTrue(any(call.args[:2] == ("global-http", "all") for call in rate.call_args_list))

    def test_http_rejects_multivalue_duplicate_or_invalid_forwarded_ips(self):
        for address in ("198.51.100.10, 198.51.100.11", "not-an-ip", "fe80::1%test"):
            status, raw, _ = self.request("GET", "/health", headers={"X-Forwarded-For": address})
            self.assertEqual((status, json.loads(raw)["error"]), (400, "forwarded_address_invalid"))
        connection = http.client.HTTPConnection("127.0.0.1", self.http.server_address[1], timeout=5)
        connection.putrequest("GET", "/health")
        connection.putheader("X-Forwarded-For", "198.51.100.10")
        connection.putheader("X-Forwarded-For", "198.51.100.11")
        connection.endheaders()
        response = connection.getresponse()
        self.assertEqual(response.status, 400)
        response.read()
        connection.close()

    def test_http_database_errors_are_fixed_503_responses(self):
        with patch.object(self.service, "rate", side_effect=sqlite3.OperationalError("private database path and query")):
            status, raw, _ = self.request("GET", "/health")
            self.assertEqual((status, json.loads(raw)["error"]), (503, "authentication_unavailable"))
            self.assertNotIn(b"private", raw)
            status, raw, _ = self.request("POST", "/v1/profile", json.dumps(self.identity), {"Content-Type": "application/json"})
            self.assertEqual(status, 503)
            self.assertNotIn(b"private", raw)

    def test_complete_browser_consent_and_game_poll_over_http(self):
        status, raw, _ = self.request("POST", "/v1/player-auth/start", json.dumps(self.identity), {"Content-Type": "application/json"})
        self.assertEqual(status, 200)
        started = json.loads(raw)
        _, _, page_headers = self.request("GET", "/authorize?code=" + started["user_code"])
        cookie = page_headers["Set-Cookie"].split(";", 1)[0]
        status, _, login_headers = self.request("GET", "/steam/login?code=" + started["user_code"], headers={"Cookie": cookie})
        self.assertEqual(status, 303)
        self.assertTrue(login_headers["Location"].startswith(STEAM_ENDPOINT + "?"))
        returned = parse_qs(urlsplit(login_headers["Location"]).query)["openid.return_to"][0]
        fields = {"state": parse_qs(urlsplit(returned).query)["state"][0], "openid.ns": OPENID_NS,
                  "openid.mode": "id_res", "openid.op_endpoint": STEAM_ENDPOINT,
                  "openid.return_to": returned, "openid.claimed_id": "https://steamcommunity.com/openid/id/" + STEAMS[0],
                  "openid.identity": "https://steamcommunity.com/openid/id/" + STEAMS[0],
                  "openid.response_nonce": datetime.fromtimestamp(self.now, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") + "http-flow",
                  "openid.assoc_handle": "association", "openid.sig": "test-signature",
                  "openid.signed": "op_endpoint,claimed_id,identity,return_to,response_nonce,assoc_handle"}
        self.assertEqual(self.request("GET", "/steam/callback?" + urlencode(fields), headers={"Cookie": cookie})[0], 303)
        sid = cookie.split("=", 1)[1]
        status, _, _ = self.request("POST", "/authorize",
                                   urlencode({"code": started["user_code"], "csrf": self.service._derived("csrf:" + sid)}),
                                   {"Content-Type": "application/x-www-form-urlencoded", "Cookie": cookie, "Origin": self.settings.origin})
        self.assertEqual(status, 200)
        status, raw, _ = self.request("POST", "/v1/player-auth/poll", json.dumps(dict(self.identity, device_code=started["device_code"])),
                                     {"Content-Type": "application/json"})
        self.assertEqual(status, 200)
        token = json.loads(raw)["access_token"]
        status, _, _ = self.request("POST", "/v1/profile", json.dumps(self.identity),
                                   {"Content-Type": "application/json", "Authorization": "Bearer " + token})
        self.assertEqual(status, 200)
        self.assertEqual(len(self.forward_calls), 1)


class FixedNetworkTest(unittest.TestCase):
    def test_redirects_are_not_followed_and_response_size_is_bounded(self):
        targets = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_POST(self):
                if self.path == "/redirect":
                    self.send_response(302)
                    self.send_header("Location", "/target")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                else:
                    targets.append(self.path)
                    self.send_response(200)
                    self.send_header("Content-Length", "100")
                    self.end_headers()
                    self.wfile.write(b"x" * 100)
        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = "http://127.0.0.1:" + str(server.server_address[1])
            status, _ = fixed_request(base + "/redirect", b"", {}, 16)
            self.assertEqual(status, 302)
            self.assertFalse(targets)
            with self.assertRaises(AuthError) as caught:
                fixed_request(base + "/oversized", b"", {}, 16)
            self.assertEqual(caught.exception.code, "upstream_response_too_large")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
