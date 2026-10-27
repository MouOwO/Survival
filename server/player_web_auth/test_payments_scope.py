"""Consenting player grants scope the isolated payment proxy; no real gateway/DB."""
from dataclasses import replace
import hashlib
import http.client
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import patch

from . import test_service as fixtures
from .run import settings_from_environment
from .service import AuthError, PAYMENT_PATHS, PAYMENT_PUBLIC_BASE, PAYMENT_UPSTREAM


class PaymentsScopeTest(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.ServiceTest()
        self.f.setUp()
        self.addCleanup(self.f.tearDown)
        self.f.service.close()
        self.f.settings = replace(self.f.settings, payments_enabled=True, payment_bearer="p" * 64)
        self.f.service = self.f.build()
        self.f.service.forward_payment = self.forward
        self.calls, self.orders = [], {}
        self.response = None

    def approve(self, identity=None, suffix="payment-a"):
        f = self.f
        identity = identity or f.identity
        started = f.start(identity)
        sid, assertion = f.assertion(started, steam=f.settings.accounts[identity["account_id"]], suffix=suffix)
        f.service.callback(assertion, sid, "peer")
        f.service.approve({"code": started["user_code"], "csrf": f.service._derived("csrf:" + sid)},
                          sid, f.settings.origin, "peer")
        grant = f.service.poll(dict(identity, device_code=started["device_code"]), "peer")
        return grant["access_token"]

    def forward(self, path, raw):
        body = json.loads(raw)
        self.calls.append((path, body))
        if self.response is not None:
            return self.response() if callable(self.response) else self.response
        action = path.rsplit("/", 1)[1]
        if action == "catalog":
            result = {"ok": True, "products": [], "categories": [], "test_reset_enabled": True}
        elif action == "create":
            order_id = ("AL" if body.get("provider") == "alipay" else "WX") + hashlib.sha256(raw).hexdigest()[:30]
            result = {"ok": True, "order_id": order_id, "sku": body["sku"], "state": "pending",
                      "amount_fen": 100, "currency": "CNY", "provider": body.get("provider", "wechat"),
                      "qr_matrix": "000|010|000", "quantity": body.get("quantity", 1)}
            result["checkout_url"] = PAYMENT_PUBLIC_BASE + ("/checkout/alipay" if result["provider"] == "alipay" else "/checkout") + "?order=" + order_id + "&token=" + "c" * 64
            self.orders[order_id] = result
        else:
            result = {**self.orders[body["order_id"]], "state": "closed" if action == "cancel" else "delivered"}
        return 200, json.dumps(result).encode()

    def proxy(self, action, token, **values):
        identity = values.pop("identity", self.f.identity)
        status, raw = self.f.service.proxy("/v1/payments/" + action, token, {**identity, **values}, "peer")
        return status, json.loads(raw)

    def assert_code(self, code, call):
        with self.assertRaises(AuthError) as caught:
            call()
        self.assertEqual(caught.exception.code, code)

    def create(self, token, **values):
        return self.proxy("create", token, sku="video_p001", **values)[1]

    def test_default_disabled_returns_noncommercial_catalog_without_revoking_player(self):
        self.f.service.close()
        self.f.settings = replace(self.f.settings, payments_enabled=False, payment_bearer="")
        self.f.service = self.f.build()
        token = self.approve()
        with patch.object(self.f.service, "forward_payment") as forward:
            status, catalog = self.proxy("catalog", token)
            self.assertEqual((status, catalog), (200, {"ok": True, "real_money_enabled": False, "products": [],
                                                      "categories": [], "wechat": False, "alipay": False, "test_reset_enabled": False}))
            for action, fields in (("create", {"sku": "video_p001"}), ("status", {"order_id": "WX" + "a" * 30}),
                                   ("cancel", {"order_id": "WX" + "a" * 30})):
                with self.assertRaises(AuthError) as caught:
                    self.proxy(action, token, **fields)
                self.assertEqual((caught.exception.code, caught.exception.status), ("payments_disabled", 409))
            for path in {"/v1/payments/reset", "/v1/payments/wechat/notify", "/checkout"}:
                self.assert_code("player_route_not_allowed", lambda: self.f.service.proxy(path, token, self.f.identity, "peer"))
            forward.assert_not_called()
        self.assertEqual(self.f.service.principal(token, self.f.identity)["account"], self.f.account)
        _, _, page = self.f.service.page(self.f.start()["user_code"], None)
        self.assertIn("不开放正式排行和真实支付", page.decode())

    def test_disabled_commerce_still_authenticates_identity_expiry_lobby_and_fields(self):
        self.f.service.close()
        self.f.settings = replace(self.f.settings, payments_enabled=False, payment_bearer="")
        self.f.service = self.f.build()
        token = self.approve()
        second_identity = dict(self.f.identity, account_id=str(int(fixtures.STEAMS[1]) - 76561197960265728))
        second = self.approve(second_identity, suffix="disabled-b")
        with patch.object(self.f.service, "forward_payment") as forward:
            self.assert_code("player_session_required", lambda: self.proxy("catalog", "invalid"))
            self.assert_code("player_session_identity_mismatch", lambda: self.proxy("catalog", token, identity=second_identity))
            self.assert_code("player_session_identity_mismatch", lambda: self.proxy("catalog", second))
            self.assert_code("payment_fields_invalid", lambda: self.proxy("catalog", token, sku="video_p001"))
            self.assert_code("payment_fields_invalid", lambda: self.create(token, amount_fen=1))
            self.assert_code("payment_quantity_invalid", lambda: self.create(token, quantity=0))
            lobby = dict(self.f.identity, match_session_id="lobby_disabled_payment")
            lobby_token = self.approve(lobby, suffix="disabled-lobby")
            self.assert_code("player_route_not_allowed", lambda: self.proxy("catalog", lobby_token, identity=lobby))
            self.assert_code("player_session_expired", lambda: self.proxy("catalog", token))
            self.f.now += fixtures.SESSION_TTL + 1
            self.assert_code("player_session_expired", lambda: self.proxy("catalog", second, identity=second_identity))
            forward.assert_not_called()

    def test_enabled_catalog_and_order_status_cancel_protocol(self):
        token = self.approve()
        self.assertFalse(self.proxy("catalog", token)[1]["test_reset_enabled"])
        order = self.create(token, quantity=2, provider="wechat")
        self.assertEqual((order["state"], order["quantity"], order["qr_matrix"]), ("pending", 2, "000|010|000"))
        self.assertEqual(self.proxy("status", token, order_id=order["order_id"])[1]["state"], "delivered")
        self.assertEqual(self.proxy("cancel", token, order_id=order["order_id"])[1]["state"], "closed")
        self.assertEqual([path for path, _ in self.calls], ["/v1/payments/" + x for x in ("catalog", "create", "status", "cancel")])
        for _, body in self.calls:
            self.assertEqual((body["account_id"], body["match_session_id"]),
                             (self.f.account, self.f.identity["match_session_id"]))
        self.assertEqual(self.f.forward_calls, [])

    def test_two_accounts_cannot_read_cancel_or_replace_each_others_identity(self):
        first = self.approve()
        account = str(int(fixtures.STEAMS[1]) - 76561197960265728)
        other = dict(self.f.identity, account_id=account)
        second = self.approve(other, suffix="payment-b")
        one = self.create(first)
        two = self.create(second, identity=other)
        self.assertNotEqual(one["order_id"], two["order_id"])
        for action in ("status", "cancel"):
            self.assert_code("payment_order_not_in_session", lambda: self.proxy(action, second, identity=other, order_id=one["order_id"]))
            self.assert_code("payment_order_not_in_session", lambda: self.proxy(action, first, order_id=two["order_id"]))
        self.assert_code("player_session_identity_mismatch", lambda: self.proxy("catalog", first, identity=other))
        self.assert_code("player_session_identity_mismatch", lambda: self.proxy("catalog", second))
        self.assertEqual(len(self.calls), 2)

    def test_new_match_revokes_old_grant_and_cannot_adopt_old_order(self):
        old = self.approve()
        order = self.create(old)
        other = dict(self.f.identity, match_session_id="next-match-session-123")
        fresh = self.approve(other, suffix="payment-next")
        self.assert_code("player_session_expired", lambda: self.proxy("catalog", old))
        self.assert_code("player_session_identity_mismatch", lambda: self.proxy("catalog", fresh))
        self.assert_code("payment_order_not_in_session", lambda: self.proxy("status", fresh, identity=other, order_id=order["order_id"]))
        self.response = 200, json.dumps(order).encode()
        self.assert_code("payment_order_not_in_session", lambda: self.create(fresh, identity=other))
        binding = self.f.service.db.execute("SELECT account,match_id FROM payment_order_bindings WHERE order_id=?",
                                            (order["order_id"],)).fetchone()
        self.assertEqual(tuple(binding), (self.f.account, self.f.identity["match_session_id"]))

    def test_order_binding_survives_restart(self):
        token = self.approve()
        order = self.create(token)
        self.f.service.close()
        self.f.service = self.f.build()
        self.f.service.forward_payment = self.forward
        self.assertEqual(self.proxy("status", token, order_id=order["order_id"])[1]["state"], "delivered")

    def test_expiry_revocation_and_wrong_bearer_never_call_payment(self):
        token = self.approve()
        self.assert_code("player_session_required", lambda: self.proxy("catalog", "untrusted"))
        self.f.now += fixtures.SESSION_TTL + 1
        self.assert_code("player_session_expired", lambda: self.proxy("catalog", token))
        self.assertEqual(self.calls, [])

    def test_lobby_grant_and_arbitrary_routes_remain_denied_when_enabled(self):
        identity = dict(self.f.identity, match_session_id="lobby_payment_session")
        token = self.approve(identity)
        for path in PAYMENT_PATHS:
            self.assert_code("player_route_not_allowed", lambda: self.f.service.proxy(path, token, identity, "peer"))
        for path in ("/v1/payments/reset", "/v1/payments/create/", "/v1/payments/../profile", "/v1/payments/wechat/notify", "https://evil.invalid"):
            self.assert_code("player_route_not_allowed", lambda: self.f.service.proxy(path, token, identity, "peer"))
        self.assertEqual(self.calls, [])
        _, _, page = self.f.service.page(self.f.start(identity)["user_code"], None)
        self.assertIn("不开放商城和支付", page.decode())
        self.assertIn("不开放正式排行和真实支付", page.decode())

    def test_field_allowlists_disallow_amount_rewards_recipient_and_tokens(self):
        token = self.approve()
        for field, value in (("amount_fen", 1), ("reward", {}), ("account", "42"), ("url", "http://evil.invalid"),
                             ("merchant", "other"), ("payment_bearer", "x"), ("order_id", "WX" + "a" * 30), ("reset", True)):
            with self.subTest(field=field):
                self.assert_code("payment_fields_invalid", lambda: self.create(token, **{field: value}))
        self.assert_code("payment_fields_invalid", lambda: self.proxy("catalog", token, sku="video_p001"))
        self.assert_code("payment_fields_invalid", lambda: self.proxy("create", token))
        self.assertEqual(self.calls, [])

    def test_quantity_provider_sku_and_order_inputs_are_bounded(self):
        token = self.approve()
        for quantity in (True, 0, -1, 101, 1.5, "1", None):
            with self.subTest(quantity=quantity):
                self.assert_code("payment_quantity_invalid", lambda: self.create(token, quantity=quantity))
        for sku in ("abc", "../escape", "x" * 65, None):
            self.assert_code("payment_sku_invalid", lambda: self.proxy("create", token, sku=sku))
        for provider in ("other", None, True):
            self.assert_code("payment_provider_invalid", lambda: self.create(token, provider=provider))
        for order_id in (None, "WX" + "x" * 30, "../order"):
            self.assert_code("payment_order_invalid", lambda: self.proxy("status", token, order_id=order_id))
        self.assertEqual(self.calls, [])
        self.assertEqual(self.create(token, quantity=100)["quantity"], 100)
        self.assertEqual(self.proxy("create", token, sku="u_coin_recharge", quantity=999999)[1]["quantity"], 999999)
        self.assert_code("payment_quantity_invalid", lambda: self.proxy("create", token, sku="u_coin_recharge", quantity=1000000))

    def test_fixed_loopback_uses_only_independent_payment_bearer(self):
        token = self.approve()
        self.f.service.forward_payment = self.f.service._forward_payment
        with patch("player_web_auth.service.fixed_request", return_value=(200, b'{"ok":true,"products":[]}')) as request:
            self.proxy("catalog", token)
        args = request.call_args.args
        self.assertEqual(args[0], PAYMENT_UPSTREAM + "/v1/payments/catalog")
        self.assertEqual(args[2]["Authorization"], "Bearer " + self.f.settings.payment_bearer)
        self.assertNotIn(token, args[1].decode())
        self.assertNotIn(self.f.settings.upstream_bearer, str(args))

    def test_upstream_responses_cannot_expose_configuration_or_secret_strings(self):
        token = self.approve()
        self.response = 200, b'{"ok":true,"products":[],"dsn":"not-public","game_token":"not-public","test_reset_enabled":true}'
        result = self.proxy("catalog", token)[1]
        self.assertNotIn("dsn", result)
        self.assertNotIn("game_token", result)
        self.assertFalse(result["test_reset_enabled"])
        for secret in (self.f.settings.payment_bearer, self.f.settings.upstream_bearer, self.f.settings.secret, token):
            self.response = 200, json.dumps({"ok": True, "products": [{"description": secret}]}).encode()
            self.assert_code("payment_upstream_response_invalid", lambda: self.proxy("catalog", token))
        escaped = "".join("\\u%04x" % ord(c) for c in self.f.settings.payment_bearer)
        self.response = 200, ('{"ok":true,"products":[{"description":"' + escaped + '"}]}').encode()
        self.assert_code("payment_upstream_response_invalid", lambda: self.proxy("catalog", token))

    def test_checkout_capabilities_require_exact_ws4_origin_path_order_and_token(self):
        token = self.approve()
        order = self.create(token)
        good = order["checkout_url"]
        bad = [good.replace("/ws4-payments", ""), good.replace("https:", "http:"),
               good.replace("pay.xiaofengnet.com", "evil.invalid"), good.replace("/checkout?", "/checkout/alipay?"),
               good.replace(order["order_id"], "WX" + "d" * 30), good + "&extra=1", good + "#fragment",
               good + "&order=" + order["order_id"], good.replace("c" * 64, "invalid-token"), good + "\n"]
        for value in bad:
            with self.subTest(url=value):
                self.response = 200, json.dumps({**order, "checkout_url": value}).encode()
                self.assert_code("payment_upstream_response_invalid", lambda: self.proxy("status", token, order_id=order["order_id"]))
        self.response = None
        alipay = self.create(token, provider="alipay")
        self.assertIn("/ws4-payments/checkout/alipay?", alipay["checkout_url"])

    def test_upstream_malformed_ambiguous_redirect_and_oversized_replies_are_closed(self):
        token = self.approve()
        for response in ((302, b'{}'), (409, b'{"ok":true}'), (200, b'{"ok":true,"ok":false}'), (200, b'{"ok":true,"amount":NaN}'),
                         (200, b'{"ok":true,"products":[{"amount_fen":1e999}]}'),
                         (200, b'[]'), (200, b'{"ok":1}'), (200, b'not-json'), (200, b'x' * (8 * 1024 * 1024 + 1))):
            with self.subTest(status=response[0], length=len(response[1])):
                self.response = response
                self.assert_code("payment_upstream_response_invalid", lambda: self.proxy("catalog", token))
        self.response = 409, b'{"ok":false,"error":"match_session_missing","private":"drop"}'
        self.assertEqual(self.proxy("catalog", token), (409, {"ok": False, "error": "match_session_missing", "test_reset_enabled": False}))

    def test_grant_rechecks_after_slow_upstream_before_exposing_order(self):
        token = self.approve()
        def late():
            self.f.now += fixtures.SESSION_TTL + 1
            return 200, b'{"ok":true,"order_id":"WXaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sku":"video_p001"}'
        self.response = late
        self.assert_code("player_session_expired", lambda: self.create(token))
        self.assertEqual(self.f.service.db.execute("SELECT count(*) FROM payment_order_bindings").fetchone()[0], 0)

    def test_enabled_page_discloses_payment_scope_without_configuration(self):
        started = self.f.start()
        _, _, raw = self.f.service.page(started["user_code"], None)
        self.assertIn("本账号、本局", raw.decode())
        self.assertIn("真实支付订单", raw.decode())
        self.assertNotIn("不开放正式排行和真实支付", raw.decode())
        for private in (self.f.settings.payment_bearer, self.f.settings.upstream_bearer, self.f.settings.secret):
            self.assertNotIn(private.encode(), raw)

    def test_http_routes_preserve_json_protocol_and_deny_injected_fields(self):
        token = self.approve()
        server = fixtures.BoundedServer(("127.0.0.1", 0), fixtures.handler(self.f.service))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def request(action, body, bearer=token):
            connection = http.client.HTTPConnection(*server.server_address, timeout=3)
            try:
                connection.request("POST", "/v1/payments/" + action, json.dumps(body),
                                   {"Content-Type": "application/json", "Authorization": "Bearer " + bearer})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()
        try:
            self.assertEqual(request("catalog", self.f.identity)[0], 200)
            status, order = request("create", {**self.f.identity, "sku": "video_p001", "quantity": 2})
            self.assertEqual((status, order["quantity"]), (200, 2))
            body = {**self.f.identity, "order_id": order["order_id"]}
            self.assertEqual(request("status", body)[1]["state"], "delivered")
            self.assertEqual(request("cancel", body)[1]["state"], "closed")
            self.assertEqual(request("create", {**self.f.identity, "sku": "video_p001", "amount_fen": 1}),
                             (400, {"ok": False, "error": "payment_fields_invalid"}))
            self.assertEqual(request("catalog", self.f.identity, "invalid"),
                             (403, {"ok": False, "error": "player_session_required"}))
            self.assertEqual(request("reset", self.f.identity),
                             (403, {"ok": False, "error": "player_route_not_allowed"}))
            self.assertEqual(len(self.calls), 4)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


class PaymentsSettingsTest(unittest.TestCase):
    def setUp(self):
        self.settings = fixtures.Settings(Path("not-opened.sqlite3"), "a" * 64, "b" * 64, fixtures.STEAMS)

    def test_default_is_disabled_and_explicit_enable_requires_independent_configuration(self):
        self.settings.validate()
        self.assertFalse(self.settings.payments_enabled)
        for bearer in ("", None, "short", "a" * 64, "b" * 64, "pwa1_" + "c" * 64, "x" * 32 + "\n"):
            with self.subTest(bearer_type=type(bearer).__name__):
                with self.assertRaisesRegex(ValueError, "independent_payment_bearer_required"):
                    replace(self.settings, payments_enabled=True, payment_bearer=bearer).validate()
        valid = replace(self.settings, payments_enabled=True, payment_bearer="p" * 64)
        valid.validate()
        self.assertNotIn("p" * 64, repr(valid))
        for upstream in ("http://127.0.0.1:8766", "http://127.0.0.1:18766", "http://localhost:18769", "https://evil.invalid", PAYMENT_UPSTREAM + "/"):
            with self.assertRaisesRegex(ValueError, "isolated_payment_loopback_required"):
                replace(valid, payment_upstream=upstream).validate()
        with self.assertRaisesRegex(ValueError, "payments_enabled_invalid"):
            replace(valid, payments_enabled=1).validate()

    def test_environment_is_explicit_and_never_reuses_existing_upstream_key(self):
        env = {"PLAYER_WEB_AUTH_DATABASE": "not-opened.sqlite3", "PLAYER_WEB_AUTH_SECRET": "a" * 64,
               "PLAYER_WEB_AUTH_UPSTREAM_BEARER": "b" * 64, "PLAYER_WEB_AUTH_STEAM_IDS": ",".join(fixtures.STEAMS)}
        default = settings_from_environment(env)
        default.validate()
        self.assertFalse(default.payments_enabled)
        self.assertEqual(default.payment_bearer, "")
        for flag in ("yes", "true", "2", ""):
            with self.assertRaisesRegex(ValueError, "payments_enabled_invalid"):
                settings_from_environment({**env, "PLAYER_WEB_AUTH_PAYMENTS_ENABLED": flag})
        with self.assertRaisesRegex(ValueError, "independent_payment_bearer_required"):
            settings_from_environment({**env, "PLAYER_WEB_AUTH_PAYMENTS_ENABLED": "1"}).validate()
        ready = settings_from_environment({**env, "PLAYER_WEB_AUTH_PAYMENTS_ENABLED": "1",
                                          "PLAYER_WEB_AUTH_PAYMENT_BEARER": "p" * 64,
                                          "PLAYER_WEB_AUTH_PAYMENT_UPSTREAM": PAYMENT_UPSTREAM})
        ready.validate()
        self.assertTrue(ready.payments_enabled)


if __name__ == "__main__":
    unittest.main()
