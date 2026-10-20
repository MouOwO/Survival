"""Offline durable-mode scope regressions; never connects to a live service."""
from copy import deepcopy
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "server")]
from archive_backend import match_modes
from archive_backend.service import ArchiveError


class ModeClearScopeTests(unittest.TestCase):
    def setUp(self):
        self.session = "trusted-mode-session-one"
        self.payload = {"account_id": "123", "match_session_id": self.session, "mode_id": "pure"}
        self.context = {"ok": True, "account_id": "database-123", "match_session_id": self.session,
                        "mode": "standard"}
        self.calls = []
        def rpc(name, body):
            self.calls.append((name, body))
            return deepcopy(self.context)
        self.service = SimpleNamespace(app=SimpleNamespace(
            _database_account_id=lambda value: "database-" + value,
            rpc_client=SimpleNamespace(rpc=rpc)))
        self.command = {"id": "untrusted-client-request", "kind": "mode_clear",
                        "difficulty_id": "n1", "count": 1}

    def scope(self, command=None, payload=None):
        return match_modes.scope_clear(self.service, payload or self.payload, command or self.command)

    def test_new_clear_binds_mode_and_receipt_to_persisted_session(self):
        for mode in match_modes.MODE_IDS:
            self.context["mode"] = mode
            with self.subTest(mode=mode):
                scoped = self.scope(dict(self.command, mode_id="scourge"))
                self.assertEqual(scoped["mode_id"], mode)
                kind = "clear" if mode == "pure" else mode + "_clear"
                self.assertEqual(scoped["id"], self.session + ":" + kind)
                self.assertEqual(scoped, self.scope(dict(self.command, mode_id="rich", id="different-client-request")))
        self.assertNotIn("mode_id", self.command, "scoping must not mutate callers' command")
        self.assertTrue(all(name == "match_profile_context" and body == {
            "p_account": "database-123", "p_session": self.session} for name, body in self.calls))

    def test_old_explicit_protocol_and_new_protocol_share_the_same_receipt(self):
        for kind, mode in match_modes.CLEAR_MODES.items():
            self.context["mode"] = mode
            with self.subTest(mode=mode):
                old = self.scope(dict(self.command, kind=kind))
                new = self.scope()
                self.assertEqual((old["id"], old["mode_id"]), (new["id"], new["mode_id"]))
        self.context["mode"] = "pure"
        self.assertEqual(self.scope(dict(self.command, kind="clear"))["id"], self.scope()["id"])

    def test_absent_malformed_or_mismatched_durable_identity_never_gets_a_mode(self):
        for update in ({"ok": False}, {"account_id": "another-account"},
                       {"match_session_id": "another-session"}, {"mode": "fishing"},
                       {"mode": "not-a-mode"}):
            before = deepcopy(self.context)
            self.context.update(update)
            with self.subTest(update=update), self.assertRaises(ArchiveError):
                self.scope()
            self.context = before
        for session in (None, "short", [], 123):
            with self.subTest(session=session), self.assertRaisesRegex(ArchiveError, "match_session_missing"):
                self.scope(payload=dict(self.payload, match_session_id=session))
        self.context["mode"] = "rich"
        with self.assertRaisesRegex(ArchiveError, "match_clear_mode_mismatch"):
            self.scope(dict(self.command, kind="standard_clear"))
        with self.assertRaisesRegex(ArchiveError, "match_clear_mode_mismatch"):
            self.scope(dict(self.command, kind="clear"))

    def test_unscoped_legacy_clear_is_compatible_without_inventing_history(self):
        legacy = dict(self.command, kind="clear")
        self.assertEqual(self.scope(legacy, {"account_id": "123"}), legacy)
        self.assertEqual(self.calls, [])

    def test_public_projection_keeps_legacy_fields_and_does_not_copy_mixed_history(self):
        archive = {"clear_counts": {"n1": 42, "n10": 1}, "rich_clear_counts": {"n2": 7},
                   "mode_clear_counts": {"pure": {"n1": 2, "n2": True, "n3": -1, "n4": "8"},
                                         "cold": {"n4": 3}, "fishing": {"n1": 999}}}
        before = deepcopy(archive)
        projected = match_modes.progression({"save": {"archive": archive}})
        self.assertEqual(projected["clear_counts"], {"n1": 42, "n10": 1})
        self.assertEqual(projected["standard_clear_counts"], projected["clear_counts"])
        self.assertEqual(projected["rich_clear_counts"], {"n2": 7})
        self.assertEqual(projected["mode_clear_counts"], {
            "pure": {"n1": 2}, "standard": {}, "rich": {}, "cold": {"n4": 3}, "scourge": {}})
        self.assertEqual(archive, before)
        for invalid in (None, [], True, "invalid"):
            archive["mode_clear_counts"] = invalid
            self.assertEqual(match_modes.progression({"save": {"archive": archive}})["mode_clear_counts"],
                             {mode: {} for mode in match_modes.MODE_IDS})

    def test_daily_projection_reads_real_account_for_pure_and_preserves_default_without_service(self):
        source = {"schema_version": 1, "save": {"archive": {"mode_clear_counts": {"pure": {"n1": 2}}}}}
        projected = {"schema_version": 1, "save": {"archive": {}},
                     "account_profile": deepcopy(source), "progression": {"loaded": True}}
        application = SimpleNamespace()
        self.assertIs(match_modes._daily_projection(application, source, projected), projected)
        self.assertNotIn("daily_limits", projected)
        seen = []
        def snapshot(account, bundle):
            seen.append((deepcopy(account), bundle))
            return {"day_key": "2026-10-20", "rows": [], "by_key": {"clear": {"remaining": 3}}}
        bundle = object()
        application.archive_service = SimpleNamespace(bundle=bundle)
        with patch.dict(sys.modules, {"archive_backend.daily_limits": SimpleNamespace(snapshot=snapshot)}):
            result = match_modes._daily_projection(application, source, {"ok": True, "profile": projected})
        self.assertEqual(seen, [(source, bundle)])
        self.assertEqual(result["daily_limits"]["by_key"]["clear"]["remaining"], 3)
        self.assertEqual(projected["daily_limits"], projected["progression"]["daily_limits"])
        self.assertEqual(projected["save"]["archive"], {}, "pure combat bonuses remain projected")

    def test_install_upgrades_the_old_guard_and_attaches_daily_summary_for_each_projection(self):
        calls = []
        def project(app, payload, response, context, *, login=False):
            calls.append(context["mode"])
            return deepcopy(response)
        module = SimpleNamespace(_validate_context=lambda *args: None,
                                 login=lambda *args: None, project=project,
                                 _rich_modes_installed=True)
        match_modes.install(module)
        installed = module.project
        match_modes.install(module)
        self.assertIs(module.project, installed, "reinstallation must not nest wrappers")
        account = {"schema_version": 1, "save": {"archive": {"clear_counts": {"n1": 7}}}}
        response = {"schema_version": 1, "save": {"archive": {}},
                    "account_profile": account, "progression": {"loaded": True}}
        app = SimpleNamespace(archive_service=SimpleNamespace(bundle="fixture-bundle"))
        seen = []
        def snapshot(profile, bundle):
            seen.append((deepcopy(profile), bundle))
            return {"day_key": "2026-10-20", "rows": [], "by_key": {}}
        with patch.dict(sys.modules, {"archive_backend.daily_limits": SimpleNamespace(snapshot=snapshot)}):
            for mode in match_modes.MODE_IDS:
                result = module.project(app, {}, response, {"mode": mode})
                self.assertIn("daily_limits", result["progression"])
                if mode in match_modes.PARENT_MODES:
                    self.assertEqual(result["game_mode"], mode)
        self.assertEqual(calls, ["pure", "standard", "standard", "standard", "standard"])
        self.assertEqual(seen, [(account, "fixture-bundle")] * 5)

    def test_authenticate_attaches_account_summary_without_creating_or_binding_a_session(self):
        class ApiError(ValueError):
            def __init__(self, code, status):
                self.code, self.status = code, status
                super().__init__(code)
        source = {"account_id": "123", "revision": 2, "schema_version": 1,
                  "save": {"archive": {"clear_counts": {"n1": 8}}}}
        for attribute in ("archive", "archive_service"):
            reads, seen = [], []
            def read(payload):
                reads.append(deepcopy(payload))
                return deepcopy(source)
            service = SimpleNamespace(bundle="fixture-bundle", profile=read)
            app = SimpleNamespace(**{attribute: service})
            def forbidden(*args, **kwargs):
                raise AssertionError("entry authentication must never call a match-session RPC")
            app.rpc_client = SimpleNamespace(rpc=forbidden)
            def authenticate(application, payload):
                if set(payload) != {"account_id", "match_session_id"}:
                    raise ApiError("authenticate_fields_invalid", 400)
                current = read({"account_id": payload["account_id"]})
                return {"authenticated": True, "account_id": payload["account_id"],
                        "match_session_id": payload["match_session_id"],
                        "progression": module.progression(current)}
            module = SimpleNamespace(_validate_context=forbidden, login=forbidden,
                                     project=forbidden, authenticate=authenticate, ApiError=ApiError)
            match_modes.install(module)
            def snapshot(profile, bundle):
                seen.append((deepcopy(profile), bundle))
                return {"day_key": "2026-10-20", "rows": [], "by_key": {"clear": {"remaining": 2}}}
            payload = {"account_id": "123", "match_session_id": self.session}
            with self.subTest(attribute=attribute), patch.dict(sys.modules, {
                    "archive_backend.daily_limits": SimpleNamespace(snapshot=snapshot)}):
                receipt = module.authenticate(app, payload)
                installed = module.authenticate
                match_modes.install(module)
                self.assertIs(module.authenticate, installed)
                self.assertEqual(receipt["daily_limits"]["by_key"]["clear"]["remaining"], 2)
                self.assertEqual(receipt["daily_limits"], receipt["progression"]["daily_limits"])
                self.assertEqual(receipt["progression"]["clear_counts"], {"n1": 8})
                self.assertEqual(set(receipt), {"authenticated", "account_id", "match_session_id",
                                                "progression", "daily_limits"})
                self.assertEqual(seen, [(source, "fixture-bundle")])
                self.assertEqual(reads, [{"account_id": "123"}] * 2)
                with self.assertRaisesRegex(ApiError, "authenticate_fields_invalid"):
                    module.authenticate(app, dict(payload, mode="standard"))
                self.assertEqual(len(reads), 2, "original field validation must run before the new read")

    def test_authenticate_rejects_an_inconsistent_second_account_read(self):
        class ApiError(ValueError):
            def __init__(self, code, status):
                super().__init__(code)
        module = SimpleNamespace(_validate_context=lambda *args: None, login=lambda *args: None,
            project=lambda *args: None, ApiError=ApiError,
            authenticate=lambda *args: {"authenticated": True, "account_id": "123"})
        match_modes.install(module)
        app = SimpleNamespace(archive=SimpleNamespace(bundle=object(), profile=lambda payload: {
            "account_id": "another-account", "revision": 1, "save": {}}))
        with self.assertRaisesRegex(ApiError, "authentication_profile_invalid"):
            module.authenticate(app, {"account_id": "123"})


if __name__ == "__main__":
    unittest.main()
