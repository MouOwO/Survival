"""Authored mode prerequisites retain private, immutable session identities."""
from copy import deepcopy
import hashlib
import importlib.util
from pathlib import Path
import re
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("archive_mode_admission_implementation", ROOT / "server/archive_backend/match_modes.py")
implementation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(implementation)


class ApiError(ValueError):
    def __init__(self, code, status):
        self.code, self.status = code, status
        super().__init__(code)


class ModeAdmissionCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.profile = {"schema_version": 1, "account_id": "100", "revision": 1,
                        "save": {"archive": {}, "gameplay_stats": {"initial_wood": 777}}}
        self.sessions, self.calls = {}, []
        module = SimpleNamespace(ApiError=ApiError, ACCOUNT_ID=r"[0-9]{1,20}", OPAQUE_ID=r"[A-Za-z0-9_.:-]{8,128}")
        def string(payload, key, pattern):
            value = payload.get(key)
            if not isinstance(value, str) or not re.fullmatch(pattern, value):
                raise ApiError("request_field_invalid", 400)
            return value
        def validate(value, account, session):
            if (value.get("ok") is not True or value.get("account_id") != account
                    or value.get("match_session_id") != session or value.get("mode") not in ("pure", "standard")):
                raise ApiError("match_session_invalid", 503)
        def project(app, payload, response, context, *, login=False):
            result = deepcopy(response)
            result.update(mode=context["mode"], match_session_id=context["match_session_id"],
                          account_profile=deepcopy(response), progression=module.progression(response))
            return result
        def ordinary_login(app, payload):
            if payload.get("mode") not in ("pure", "standard"):
                raise ApiError("match_mode_invalid", 400)
            return {"ordinary_login": payload["mode"]}
        module._string, module._validate_context, module.project, module.login = string, validate, project, ordinary_login
        implementation.install(module)
        self.module = module
        self.session = "admission-compatibility-session"
        def rpc(name, payload):
            self.assertEqual(name, "match_profile_login")
            self.calls.append(deepcopy(payload))
            key = payload["p_account"], payload["p_session"]
            if key in self.sessions and self.sessions[key]["mode"] != payload["p_mode"]:
                return {"ok": False, "error": "match_mode_locked"}
            self.sessions.setdefault(key, {"ok": True, "account_id": payload["p_account"],
                "match_session_id": payload["p_session"], "mode": payload["p_mode"],
                "baseline": deepcopy(self.profile), "defaults": {}, "created_at": 100})
            return dict(deepcopy(self.sessions[key]), profile=deepcopy(self.profile))
        self.app = SimpleNamespace(archive=SimpleNamespace(profile=lambda payload: deepcopy(self.profile)),
            rpc_client=SimpleNamespace(rpc=rpc), gameplay_stats={},
            _database_account_id=lambda account: hashlib.sha256(account.encode()).hexdigest(),
            _public_response=lambda response, database, account: deepcopy(response))

    def login(self, mode):
        return self.module.login(self.app, {"account_id": "100", "match_session_id": self.session, "mode": mode})

    def test_open_advanced_modes_use_exact_clear_prerequisites(self):
        for mode, prerequisite in (("rich", "n3"), ("cold", "n5")):
            with self.subTest(mode=mode):
                self.session = "compatibility-" + mode + "-session"
                with self.assertRaisesRegex(ApiError, mode + "_mode_locked"):
                    self.login(mode)
                self.profile["save"]["archive"] = {"mode_clear_counts": {"pure": {prerequisite: 1}}}
                result = self.login(mode)
                self.assertEqual((result["mode"], result["game_mode"]), ("standard", mode))
                self.assertEqual(result["save"]["gameplay_stats"]["initial_wood"], 777)
                self.assertEqual(self.calls[-1]["p_mode"], mode)
                key = self.app._database_account_id("100"), self.session
                self.assertEqual(self.sessions[key]["mode"], mode)
        self.assertEqual(self.profile["save"]["archive"], {"mode_clear_counts": {"pure": {"n5": 1}}},
                         "identity cannot fabricate prerequisite clears")

    def test_rich_uses_global_exact_n3_including_valid_legacy_history(self):
        with self.assertRaisesRegex(ApiError, "rich_mode_locked"):
            self.login("rich")
        self.assertEqual(self.calls, [])
        archive = self.profile["save"]["archive"]
        archive["clear_counts"] = {"n10": 1}
        with self.assertRaisesRegex(ApiError, "rich_mode_locked"):
            self.login("rich")
        archive["clear_counts"]["n3"] = 1
        self.assertEqual(self.login("rich")["game_mode"], "rich")
        self.session = "rich-established-empty-map-session"
        archive["standard_clear_counts"] = {}
        with self.assertRaisesRegex(ApiError, "rich_mode_locked"):
            self.login("rich")
        archive["clear_counts"] = {}
        archive["standard_clear_counts"] = {"n3": 1}
        self.assertEqual(self.login("rich")["game_mode"], "rich")

    def test_mode_identity_is_immutable_and_unreleased_modes_stay_closed(self):
        self.profile["save"]["archive"] = {"clear_counts": {"n3": 1, "n5": 1, "n9": 1, "n11": 1}}
        self.login("cold")
        with self.assertRaisesRegex(ApiError, "match_mode_locked"):
            self.login("rich")
        for mode in ("scourge", "ruins", "celestial", "fishing"):
            with self.subTest(mode=mode), self.assertRaisesRegex(ApiError, "mode_not_released"):
                self.login(mode)
        key = self.app._database_account_id("100"), self.session
        self.assertEqual(self.sessions[key]["mode"], "cold")

    def test_pure_and_standard_still_use_the_original_login_contract(self):
        for mode in ("pure", "standard"):
            self.assertEqual(self.login(mode), {"ordinary_login": mode})
        self.assertEqual(self.calls, [])

    def test_sql_prepares_seven_identities_but_only_four_modes_admit_new_sessions(self):
        path = ROOT / "server/aliyun/database/target/202610220001_human_spec_mode_admission.sql"
        source = path.read_text(encoding="utf-8")
        self.assertIn("CHECK (mode IN ('pure','standard','rich','cold','scourge','ruins','celestial'))", source)
        self.assertIn("IF p_mode NOT IN ('pure','standard','rich','cold')", source)
        self.assertIn("WHEN 'rich' THEN 'n3' WHEN 'cold' THEN 'n5'", source)
        self.assertIn("WHEN 'pure' THEN archive->'mode_clear_counts'->'pure'", source)
        self.assertIn("WHEN 'standard' THEN CASE WHEN archive ? 'standard_clear_counts'", source)
        self.assertIn("THEN archive->'standard_clear_counts' ELSE archive->'clear_counts' END", source)
        self.assertIn("ELSE archive->(source_mode||'_clear_counts') END", source)
        self.assertNotIn("'pure_clear_counts'", source)
        self.assertNotIn("archive->'mode_clear_counts'->source_mode", source)
        self.assertEqual(source.count("FOREACH source_mode"), 1)
        self.assertIn("s.mode<>p_mode", source)
        self.assertIn("'match_mode_locked'", source)
        self.assertLess(source.index("FROM public.player_gameplay_stats"), source.index("FROM public.survival_players"))
        self.assertIn("ON CONFLICT DO NOTHING", source)
        self.assertIn("REVOKE ALL ON FUNCTION", source)
        self.assertNotRegex(source, r"(?i)UPDATE\s+public\.match_profile_sessions|DELETE\s+FROM")


if __name__ == "__main__":
    unittest.main()
