"""Retired tutorial commands cannot reach any database/profile/reward RPC."""
from __future__ import annotations

import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_archive_backend as base
import test_archive_benefits as benefits
from archive_backend.service import ArchiveError, ArchiveService


class RecordingDatabase(benefits.Database):
    def __init__(self, bundle):
        super().__init__(bundle)
        self.calls = []

    def rpc(self, name, arguments):
        self.calls.append((name, copy.deepcopy(arguments)))
        return super().rpc(name, arguments)


class RetiredTutorialTests(unittest.TestCase):
    setUpClass = classmethod(base.ArchiveTests.setUpClass.__func__)

    def setUp(self):
        self.db = RecordingDatabase(self.bundle)
        self.app = benefits.App(self.db)
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.account = self.app._database_account_id("100")
        self.profile = self.db.profile(self.account)
        self.session = "retired_tutorial_match_001"

    def request(self, kind, outcome=None):
        command = {"id": self.session + ":onboarding:" + (outcome or "state"),
                   "kind": kind, "version": 1}
        if outcome is not None:
            command["outcome"] = outcome
        return {"account_id": "100", "match_session_id": self.session,
                "config_hash": self.bundle.hash, "command": command}

    def test_old_state_and_both_finish_commands_rejected_before_any_rpc(self):
        before = copy.deepcopy(self.profile)
        for kind, outcome in (("onboarding_state", None), ("onboarding_finish", "completed"),
                              ("onboarding_finish", "skipped")):
            with self.subTest(kind=kind, outcome=outcome), self.assertRaisesRegex(
                    ArchiveError, "archive_command_fields_invalid"):
                self.service.command(self.request(kind, outcome))
        self.assertEqual(self.db.calls, [])
        self.assertEqual(self.profile, before)
        self.assertFalse(self.db.ops)

    def test_historical_hashless_metadata_route_is_not_a_bypass(self):
        for kind in ("onboarding_state", "onboarding_finish"):
            request = self.request(kind, "completed" if kind.endswith("finish") else None)
            request.pop("config_hash")
            result = self.service.command(request)
            self.assertFalse(result["ok"])
            self.assertTrue(result["terminal"])
            self.assertEqual(result["error"], "archive_config_mismatch")
        self.assertEqual(self.db.calls, [])
        self.assertFalse(self.db.ops)

    def test_tutorial_names_cannot_submit_status_progress_or_rewards(self):
        before = copy.deepcopy(self.profile)
        for kind in ("onboarding_state", "onboarding_finish"):
            request = self.request(kind)
            request["command"].update(status="completed", required=False,
                                      count=200, item_id="special_lottery_ticket")
            with self.assertRaisesRegex(ArchiveError, "archive_command_fields_invalid"):
                self.service.command(request)
        self.assertEqual(self.db.calls, [])
        self.assertEqual(self.profile, before)

    def test_normal_profile_read_does_not_consult_or_require_tutorial(self):
        before = copy.deepcopy(self.profile["save"])
        result = self.service.profile({"account_id": "100"})
        self.assertEqual(result["account_id"], "100")
        self.assertEqual(result["save"], before)
        self.assertFalse(self.db.ops)
        self.assertTrue(self.db.calls)
        self.assertFalse(any(name.startswith("onboarding") for name, _ in self.db.calls))

    def test_existing_public_beta_gift_still_uses_session_and_atomic_receipt(self):
        self.db.contexts[self.session] = "standard"
        result = self.service.command({"account_id": "100", "match_session_id": self.session,
            "config_hash": self.bundle.hash, "command": {
                "id": "retired_tutorial:public_beta_gift:today", "kind": "benefit_claim",
                "track": "public_beta_login", "tier_id": "public_beta_login"}})
        self.assertTrue(result["ok"])
        self.assertEqual(result["profile"]["save"]["content_inventory"], {"special_lottery_ticket": 2})
        names = [name for name, _ in self.db.calls]
        self.assertIn("match_profile_context", names)
        self.assertIn("archive_commit_lottery", names)
        self.assertFalse(any(name.startswith("onboarding") for name in names))


if __name__ == "__main__":
    unittest.main()
