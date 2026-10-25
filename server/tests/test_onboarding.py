from __future__ import annotations

import ast
from copy import deepcopy
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.onboarding import command
from archive_backend.service import ArchiveService, ArchiveError
from fishing_api_overrides.onboarding_postgres import patch_postgres, ADDITION

SESSION = "onboarding_test_match_001"


def request(kind="onboarding_state", outcome=None):
    item = {"kind": kind, "version": 1,
            "id": SESSION + ":onboarding:" + (outcome or "state")}
    if outcome is not None:
        item["outcome"] = outcome
    return {"account_id": "100", "match_session_id": SESSION, "command": item}


class Database:
    def __init__(self):
        self.calls = []
        self.response = {"ok": True, "required": True, "status": "required", "version": 1}

    def rpc(self, name, arguments):
        self.calls.append((name, deepcopy(arguments)))
        return deepcopy(self.response)


class OnboardingTests(unittest.TestCase):
    def setUp(self):
        self.db = Database()
        self.identities = []
        def database_id(account):
            self.identities.append(account)
            return "a" * 64
        self.app = SimpleNamespace(rpc_client=self.db, _database_account_id=database_id)

    def test_state_uses_account_session_and_no_reward_or_profile_rpc(self):
        result = command(self.app, request())
        self.assertEqual(result, {"ok": True, "account_id": "100", "match_session_id": SESSION,
                                 "version": 1, "required": True, "status": "required"})
        self.assertEqual(self.identities, ["100"])
        self.assertEqual(self.db.calls, [("onboarding_state", {"p_account": "a" * 64, "p_session": SESSION})])

    def test_completed_skipped_and_legacy_metadata_survive_pure_mode_without_battle_profile(self):
        for status in ("completed", "skipped", "legacy"):
            self.db.response.update(status=status, required=False,
                private_database_id="secret", profile={"save": {"gameplay_stats": {"attack": 999}}})
            result = command(self.app, request())
            self.assertEqual(result["status"], status)
            self.assertFalse(result["required"])
            self.assertNotIn("profile", result)
            self.assertNotIn("private_database_id", result)

    def test_real_pure_projection_preserves_metadata_without_restoring_saved_combat_stats(self):
        # Exercise the packaged projection function itself, without importing
        # the externally installed fishing_api package or connecting anywhere.
        source = (ROOT / "server/fishing_api_overrides/match_profiles.py").read_text(encoding="utf-8-sig")
        project = next(node for node in ast.parse(source).body
                       if isinstance(node,ast.FunctionDef) and node.name=="project")
        namespace = {"deepcopy":deepcopy}
        exec(compile(ast.Module(body=[project],type_ignores=[]),"<pure-metadata-projection>","exec"),namespace)
        response = command(self.app,request())
        context = {"mode":"pure","baseline":{"save":{"gameplay_stats":{"attack":999999}}}}
        projected = namespace["project"](self.app,request(),response,context,login=True)
        self.assertEqual(projected,response)
        self.assertNotIn("profile",projected)
        self.assertNotIn("save",projected)

    def test_finish_accepts_only_terminal_outcomes(self):
        for outcome in ("completed", "skipped"):
            self.db.response.update(status=outcome, required=False)
            result = command(self.app, request("onboarding_finish", outcome))
            self.assertEqual(result["status"], outcome)
            self.assertEqual(self.db.calls[-1], ("onboarding_finish", {
                "p_account": "a" * 64, "p_session": SESSION, "p_outcome": outcome}))
        for outcome in ("required", "legacy", "", True, 1, [], {}):
            value = request("onboarding_finish", "completed")
            value["command"]["outcome"] = outcome
            with self.subTest(outcome=outcome), self.assertRaises(ValueError):
                command(self.app, value)

    def test_client_cannot_supply_first_login_status_progress_or_account_override(self):
        for field, value in (("status", "completed"), ("required", False), ("first_login", False),
                             ("step", 5), ("account_id", "200"), ("actual_seconds", 999)):
            payload = request()
            payload["command"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "fields_invalid"):
                command(self.app, payload)
        self.assertEqual(self.db.calls, [])

    def test_invalid_version_identity_and_command_id_rejected_before_rpc(self):
        mutations = [lambda p: p.update(account_id=100), lambda p: p.update(account_id="x"),
                     lambda p: p.update(match_session_id="short"),
                     lambda p: p["command"].update(id="other_match:onboarding:state"),
                     lambda p: p["command"].update(version=True),
                     lambda p: p["command"].update(version=2),
                     lambda p: p["command"].update(kind=[])]
        for mutation in mutations:
            payload = request()
            mutation(payload)
            with self.assertRaises(ValueError):
                command(self.app, payload)
        self.assertEqual(self.db.calls, [])

    def test_backend_failure_and_malformed_metadata_cannot_be_reported_as_loaded(self):
        for value in ({"ok": False, "error": "unknown"}, None, {},
                      {"ok": True, "required": False, "status": "required", "version": 1},
                      {"ok": True, "required": True, "status": [], "version": 1},
                      {"ok": True, "required": True, "status": "required", "version": True}):
            self.db.response = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "response_invalid"):
                command(self.app, request())
        self.db.response = {"ok": False, "error": "match_session_missing"}
        self.assertEqual(command(self.app, request()), {
            "ok": False, "error": "match_session_missing", "terminal": True})

    def test_existing_archive_route_bypasses_rewards_bundle_but_preserves_other_commands(self):
        service = ArchiveService(self.app, SimpleNamespace(), "not-executable")
        payload = request()
        payload["config_hash"] = "old_reward_bundle"
        self.assertTrue(service.command(payload)["required"])
        payload["command"]["version"] = 2
        with self.assertRaisesRegex(ArchiveError, "fields_invalid"):
            service.command(payload)

    def test_transport_overlay_preserves_old_signatures_and_all_other_code(self):
        baseline = ROOT / "design_refs/endless_leaderboard_20261016/deployment/online_baseline/backend/fishing_api/postgres.py"
        source = baseline.read_text(encoding="utf-8-sig")
        patched = patch_postgres(source)
        self.assertEqual(patch_postgres(patched),patched)
        self.assertEqual(patched.replace(ADDITION,"",1),source)
        self.assertIn('"onboarding_finish": _params',patched)
        with self.assertRaises(ValueError):
            patch_postgres(patched.replace('("p_outcome", "text", "reward_id")','("p_outcome", "text", "hash")'))


if __name__ == "__main__":
    unittest.main()
