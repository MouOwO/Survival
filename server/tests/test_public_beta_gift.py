"""Public-beta login gifts use real Lua plus mocked durable RPC transactions.

No cloud, application credentials, or real player/reward data are accessed.
"""
import copy
import math
import hashlib
import json
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_archive_backend as base
import test_archive_benefits as benefits
from archive_backend.service import ArchiveError, ArchiveService
from archive_backend.public_beta_gift import MARKER
from archive_backend.bundle import Bundle


class Database(benefits.Database):
    def __init__(self, bundle):
        super().__init__(bundle)
        self.sessions = {}

    def rpc(self, name, params):
        if name == "match_profile_context":
            account, session = params["p_account"], params["p_session"]
            mode = self.sessions.get((account, session))
            return {"ok": mode is not None, "account_id": account,
                    "match_session_id": session, "mode": mode}
        return super().rpc(name, params)


class PublicBetaGiftTests(unittest.TestCase):
    setUpClass = classmethod(base.ArchiveTests.setUpClass.__func__)

    def setUp(self):
        self.db = Database(self.bundle)
        self.app = benefits.App(self.db)
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.account = self.app._database_account_id("100")
        self.profile = self.db.profile(self.account)
        self.session = "public_beta_session_100"
        self.db.sessions[self.account, self.session] = "rich"
        self.n = 0
        self.timer = patch("archive_backend.service.time.time", side_effect=lambda: self.db.timestamp)
        self.timer.start()
        self.addCleanup(self.timer.stop)

    def request(self, **extra):
        self.n += 1
        return {"account_id": "100", "match_session_id": self.session,
                "config_hash": self.bundle.hash,
                "command": {"id": "game_runtime:public_beta_gift:" + str(self.n),
                            "kind": "benefit_claim", "track": "public_beta_login",
                            "tier_id": "public_beta_login", **extra}}

    def inventory(self):
        return self.profile["save"].get("content_inventory", {})

    def next_bundle(self, fields, *, compatible=True):
        """Build a separate real immutable fixture, without changing the game."""
        data=json.loads((self.bundle.directory/"bundle.json").read_text(encoding="utf-8"))
        row=next(row for row in data["configs"]["archive_benefit_rewards"]["rows"]
                 if row["reward_id"]=="public_beta_login")
        row.update(fields)
        if compatible:
            data["compatible_config_hashes"]={self.bundle.hash:{
                "commands":["benefit_claim"],"upgrade_commands":[]}}
        raw=json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
        digest=hashlib.sha256(raw).hexdigest()
        directory=self.bundle.directory.parent/digest
        directory.mkdir(exist_ok=True)
        for name,source in data["sources"].items():
            path=directory/name;path.parent.mkdir(exist_ok=True,parents=True)
            path.write_text(source,encoding="utf-8",newline="\n")
        (directory/"bundle.json").write_bytes(raw)
        self.assertNotEqual(digest,self.bundle.hash)
        return Bundle(directory)

    def test_configuration_free_manual_two_existing_special_tickets(self):
        row = self.bundle.tables["archive_benefit_rewards"]["public_beta_login"]
        self.assertTrue(row["enabled"])
        self.assertEqual(row["base_item_ids"], ["special_lottery_ticket"])
        self.assertEqual(row["base_counts"], ["2"])
        self.assertFalse(row["monthly_only"])
        self.assertFalse(row["auto_claim"])
        self.assertFalse(row.get("pass_item_ids"))
        self.assertEqual((row["starts_at"], row["ends_at"]), (0, 0))
        before = copy.deepcopy(self.profile["save"])
        self.service.profile({"account_id": "100"})
        self.assertEqual(self.profile["save"], before)
        self.assertFalse(self.db.ops, "A profile/eligibility read never grants or prepares")

    def test_free_and_month_card_accounts_both_receive_exactly_two(self):
        for account, monthly in (("100", False), ("101", True)):
            request = self.request()
            request["account_id"] = account
            database = self.app._database_account_id(account)
            self.db.sessions[database, self.session] = "standard"
            profile = self.db.profile(database)
            profile["entitlements"]["archive_pass"] = {"active": monthly}
            result = self.service.command(request)
            self.assertTrue(result["ok"])
            self.assertEqual(profile["save"]["content_inventory"], {"special_lottery_ticket": 2})
            self.assertEqual(result["response"]["rewards"][0]["count"], 2)
            self.assertEqual(result["profile"]["account_id"], account)

    def test_repeat_reconnect_and_other_session_cannot_grant_twice(self):
        first = self.request()
        self.assertTrue(self.service.command(first)["ok"])
        self.assertTrue(self.service.command(first)["ok"], "Identical receipt retries return original success")
        self.assertFalse(self.service.command(self.request())["ok"])
        self.session = "public_beta_reconnected_session"
        self.db.sessions[self.account, self.session] = "pure"
        self.assertFalse(self.service.command(self.request())["ok"])
        self.assertEqual(self.inventory(), {"special_lottery_ticket": 2})

    def test_five_am_boundary_not_midnight_and_lost_ack_keeps_original_day(self):
        self.db.timestamp = benefits.stamp("2026-10-29T15:59:59")
        self.assertTrue(self.service.command(self.request())["ok"])
        self.db.timestamp = benefits.stamp("2026-10-29T16:00:01")
        self.assertFalse(self.service.command(self.request())["ok"], "Beijing midnight is not a reset")
        self.db.timestamp = benefits.stamp("2026-10-29T21:00:00")
        request = self.request()
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.command(request)
        self.assertEqual(self.inventory(), {"special_lottery_ticket": 4})
        receipt_day = math.floor((self.db.timestamp + 10800) / 86400)
        self.db.timestamp += 86400
        recovered = self.service.command(request)
        self.assertTrue(recovered["ok"])
        self.assertEqual(recovered["response"]["period_id"], str(receipt_day))
        self.assertEqual(self.inventory(), {"special_lottery_ticket": 4})
        self.assertTrue(self.service.command(self.request())["ok"])
        self.assertEqual(self.inventory(), {"special_lottery_ticket": 6})

    def test_revision_conflict_and_two_concurrent_claims_grant_once(self):
        self.db.conflict = True
        requests = [self.request(), self.request()]
        barrier = threading.Barrier(2)
        results, errors = [], []
        def claim(request):
            try:
                barrier.wait(timeout=5)
                results.append(self.service.command(request))
            except Exception as error:
                errors.append(error)
        threads = [threading.Thread(target=claim, args=(request,)) for request in requests]
        for thread in threads: thread.start()
        for thread in threads: thread.join(timeout=15)
        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertFalse(errors)
        self.assertEqual(sum(row["ok"] is True for row in results), 1)
        self.assertEqual(self.inventory(), {"special_lottery_ticket": 2})

    def test_missing_wrong_account_and_stale_session_rejected_before_prepare(self):
        for mutation in ("missing", "unknown", "wrong_account", "forged_context"):
            request = self.request()
            if mutation == "missing": request.pop("match_session_id")
            elif mutation == "unknown": request["match_session_id"] = "unknown_session_100"
            elif mutation == "wrong_account": request["account_id"] = "200"
            if mutation == "forged_context":
                original = self.db.rpc
                def wrong_context(name, params):
                    if name == "match_profile_context":
                        return {"ok": True, "account_id": self.account,
                                "match_session_id": "different_session", "mode": "standard"}
                    return original(name, params)
                with patch.object(self.db, "rpc", side_effect=wrong_context):
                    with self.assertRaises(ArchiveError): self.service.command(request)
            else:
                with self.assertRaises(ArchiveError): self.service.command(request)
        self.assertFalse(self.db.ops)
        self.assertEqual(self.inventory(), {})

    def test_callers_cannot_choose_date_currency_amount_or_activity_window(self):
        for key, value in (("today", 999), ("day_key", "999"), ("event_at", 1),
                           ("count", 200), ("item_id", "lottery_ticket"), ("starts_at", 0)):
            with self.assertRaises(ArchiveError):
                self.service.command(self.request(**{key: value}))
        self.assertFalse(self.db.ops)

    def test_activity_start_end_and_switch_are_server_configured(self):
        row = self.bundle.tables["archive_benefit_rewards"]["public_beta_login"]
        for fields in ({"starts_at": self.db.timestamp+1}, {"ends_at": self.db.timestamp}, {"enabled": False}):
            with patch.dict(row, fields):
                self.assertFalse(self.service.command(self.request())["ok"])
                self.assertEqual(self.inventory(), {})
        self.assertTrue(self.service.command(self.request())["ok"])
        self.assertEqual(self.inventory(), {"special_lottery_ticket": 2})

    def test_completed_receipt_survives_activity_switch_off_without_new_grants(self):
        request = self.request()
        self.assertTrue(self.service.command(request)["ok"])
        row = self.bundle.tables["archive_benefit_rewards"]["public_beta_login"]
        with patch.dict(row, {"enabled": False}):
            self.assertTrue(self.service.command(request)["ok"], "Committed receipt stays immutable when disabled")
            self.assertFalse(self.service.command(self.request())["ok"])
        self.assertEqual(self.inventory(), {"special_lottery_ticket": 2})

    def test_explicitly_compatible_old_hash_cannot_bypass_new_bundle_switch(self):
        request=self.request()
        self.assertTrue(self.service.command(request)["ok"])
        closed=self.next_bundle({"enabled":False})
        self.service=ArchiveService(self.app,closed,self.lua)
        self.assertTrue(self.service.command(request)["ok"],"Old completed receipt remains readable")
        self.db.timestamp+=86400
        denied=self.service.command(self.request()) # intentionally still uses old config_hash
        self.assertFalse(denied["ok"])
        self.assertEqual(denied["error"],"public_beta_activity_inactive")
        self.assertEqual(self.inventory(),{"special_lottery_ticket":2})

    def test_compatible_old_pending_receipt_uses_current_activity_authority(self):
        request=self.request()
        with patch.object(self.service,"finish_prepared",return_value={"ok":False,"error":"paused_fixture"}):
            self.service.command(request)
        operation=next(iter(self.db.ops))[1]
        closed=self.next_bundle({"enabled":False})
        self.service=ArchiveService(self.app,closed,self.lua)
        result=self.service.finish_prepared(self.account,operation,self.db.resume(self.account,operation))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"],"public_beta_activity_inactive")
        self.assertTrue(result["terminal"])
        self.assertEqual(self.inventory(),{})

    def test_compatible_old_hash_obeys_current_new_bundle_start_and_end(self):
        for fields in ({"starts_at":self.db.timestamp+1},{"ends_at":self.db.timestamp}):
            bounded=self.next_bundle(fields)
            self.service=ArchiveService(self.app,bounded,self.lua)
            result=self.service.command(self.request())
            self.assertFalse(result["ok"])
            self.assertEqual(result["error"],"public_beta_activity_inactive")
            self.assertEqual(self.inventory(),{})
        opened=self.next_bundle({"starts_at":self.db.timestamp,"ends_at":self.db.timestamp+1})
        self.service=ArchiveService(self.app,opened,self.lua)
        request=self.request()
        self.assertTrue(self.service.command(request)["ok"])
        self.db.timestamp+=1
        self.assertTrue(self.service.command(request)["ok"],"Done receipt survives the exclusive end boundary")
        self.assertEqual(self.service.command(self.request())["error"],"public_beta_activity_inactive")
        self.assertEqual(self.inventory(),{"special_lottery_ticket":2})

    def test_unapproved_old_hash_stays_rejected_without_changing_compatibility_policy(self):
        request=self.request()
        self.assertTrue(self.service.command(request)["ok"])
        closed=self.next_bundle({"enabled":False},compatible=False)
        self.service=ArchiveService(self.app,closed,self.lua)
        result=self.service.command(request)
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"],"archive_config_mismatch")
        self.assertEqual(self.inventory(),{"special_lottery_ticket":2})

    def test_new_receipt_is_session_scoped_and_pending_recovery_validates_binding(self):
        request = self.request()
        original = self.service.finish_prepared
        with patch.object(self.service, "finish_prepared", return_value={"ok": False, "error": "paused_fixture"}):
            self.service.command(request)
        operation = next(iter(self.db.ops))[1]
        self.assertTrue(operation.startswith(self.session + MARKER))
        self.db.sessions.clear()
        with self.assertRaises(ArchiveError):
            original(self.account, operation, self.db.resume(self.account, operation))
        self.assertEqual(self.inventory(), {})
        self.db.sessions[self.account, self.session] = "rich"
        self.assertTrue(original(self.account, operation, self.db.resume(self.account, operation))["ok"])
        self.assertEqual(self.inventory(), {"special_lottery_ticket": 2})


if __name__ == "__main__":
    unittest.main()
