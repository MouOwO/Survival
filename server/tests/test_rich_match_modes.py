"""Offline rich admission/session/settlement contracts; no remote DB writes."""
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import os
import re
import shutil
import sys
import tempfile
import types
import unittest
import json
import hashlib
import threading
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "server"), str(ROOT / "server/tests")]
from archive_backend import match_modes
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveService, ArchiveError
from test_archive_backend import Database, App


class ApiError(ValueError):
    def __init__(self, code, status):
        self.code, self.status = code, status
        super().__init__(code)


def api_contract():
    """Existing API hooks: identity checks and standard combat projection."""
    module = types.SimpleNamespace(ApiError=ApiError, ACCOUNT_ID=r"[0-9]{1,20}",
                                   OPAQUE_ID=r"[A-Za-z0-9_.:-]{8,128}")
    def string(payload, key, pattern):
        value = payload.get(key)
        if not isinstance(value, str) or not re.fullmatch(pattern, value):
            raise ApiError("request_field_invalid", 400)
        return value
    def validate(value, account, session):
        if (not isinstance(value, dict) or value.get("ok") is not True
                or value.get("account_id") != account or value.get("match_session_id") != session
                or value.get("mode") not in ("pure", "standard")):
            raise ApiError("match_session_invalid", 503)
    def project(app, payload, response, context, *, login=False):
        result = deepcopy(response)
        view = result if "schema_version" in result else result.get("profile")
        if view is not None:
            view.update(mode=context["mode"], match_session_id=context["match_session_id"],
                        progression=module.progression(view), account_profile=deepcopy(view))
        return result
    module._string, module._validate_context, module.project = string, validate, project
    module.login = lambda app, payload: {"ordinary_login": payload["mode"]}
    match_modes.install(module)
    return module


class RichDatabase(Database):
    def __init__(self, bundle):
        super().__init__(bundle)
        self.sessions = {}
    def rpc(self, name, payload):
        if name == "match_profile_context":
            return deepcopy(self.sessions.get((payload["p_account"], payload["p_session"]), {"ok": False}))
        if name == "match_profile_login":
            account, session, mode = (payload[key] for key in ("p_account", "p_session", "p_mode"))
            key = account, session
            if key in self.sessions and self.sessions[key]["mode"] != mode:
                return {"ok": False, "error": "match_mode_locked"}
            current = self.profile(account)
            if mode == "rich" and not match_modes.progression(current)["standard_clear_counts"].get("n10"):
                return {"ok": False, "error": "rich_mode_locked"}
            self.sessions.setdefault(key, {"ok": True, "account_id": account,
                "match_session_id": session, "mode": mode, "baseline": deepcopy(current),
                "defaults": deepcopy(payload["p_defaults"]), "created_at": 100})
            return dict(deepcopy(self.sessions[key]), profile=deepcopy(current))
        return super().rpc(name, payload)


class RichApp(App):
    def __init__(self, database):
        super().__init__(database)
        self.gameplay_stats = {}
    def _public_response(self, response, account, public):
        result = super()._public_response(response, account, public)
        if "schema_version" in result:
            result["account_id"] = public
        return result


class RichModeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = os.environ.get("LUA_EXECUTABLE") or shutil.which("lua5.1") or shutil.which("lua")
        if not cls.lua:
            raise RuntimeError("Set LUA_EXECUTABLE for the real archive reducer")
        cls.temporary = tempfile.TemporaryDirectory(prefix="rich-mode-test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        destination = Path(cls.temporary.name)
        cls.bundle = Bundle(destination / build(ROOT, destination=destination, update_game_config=False))

    def setUp(self):
        self.database = RichDatabase(self.bundle)
        self.app = RichApp(self.database)
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.app.archive = self.service
        self.module = api_contract()
        self.account, self.session = "100", "rich-test-session-one"
        self.database_account = self.app._database_account_id(self.account)
        self.profile = self.database.profile(self.database_account)

    def login(self, mode="rich"):
        return self.module.login(self.app, {"account_id": self.account,
            "match_session_id": self.session, "mode": mode})

    def context(self, mode="rich"):
        self.database.sessions[(self.database_account, self.session)] = {
            "ok": True, "mode": mode, "account_id": self.database_account,
            "match_session_id": self.session, "baseline": deepcopy(self.profile), "defaults": {}, "created_at": 100}

    def send(self, kind="rich_clear", difficulty="n5", **extra):
        return self.service.command({"account_id": self.account, "config_hash": self.bundle.hash,
            "match_session_id": self.session, "command": {"id": "client-clear-id-one", "kind": kind,
            "difficulty_id": difficulty, "count": 1, **extra}})

    def test_historical_fallback_and_strict_established_standard_counter(self):
        archive = self.profile["save"]["archive"]
        archive["clear_counts"] = {"n10": 1}
        self.profile["save"]["gameplay_stats"]["initial_wood"] = 777
        rich = self.login()
        self.assertEqual(rich["mode"], "standard")
        self.assertEqual(rich["game_mode"], "rich")
        self.assertEqual(rich["save"]["gameplay_stats"]["initial_wood"], 777)
        self.assertEqual(self.database.sessions[(self.database_account, self.session)]["mode"], "rich")
        self.assertEqual(self.login()["save"], rich["save"], "same-session retries preserve the baseline")
        self.session = "rich-test-session-two"
        archive["standard_clear_counts"] = {}
        with self.assertRaisesRegex(ApiError, "rich_mode_locked"):
            self.login()
        self.assertEqual(self.module.login(self.app, {"mode": "pure"}), {"ordinary_login": "pure"})

    def test_untrusted_unlock_and_malformed_counts_do_not_admit(self):
        for invalid in (True, "1", -1, 0, 1.5, float("inf")):
            self.profile["save"]["archive"] = {"clear_counts": {"n10": 999},
                "standard_clear_counts": {"n10": invalid}}
            with self.subTest(value=invalid), self.assertRaisesRegex(ApiError, "rich_mode_locked"):
                self.module.login(self.app, {"account_id": self.account, "match_session_id": self.session,
                    "mode": "rich", "unlocked": True})
        self.assertEqual(self.database.sessions, {})

    def test_clear_scope_requires_durable_matching_account_and_mode(self):
        with self.assertRaisesRegex(ArchiveError, "match_session_invalid"):
            self.send()
        for mode, kind in (("pure", "rich_clear"), ("standard", "rich_clear"),
                           ("rich", "clear"), ("rich", "standard_clear"), ("pure", "standard_clear")):
            self.context(mode)
            with self.subTest(mode=mode, kind=kind), self.assertRaisesRegex(ArchiveError, "match_clear_mode_mismatch"):
                self.send(kind)
        self.context("rich")
        self.database.sessions[(self.database_account, self.session)]["account_id"] = "wrong-account"
        with self.assertRaisesRegex(ArchiveError, "match_session_invalid"):
            self.send()
        self.assertEqual(self.database.ops, {}, "rejected scope must not prepare any permanent operation")

    def test_rich_replay_and_standard_progression_are_separate(self):
        self.profile["save"]["archive"] = {"clear_counts": {"n5": 4, "n10": 1}}
        self.context("rich")
        self.assertTrue(self.send()["ok"])
        self.assertTrue(self.send()["ok"])
        saved = self.profile["save"]["archive"]
        self.assertEqual(saved["rich_clear_counts"], {"n5": 1})
        self.assertEqual(saved["clear_counts"], {"n5": 4, "n10": 1})
        self.assertEqual(saved["standard_clear_counts"], {"n5": 4, "n10": 1})
        self.assertEqual(len(self.database.ops), 1)
        self.context("standard")
        self.assertTrue(self.send("standard_clear", "n6")["ok"])
        self.assertEqual(self.profile["save"]["archive"]["standard_clear_counts"]["n6"], 1)
        self.assertNotIn("n6", self.profile["save"]["archive"]["rich_clear_counts"])

    def test_extra_fields_count_and_rich_n11_rejected_before_write(self):
        self.context()
        for extra in ({"unlocked": True}, {"count": 2}, {"count": True}):
            command = {"id": "client-clear-id-one", "kind": "rich_clear", "difficulty_id": "n5", "count": 1, **extra}
            with self.assertRaises(ArchiveError):
                self.service.validate(command)
        with self.assertRaisesRegex(ArchiveError, "archive_clear_invalid"):
            self.send(difficulty="n11")
        self.assertEqual(self.database.ops, {})

    def test_explicit_old_hash_policy_routes_only_new_clear_kinds_to_new_reducer(self):
        # A game can keep its existing hash during the staged backend rollout.
        # Its old reducer cannot understand the new wire kinds; the explicit
        # compatibility rule must choose the new reducer for those commands.
        original = json.loads((self.bundle.directory / "bundle.json").read_bytes())
        directory = Path(self.temporary.name) / "staged-compatibility"
        def write_bundle(data):
            raw = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
            digest = hashlib.sha256(raw).hexdigest()
            target = directory / digest
            target.mkdir(parents=True, exist_ok=True)
            (target / "bundle.json").write_bytes(raw)
            for name, text in data["sources"].items():
                file = target / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(text, encoding="utf-8", newline="\n")
            return Bundle(target)
        legacy = deepcopy(original)
        legacy["sources"]["systems/archive_settlement.lua"] = (
            'return {settle=function() error("old_reducer_received_new_clear_protocol") end}\n')
        old = write_bundle(legacy)
        current = deepcopy(original)
        current.setdefault("compatible_config_hashes", {})[old.hash] = {
            "commands": ["standard_clear", "rich_clear"], "upgrade_commands": ["standard_clear", "rich_clear"]}
        active = ArchiveService(self.app, write_bundle(current), self.lua)
        self.context("rich")
        request = {"account_id": self.account, "match_session_id": self.session,
            "config_hash": old.hash, "command": {"id": "old-client-hash-rich-clear", "kind": "rich_clear",
                                                "difficulty_id": "n5", "count": 1}}
        self.assertTrue(active.command(request)["ok"])
        self.assertEqual(self.profile["save"]["archive"]["rich_clear_counts"], {"n5": 1})
        self.context("standard")
        request["command"] = dict(request["command"], kind="standard_clear")
        self.assertTrue(active.command(request)["ok"])
        self.assertEqual(self.profile["save"]["archive"]["standard_clear_counts"], {"n5": 1})
        self.assertFalse(active.command(dict(request, command=dict(request["command"], kind="boss_kill")))["ok"],
                         "a narrow compatibility rule must not admit unrelated commands")

    @unittest.skipUnless(os.environ.get("FISHING_BACKEND_ROOT"), "set FISHING_BACKEND_ROOT for actual HTTP integration")
    def test_actual_fishing_api_auth_login_projection_and_scoped_clear(self):
        sys.path.insert(0, os.environ["FISHING_BACKEND_ROOT"])
        from fishing_api import server, match_profiles
        match_modes.install(match_profiles)
        http = ThreadingHTTPServer(("127.0.0.1", 0), server.make_handler(self.app))
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        def post(path, payload):
            request = urllib.request.Request("http://127.0.0.1:" + str(http.server_port) + path,
                data=json.dumps(payload).encode(), headers={"Authorization": "Bearer local-test-only",
                                                          "Content-Type": "application/json"})
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(request, timeout=10) as response:
                return json.load(response)
        payload = {"account_id": self.account, "match_session_id": self.session}
        try:
            admitted = post("/v1/session/authenticate", payload)
            self.assertFalse(admitted["progression"]["standard_clear_counts"])
            self.assertFalse(self.database.sessions, "entry authentication cannot create a mode baseline")
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                post("/v1/session/login", dict(payload, mode="rich", unlocked=True))
            self.assertEqual(rejected.exception.code, 409)
            rejected.exception.close()
            self.profile["save"]["archive"]["clear_counts"] = {"n10": 1}
            self.profile["save"]["gameplay_stats"]["initial_wood"] = 777
            admitted = post("/v1/session/authenticate", payload)
            self.assertEqual(admitted["progression"]["standard_clear_counts"]["n10"], 1)
            profile = post("/v1/session/login", dict(payload, mode="rich"))
            self.assertEqual((profile["mode"], profile["game_mode"]), ("standard", "rich"))
            self.assertEqual(profile["save"]["gameplay_stats"]["initial_wood"], 777)
            self.assertEqual(profile["account_profile"]["save"], profile["save"])
            command = {"id": "rich-http-clear-one", "kind": "rich_clear", "difficulty_id": "n5", "count": 1}
            result = post("/v1/archive/command", dict(payload, config_hash=self.bundle.hash, command=command))
            self.assertTrue(result["ok"])
            self.assertEqual(result["profile"]["game_mode"], "rich")
            self.assertEqual(result["profile"]["progression"]["rich_clear_counts"], {"n5": 1})
            self.assertEqual(result["profile"]["progression"]["clear_counts"], {"n10": 1})
            self.assertTrue(post("/v1/archive/command", dict(payload, config_hash=self.bundle.hash, command=command))["ok"])
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                post("/v1/archive/command", dict(payload, config_hash=self.bundle.hash,
                    command=dict(command, kind="standard_clear")))
            self.assertEqual(rejected.exception.code, 400)
            rejected.exception.close()
        finally:
            http.shutdown(); http.server_close(); thread.join()


if __name__ == "__main__":
    unittest.main()
