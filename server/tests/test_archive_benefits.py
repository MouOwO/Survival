"""Welfare claims run the real packaged Lua reducer through durable RPC receipts."""
import copy
import math
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_archive_backend as base
from archive_backend.daily_limits import snapshot as quota_snapshot
from archive_backend.service import ArchiveError


def stamp(value):
    return int(datetime.fromisoformat(value).replace(tzinfo=timezone.utc).timestamp())


class Database(base.Database):
    def __init__(self, bundle):
        super().__init__(bundle)
        self.timestamp = stamp("2026-10-21T04:00:00")  # Beijing noon.
        self.contexts = {}

    def resume(self, account, operation):
        result = super().resume(account, operation)
        result["event_at"] = self.ops[account, operation]["event_at"]
        return result

    def rpc(self, name, params):
        if name == "match_profile_context":
            session=params["p_session"]
            return {"ok":True,"account_id":params["p_account"],"match_session_id":session,
                    "mode":self.contexts[session]}
        if name == "archive_prepare":
            with self.lock:
                key = params["p_account"], params["p_id"]
                new = key not in self.ops
                if new:
                    command = copy.deepcopy(params["p_command"])
                    day = math.floor((self.timestamp + 10800) / 86400)
                    command.update(today=day, day_key=str(day))
                    self.ops[key] = {"command": command, "done": False,
                        "fingerprint": params["p_fingerprint"], "hash": params["p_hash"],
                        "pass": self._has_pass(key[0]),
                        "event_at": self.timestamp}
                return super().rpc(name, params)
        if name == "archive_commit_lottery":
            kind = self.ops[params["p_account"], params["p_id"]]["command"]["kind"]
            assert kind in ("lottery_draw", "lottery_exchange", "lottery_read", "commerce_purchase", "benefit_claim")
        return super().rpc(name, params)

    def _has_pass(self,account):
        entitlement=self.profile(account)["entitlements"].get("archive_pass",{})
        expiry=entitlement.get("expires_at")
        starts=entitlement.get("starts_at")
        return (entitlement.get("active") is True and (expiry is None or expiry>self.timestamp)
                and (starts is None or starts<=self.timestamp))


class App(base.App):
    def _public_response(self,value,database_account,public_account):
        value=super()._public_response(value,database_account,public_account)
        if isinstance(value,dict) and value.get("account_id")==database_account:
            value["account_id"]=public_account
        return value


class BenefitTests(unittest.TestCase):
    setUpClass = classmethod(base.ArchiveTests.setUpClass.__func__)

    def setUp(self):
        self.db = Database(self.bundle)
        self.app = App(self.db)
        self.service = base.ArchiveService(self.app, self.bundle, self.lua)
        self.account = self.app._database_account_id("100")
        self.profile = self.db.profile(self.account)
        self.n = 0
        self.timer = patch("archive_backend.service.time.time", side_effect=lambda: self.db.timestamp)
        self.timer.start()
        self.addCleanup(self.timer.stop)

    command = base.ArchiveTests.command
    send = base.ArchiveTests.send

    def claim(self, tier, track=None):
        if track is None:
            track = self.bundle.tables["archive_benefit_rewards"][tier]["track"]
        return self.send("benefit_claim", track=track, tier_id=tier)

    def credit_time(self, seconds, *, event_at=None, weighted=None, receipt=None):
        self.n += 1
        operation = receipt or "online:benefittest:" + str(self.n)
        event_at = self.db.timestamp if event_at is None else event_at
        if (self.account, operation) not in self.db.ops:
            self.db.ops[self.account, operation] = {"command": {
                "id": operation, "kind": "online_checkpoint", "session": operation,
                "actual_seconds": seconds, "map_seconds": weighted if weighted is not None else seconds,
                "day_key": str(math.floor((event_at + 10800) / 86400))},
                "done": False, "fingerprint": operation, "hash": self.bundle.hash,
                "pass": False, "event_at": event_at}
        prepared = self.db.resume(self.account, operation)
        return self.service.finish_prepared(self.account, operation, prepared)

    def bucket(self, timestamp=None, weekly=False):
        value = self.db.timestamp if timestamp is None else timestamp
        day = math.floor((value + 10800) / 86400)
        key = math.floor((day + 3) / 7) if weekly else day
        return self.profile["save"]["archive"]["benefits"]["weeks" if weekly else "days"][str(key)]

    def inventory(self):
        return self.profile["save"].get("content_inventory", {})

    def month_card(self, active=True):
        self.profile["entitlements"]["archive_pass"] = {"active": active}

    def test_configuration_adds_login_tier_and_preserves_all_existing_tiers(self):
        rows = self.bundle.tables["archive_benefit_rewards"]
        self.assertEqual(len(rows), 21)
        login=rows["daily_time_0"]
        self.assertEqual(login["required"],0)
        self.assertTrue(login["monthly_only"])
        self.assertFalse(login["auto_claim"])
        self.assertFalse(login.get("base_item_ids"))
        self.assertEqual(login["pass_item_ids"],["special_lottery_ticket"])
        monthly = rows["daily_time_150"]
        self.assertEqual(dict(zip(monthly["pass_item_ids"], map(int, monthly["pass_counts"]))), {
            "lottery_ticket": 2, "welfare_zongzi": 2,
            "special_lottery_ticket": 1, "lottery_ember_of_legacy": 2})
        self.assertIn("systems/archive_benefit_rewards.lua", (self.bundle.directory / "bundle.json").read_text(encoding="utf-8"))

    def test_multiple_sessions_accumulate_actual_seconds_not_month_card_weight(self):
        self.month_card()
        self.assertTrue(self.credit_time(900, weighted=1800)["ok"])
        self.assertFalse(self.claim("daily_time_30")["ok"])
        self.assertTrue(self.credit_time(900, weighted=1800)["ok"])
        self.assertEqual(self.bucket()["seconds"], 1800)
        self.assertEqual(self.bucket(weekly=True)["seconds"], 1800)
        self.assertTrue(self.claim("daily_time_30")["ok"])
        self.assertEqual(self.inventory()["lottery_ticket"], 2)

    def test_every_time_tier_grants_once_and_month_card_full_totals(self):
        self.month_card()
        self.service.profile({"account_id":"100"})
        self.assertTrue(self.claim("daily_time_0")["ok"])
        self.assertTrue(self.credit_time(150 * 60)["ok"])
        for minute in (30, 60, 90, 120, 150):
            self.assertTrue(self.claim("daily_time_" + str(minute))["ok"])
        self.assertEqual(self.inventory(), {"lottery_ticket": 14, "welfare_zongzi": 6,
            "lottery_ember_of_legacy": 3, "special_lottery_ticket": 2})
        stats = copy.deepcopy(self.profile["save"]["gameplay_stats"])
        self.assertFalse(self.claim("daily_time_150")["ok"])
        self.assertEqual(self.inventory()["lottery_ember_of_legacy"], 3)
        self.assertEqual(self.profile["save"]["gameplay_stats"], stats, "Stackable effects are projected, not permanently added again")

    def test_month_card_login_requires_explicit_zero_time_claim_once_across_reconnects(self):
        self.month_card()
        for _ in range(3):
            result=self.service.profile({"account_id":"100"})
            self.assertFalse(result["save"].get("content_inventory"))
        self.assertEqual(self.db.ops,{},"Loading a month-card profile cannot create a login receipt")
        self.assertTrue(self.claim("daily_time_0")["ok"])
        for _ in range(3):
            self.service.profile({"account_id":"100"})
            self.assertFalse(self.claim("daily_time_0")["ok"])
        self.assertEqual(self.inventory(),{"special_lottery_ticket":1})
        self.assertEqual(self.bucket()["seconds"],0)
        self.assertIn("daily_time_0",self.bucket()["claimed"])

    def test_online_checkpoint_records_time_without_issuing_login_reward(self):
        self.month_card()
        self.credit_time(60)
        self.service.profile({"account_id":"100"})
        self.assertEqual(self.inventory(),{})
        self.assertNotIn("daily_time_0",self.bucket()["claimed"])
        self.assertTrue(self.claim("daily_time_0")["ok"])
        self.assertEqual(self.inventory(),{"special_lottery_ticket":1})

    def test_free_and_expired_accounts_cannot_consume_login_tier_before_activation(self):
        for entitlement in ({},{"active":False},{"active":True,"expires_at":self.db.timestamp}):
            self.profile["entitlements"]["archive_pass"]=entitlement
            self.service.profile({"account_id":"100"})
            self.assertFalse(self.claim("daily_time_0")["ok"])
            self.assertFalse(self.profile["save"]["archive"].get("benefits",{}).get("days",{}))
            self.assertEqual(self.inventory(),{})
        self.month_card()
        self.service.profile({"account_id":"100"})
        self.assertEqual(self.inventory(),{},"Buying a card does not automatically issue a login reward")
        self.assertTrue(self.claim("daily_time_0")["ok"])
        self.assertEqual(self.inventory(),{"special_lottery_ticket":1},"Buying a card later in the day still allows its login tier")

    def test_login_manual_claim_lost_reply_recovers_without_second_ticket(self):
        self.month_card()
        request=self.command("benefit_claim",track="daily_time",tier_id="daily_time_0")
        self.db.lose_reply=True
        with self.assertRaises(TimeoutError):
            self.service.command(request)
        self.assertEqual(self.inventory(),{"special_lottery_ticket":1})
        self.service.profile({"account_id":"100"})
        self.assertTrue(self.service.command(request)["ok"])
        self.assertEqual(self.inventory(),{"special_lottery_ticket":1})

    def test_login_manual_claim_refreshes_at_five_not_midnight(self):
        self.month_card()
        self.db.timestamp=stamp("2026-10-21T15:59:59")
        self.service.profile({"account_id":"100"})
        self.assertTrue(self.claim("daily_time_0")["ok"])
        self.db.timestamp=stamp("2026-10-21T16:00:01")
        self.service.profile({"account_id":"100"})
        self.assertFalse(self.claim("daily_time_0")["ok"])
        self.assertEqual(self.inventory(),{"special_lottery_ticket":1})
        self.db.timestamp=stamp("2026-10-21T21:00:00")
        self.service.profile({"account_id":"100"})
        self.assertEqual(self.inventory(),{"special_lottery_ticket":1},"Refreshing the next day still waits for a click")
        self.assertTrue(self.claim("daily_time_0")["ok"])
        self.assertEqual(self.inventory(),{"special_lottery_ticket":2})

    def test_renewed_month_card_can_click_again_after_expiry_race(self):
        self.profile["entitlements"]["archive_pass"]={"active":True,"expires_at":self.db.timestamp+1}
        original=self.service.command
        def expire(request):
            self.db.timestamp+=2
            return original(request)
        self.service.command=expire
        self.assertFalse(self.claim("daily_time_0")["ok"])
        self.assertEqual(self.inventory(),{})
        self.service.command=original
        self.profile["entitlements"]["archive_pass"]={"active":True,"expires_at":self.db.timestamp+86400}
        self.service.profile({"account_id":"100"})
        self.assertEqual(self.inventory(),{})
        self.assertTrue(self.claim("daily_time_0")["ok"])
        self.assertEqual(self.inventory(),{"special_lottery_ticket":1})

    def test_existing_login_claim_marker_survives_switch_from_automatic_to_manual(self):
        self.month_card()
        day=str(math.floor((self.db.timestamp+10800)/86400))
        old_marker={"at":self.db.timestamp-60,"has_pass":1}
        self.profile["save"]["archive"]={"benefits":{"version":1,"days":{day:{"seconds":0,"wins":0,
            "claimed":{"daily_time_0":copy.deepcopy(old_marker)}}},"weeks":{}}}
        self.profile["save"]["content_inventory"]={"special_lottery_ticket":1}
        before=copy.deepcopy(self.profile["save"])
        self.service.profile({"account_id":"100"})
        self.assertFalse(self.claim("daily_time_0")["ok"])
        self.assertEqual(self.profile["save"],before,"Disabling auto delivery never resets or tops up today's existing claim")

    def test_base_time_tier_totals_without_month_card(self):
        self.credit_time(9000)
        for minute in (30, 60, 90, 120, 150):
            self.assertTrue(self.claim("daily_time_" + str(minute))["ok"])
        self.assertEqual(self.inventory(), {"lottery_ticket": 7, "welfare_zongzi": 3, "lottery_ember_of_legacy": 1})

    def test_weekly_tiers_double_base_and_only_last_three_have_month_card_gold(self):
        self.month_card()
        self.credit_time(1080 * 60)
        for minute in (120, 240, 360, 480, 600, 720, 840, 960, 1080):
            before=copy.deepcopy(self.inventory())
            self.assertTrue(self.claim("weekly_time_" + str(minute))["ok"])
            self.assertEqual(self.inventory().get("special_lottery_ticket",0)-before.get("special_lottery_ticket",0),
                             1 if minute>=840 else 0)
        self.assertEqual(self.inventory(), {"lottery_ticket": 78, "special_lottery_ticket": 3})

    def test_real_win_counts_once_before_double_clear_and_acquisition_cap(self):
        self.profile["save"]["content_inventory"] = {"commerce_p005": 1}
        request = self.command("clear", difficulty_id="n1", count=1)
        self.assertTrue(self.service.command(request)["ok"])
        self.assertTrue(self.service.command(request)["ok"])
        self.assertEqual(self.bucket()["wins"], 1)
        self.assertEqual(self.profile["save"]["archive"]["clear_counts"]["n1"],2)
        day = str(math.floor((self.db.timestamp + 10800) / 86400))
        self.profile["save"]["archive"].setdefault("daily", {}).setdefault(day, {})["clear_total"] = 20
        self.assertTrue(self.send("clear", difficulty_id="n1", count=1)["ok"])
        self.assertEqual(self.bucket()["wins"], 1, "The same match receipt cannot invent a second victory")
        different = self.command("clear", difficulty_id="n1", count=1)
        different["command"]["id"] = "othermatch:clear"
        self.assertTrue(self.service.command(different)["ok"])
        self.assertEqual(self.bucket()["wins"], 2)

    def test_win_tiers_month_card_rewards_and_all_modes_shared(self):
        self.month_card()
        for win, kind in enumerate(("clear", "standard_clear", "rich_clear", "cold_clear", "scourge_clear"), 1):
            request = self.command(kind, difficulty_id="n1", count=1)
            session = "benefitmatch" + str(win)
            self.db.contexts[session] = {"clear":"pure"}.get(kind,kind.removesuffix("_clear"))
            request["match_session_id"] = session
            request["command"]["id"] = session + ":" + kind
            self.assertTrue(self.service.command(request)["ok"])
        self.assertEqual(self.bucket()["wins"], 5)
        for win in range(1, 6):
            before=copy.deepcopy(self.inventory())
            self.assertTrue(self.claim("daily_win_" + str(win))["ok"])
            if win==3:
                self.assertEqual(self.inventory()["lottery_ticket"]-before.get("lottery_ticket",0),2)
                self.assertEqual(self.inventory()["special_lottery_ticket"]-before.get("special_lottery_ticket",0),1)
            elif win==4:
                self.assertEqual(self.inventory()["lottery_ticket"]-before.get("lottery_ticket",0),1)
                self.assertEqual(self.inventory().get("special_lottery_ticket",0)-before.get("special_lottery_ticket",0),0)
        self.assertEqual(self.inventory(), {"lottery_ticket": 9, "special_lottery_ticket": 2})

    def test_revised_schedule_preserves_claimed_tiers_and_completed_receipts(self):
        self.month_card()
        self.credit_time(150*60)
        daily=self.bucket()
        old_claim={"at":self.db.timestamp-60,"has_pass":1}
        for tier in ("daily_time_150","daily_win_3","daily_win_4"):
            daily["claimed"][tier]=copy.deepcopy(old_claim)
        daily["wins"]=5
        self.profile["save"]["content_inventory"]={"lottery_ticket":8,"special_lottery_ticket":3}
        operation="oldschedule:benefit:claimed"
        old_response={"ok":True,"tier_id":"daily_time_150","rewards":[{"id":"special_lottery_ticket","count":2}]}
        self.db.ops[self.account,operation]={"command":{"id":operation,"kind":"benefit_claim",
            "track":"daily_time","tier_id":"daily_time_150"},"done":True,"fingerprint":operation,
            "hash":"a"*64,"pass":True,"event_at":self.db.timestamp-60,"response":copy.deepcopy(old_response)}
        saved=copy.deepcopy(self.profile["save"])
        result=self.service.finish_prepared(self.account,operation,self.db.resume(self.account,operation))
        self.assertEqual(result["response"],old_response,"Completed historical receipts keep their recorded reward")
        for tier in ("daily_time_150","daily_win_3","daily_win_4"):
            self.assertFalse(self.claim(tier)["ok"],"A changed schedule cannot reopen a previously claimed tier")
        self.assertEqual(self.profile["save"],saved,"No reset, top-up or retroactive deduction is allowed")
        self.assertTrue(self.claim("weekly_time_120")["ok"])
        self.assertEqual(self.inventory(),{"lottery_ticket":12,"special_lottery_ticket":3},
                         "Unclaimed weekly tiers use the revised double-base reward without early gold")

    def test_online_receipt_lost_reply_and_claim_lost_reply_never_double(self):
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.credit_time(1800, receipt="online:benefit-lost-reply")
        self.assertTrue(self.credit_time(1800, receipt="online:benefit-lost-reply")["ok"])
        self.assertEqual(self.bucket()["seconds"], 1800)
        request = self.command("benefit_claim", track="daily_time", tier_id="daily_time_30")
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.command(request)
        self.assertTrue(self.service.command(request)["ok"])
        self.assertEqual(self.inventory()["lottery_ticket"], 1)

    def test_revision_conflict_preserves_unrelated_stats_and_only_grants_once(self):
        self.credit_time(1800)
        before = self.profile["save"]["gameplay_stats"]["initial_wood"]
        self.db.conflict = True
        self.assertTrue(self.claim("daily_time_30")["ok"])
        self.assertEqual(self.inventory()["lottery_ticket"], 1)
        self.assertEqual(self.profile["save"]["gameplay_stats"]["initial_wood"], before + 100)

    def test_both_calendars_split_at_monday_five_and_late_outbox_keeps_new_bucket(self):
        boundary = stamp("2026-10-25T21:00:00")  # Monday 05:00 Beijing.
        self.db.timestamp = boundary + 30
        self.credit_time(60, event_at=boundary + 30)
        self.assertEqual(self.bucket(boundary - 1)["seconds"], 30)
        self.assertEqual(self.bucket(boundary + 1)["seconds"], 30)
        self.assertEqual(self.bucket(boundary - 1, weekly=True)["seconds"], 30)
        self.assertEqual(self.bucket(boundary + 1, weekly=True)["seconds"], 30)
        self.credit_time(900, event_at=boundary - 30)
        self.assertEqual(self.bucket(boundary - 1)["seconds"], 930)
        self.assertEqual(self.bucket(boundary + 1)["seconds"], 30)

    def test_day_does_not_reset_at_midnight_and_existing_caps_use_five(self):
        before_midnight = stamp("2026-10-21T15:59:59")
        after_midnight = before_midnight + 2
        before_five = stamp("2026-10-21T20:59:59")
        after_five = before_five + 2
        day = str(math.floor((before_midnight + 10800) / 86400))
        self.profile["save"]["archive"]["daily"] = {day: {"clear_total": 20}}
        for now in (before_midnight, after_midnight, before_five):
            projected = quota_snapshot(self.profile, self.bundle, now)
            self.assertEqual(projected["day_key"], day)
            self.assertEqual(projected["by_key"]["clear"]["remaining"], 0)
        after = quota_snapshot(self.profile, self.bundle, after_five)
        self.assertNotEqual(after["day_key"], day)
        self.assertEqual(after["by_key"]["clear"]["remaining"], 20)

    def test_immutable_prepared_claim_time_and_month_card_survive_reset_retry(self):
        boundary = stamp("2026-10-21T21:00:00")
        self.db.timestamp = boundary - 1
        self.credit_time(1800)
        self.month_card()
        request = self.command("benefit_claim", track="daily_time", tier_id="daily_time_30")
        original = self.service.settle
        def timeout(*args, **kwargs):
            raise TimeoutError("worker interrupted before commit")
        self.service.settle = timeout
        with self.assertRaises(TimeoutError):
            self.service.command(request)
        self.db.timestamp = boundary + 1
        self.month_card(False)
        self.service.settle = original
        self.assertTrue(self.service.command(request)["ok"])
        self.assertEqual(self.inventory()["lottery_ticket"], 2)
        self.assertIn("daily_time_30", self.bucket(boundary - 1)["claimed"])
        self.assertFalse(self.claim("daily_time_30")["ok"], "Previous day's progress does not unlock today's tier")

    def test_zongzi_overflow_keeps_other_rewards_and_never_converts_to_points(self):
        self.profile["save"]["content_inventory"] = {"welfare_zongzi": 149}
        self.credit_time(9000)
        self.assertTrue(self.claim("daily_time_150")["ok"])
        self.assertEqual(self.inventory(), {"welfare_zongzi": 150, "lottery_ticket": 2, "lottery_ember_of_legacy": 1})
        self.assertEqual(self.profile["save"]["archive"].get("commerce", {}).get("balances", {}).get("shop_points", 0), 0)

    def test_caller_cannot_supply_progress_clock_reward_quantity_or_mismatched_track(self):
        for extra in ({"event_at": 1}, {"actual_seconds": 100000}, {"count": 99}):
            with self.assertRaises(ArchiveError):
                self.service.validate(dict(id="benefit:test", kind="benefit_claim", track="daily_time", tier_id="daily_time_30", **extra))
        with self.assertRaises(ArchiveError):
            self.service.validate(dict(id="benefit:test", kind="benefit_claim", track="weekly_time", tier_id="daily_time_30"))
        with self.assertRaises(ArchiveError):
            self.service.validate(dict(id="benefit:test", kind="online_checkpoint", actual_seconds=99999))
        self.assertEqual(self.service.commerce_unique_block(self.profile, {"enabled": False,
            "item_id": "lottery_ember_of_legacy", "grants": {}}), "product_unavailable")

    def test_disabled_configuration_can_stop_new_grants_without_deleting_saved_inventory(self):
        self.credit_time(9000)
        self.profile["save"]["content_inventory"]={"lottery_ember_of_legacy":3,"welfare_zongzi":4}
        row=self.bundle.tables["archive_benefit_rewards"]["daily_time_150"]
        row["enabled"]=False
        try:
            with self.assertRaises(ArchiveError):
                self.claim("daily_time_150")
            # The reducer independently validates availability, even when an
            # older already-prepared command bypasses the HTTP validator.
            result=self.service.settle(self.profile,{"id":"disabled:benefit","kind":"benefit_claim",
                "track":"daily_time","tier_id":"daily_time_150","event_at":self.db.timestamp},False)
            self.assertFalse(result["ok"])
            self.assertEqual(self.inventory(),{"lottery_ember_of_legacy":3,"welfare_zongzi":4})
        finally:
            row["enabled"]=True


if __name__ == "__main__":
    unittest.main()
