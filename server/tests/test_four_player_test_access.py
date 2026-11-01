"""Four-account admission against the actual shared FishingApplication boundary."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import hmac
import os
from pathlib import Path
import sys
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
if os.environ.get("FISHING_BACKEND_ROOT"):
    sys.path.insert(0, os.environ["FISHING_BACKEND_ROOT"])
sys.path.insert(0, str(ROOT / "server"))

from archive_backend.test_access import (ENVIRONMENT_NAME, STEAM_INDIVIDUAL_BASE,
                                         TestAccountPolicy, install)
from fishing_api.application import ApiError, FishingApplication


def setting(*accounts):
    return {ENVIRONMENT_NAME: ",".join(str(STEAM_INDIVIDUAL_BASE + value) for value in accounts)}


class RpcRecorder:
    def __init__(self):
        self.calls = []
        self.lock = threading.Lock()

    def rpc(self, name, payload):
        with self.lock:
            self.calls.append((name, dict(payload)))
        if name == "get_fishing_profile":
            return {"account_id": payload["p_account_id"], "revision": 1, "save": {}}
        return {"ok": True}


class FourPlayerAccessTests(unittest.TestCase):
    def setUp(self):
        self.rpc = RpcRecorder()
        self.app = FishingApplication("fixture-token", "fixture-account-pepper", None, self.rpc)

    def test_unset_or_blank_keeps_existing_access(self):
        for env in ({}, {ENVIRONMENT_NAME: " \t"}):
            with self.subTest(env=env):
                before = self.app._database_account_id("999")
                self.assertIsNone(install(self.app, env))
                self.assertEqual(self.app.profile({"account_id": "999"})["account_id"], "999")
                self.assertEqual(before, self.app._database_account_id("999"))

    def test_four_concurrent_profiles_preserve_identity_and_isolation(self):
        install(self.app, setting(100, 101, 102, 103))
        accounts = ["100", "101", "102", "103"]
        with ThreadPoolExecutor(max_workers=4) as pool:
            profiles = list(pool.map(lambda account: self.app.profile({"account_id": account}), accounts))
        self.assertEqual([value["account_id"] for value in profiles], accounts)
        expected = {hmac.new(b"fixture-account-pepper", account.encode(), hashlib.sha256).hexdigest()
                    for account in accounts}
        actual = {payload["p_account_id"] for name, payload in self.rpc.calls
                  if name == "get_fishing_profile"}
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), 4)

    def test_outsider_cannot_read_or_initialize_a_profile(self):
        install(self.app, setting(100, 101, 102, 103))
        with self.assertRaises(ApiError) as rejected:
            self.app.profile({"account_id": "104"})
        self.assertEqual((rejected.exception.code, rejected.exception.status),
                         ("test_account_not_allowed", 403))
        self.assertEqual(self.rpc.calls, [])

    def test_fifth_account_requires_explicit_configuration_and_sixth_stays_denied(self):
        added = str(76561198296534615 - STEAM_INDIVIDUAL_BASE)
        self.assertEqual(added, "336268887")
        install(self.app, setting(100, 101, 102, 103))
        with self.assertRaises(ApiError):
            self.app.profile({"account_id": added})
        self.assertEqual(self.rpc.calls, [])

        extended = FishingApplication("fixture-token", "fixture-account-pepper", None, self.rpc)
        install(extended, setting(100, 101, 102, 103, int(added)))
        for account in ("100", "101", "102", "103", added):
            self.assertEqual(extended.profile({"account_id": account})["account_id"], account)
        expected = hmac.new(b"fixture-account-pepper", added.encode(), hashlib.sha256).hexdigest()
        self.assertEqual(self.rpc.calls[-1][1]["p_account_id"], expected)
        before = len(self.rpc.calls)
        with self.assertRaises(ApiError) as rejected:
            extended.profile({"account_id": "336268888"})
        self.assertEqual((rejected.exception.code, rejected.exception.status),
                         ("test_account_not_allowed", 403))
        self.assertEqual(len(self.rpc.calls), before)

    def test_outsider_reward_and_online_checkpoint_rejected_before_rpc(self):
        install(self.app, setting(100, 101, 102, 103))
        reward = dict(account_id="104", grant_id="00000000-0000-0000-0000-000000000001",
                      reward_id="fixture_reward", definition_version=1, amount=1)
        checkpoint = dict(account_id="104", session_id="fixture-session", request_id="fixture-request",
                          elapsed_seconds=1, definition_version=1, final=False)
        for method, payload in ((self.app.grant_out_of_match_reward, reward),
                                (self.app.online_checkpoint, checkpoint)):
            with self.subTest(method=method.__name__):
                with self.assertRaises(ApiError) as rejected:
                    method(payload)
                self.assertEqual(rejected.exception.code, "test_account_not_allowed")
        self.assertEqual(self.rpc.calls, [])

    def test_invalid_opt_in_fails_without_changing_application(self):
        for env in (setting(1, 2, 3), setting(1, 2, 3, 4, 5, 6), setting(1, 2, 3, 3),
                    setting(1, 2, 3, 4, 4), setting(1, 2, 3, 4, 0),
                    setting(0, 2, 3, 4), setting(4294967296, 2, 3, 4),
                    {ENVIRONMENT_NAME: "1,2,3,4"}, {ENVIRONMENT_NAME: "invalid"}):
            with self.subTest(env=env):
                original = self.app._database_account_id
                with self.assertRaises(ValueError):
                    install(self.app, env)
                self.assertEqual(self.app._database_account_id, original)
                self.assertFalse(hasattr(self.app, "_survival_test_access_policy"))

    def test_startup_accepts_configured_four_or_five_and_rejects_six_before_database_builder(self):
        from workshop_test import run_api
        settings = SimpleNamespace(database_backend="postgres", host="127.0.0.1", port=18765,
            postgres_dsn="postgresql://fixture@127.0.0.1:15432/goufayu_ws4", payment_mode="test",
            http_client_timeout_seconds=5, http_request_deadline_seconds=10, http_max_concurrency=4)
        for members in ((100, 101, 102, 103), (100, 101, 102, 103, 336268887),
                        (100, 101, 102, 103, 336268887, 336268888)):
            app = FishingApplication("fixture-token", "fixture-account-pepper", None, self.rpc)
            with self.subTest(count=len(members)), patch.dict(os.environ, setting(*members), clear=True), \
                    patch.object(run_api.Settings, "from_env", return_value=settings), \
                    patch.object(run_api, "build_application", return_value=app) as builder, \
                    patch.object(run_api, "Policy"), patch.object(run_api, "make_handler"), \
                    patch.object(run_api, "handler"), patch.object(run_api, "BoundedThreadingHTTPServer") as server:
                result = run_api.main()
                if len(members) == 6:
                    self.assertEqual(result, 2)
                    builder.assert_not_called()
                    server.assert_not_called()
                else:
                    self.assertEqual(result, 0)
                    builder.assert_called_once_with(settings)
                    server.return_value.serve_forever.assert_called_once_with()
                    server.return_value.server_close.assert_called_once_with()
                    self.assertEqual(app._survival_test_access_policy.permits("336268887"), len(members) == 5)

    def test_no_steam64_alias_or_noncanonical_account_can_create_other_archive(self):
        policy = install(self.app, setting(100, 101, 102, 103))
        for account in (100, "0100", str(STEAM_INDIVIDUAL_BASE + 100), "100 ", "", None):
            with self.subTest(account=account):
                self.assertFalse(policy.permits(account))
                with self.assertRaises(ApiError):
                    self.app._database_account_id(account)
        self.assertEqual(self.rpc.calls, [])

    def test_active_policy_cannot_be_relaxed_or_replaced_in_place(self):
        env = setting(100, 101, 102, 103)
        policy = install(self.app, env)
        wrapped = self.app._database_account_id
        self.assertIs(install(self.app, env), policy)
        self.assertIs(self.app._database_account_id, wrapped)
        for replacement in ({}, setting(200, 201, 202, 203)):
            with self.assertRaisesRegex(ValueError, "restart_required"):
                install(self.app, replacement)
        self.assertIs(self.app._database_account_id, wrapped)

    def test_invalid_service_setting_fails_before_bundle_or_config_sync(self):
        from archive_backend.service import install as install_archive
        with patch.dict(os.environ, {ENVIRONMENT_NAME: "invalid"}), \
                patch("archive_backend.service.Bundle") as bundle:
            with self.assertRaises(ValueError):
                install_archive(self.app, "unused-addon", "unused-lua")
        bundle.assert_not_called()
        self.assertEqual(self.rpc.calls, [])


if __name__ == "__main__":
    unittest.main()
