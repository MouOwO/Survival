"""Offline game/server archive contract and immutable receipt regressions.

The tests run the real packaged Lua worker against an isolated account. Set
SURVIVAL_ARCHIVE_FULL_BUNDLE and SURVIVAL_ARCHIVE_SERVICE_CANDIDATE to exercise
the exact release candidate. They never connect to ECS or write player data.
"""
from __future__ import annotations

import copy
import hashlib
import importlib
import json
import os
from pathlib import Path
import sys
import tempfile
from types import ModuleType
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(ROOT))
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveError, ArchiveService, FIELDS
from tools.test_endless_archive_upgrade import App, ReceiptDatabase


class FullArchiveSyncTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        global ArchiveError, ArchiveService, FIELDS, Bundle
        candidate = os.environ.get("SURVIVAL_ARCHIVE_SERVICE_CANDIDATE")
        if candidate:
            package = ModuleType("offline_full_archive_backend")
            package.__path__ = [str(Path(candidate).resolve().parent),
                                str(ROOT / "server/archive_backend")]
            sys.modules[package.__name__] = package
            service = importlib.import_module(package.__name__ + ".service")
            ArchiveError, ArchiveService, FIELDS = service.ArchiveError, service.ArchiveService, service.FIELDS
            Bundle = importlib.import_module(package.__name__ + ".bundle").Bundle
        directory = os.environ.get("SURVIVAL_ARCHIVE_FULL_BUNDLE")
        cls.game_hash_before = (ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua").read_bytes()
        cls.pointer_before = (ROOT / "server/bundles/current.json").read_bytes()
        if not directory:
            cls.temp = tempfile.TemporaryDirectory(prefix="full-archive-offline-")
            cls.addClassCleanup(cls.temp.cleanup)
            destination = Path(cls.temp.name)
            directory = destination / build(ROOT, destination, update_game_config=False)
        cls.bundle = Bundle(Path(directory))
        cls.lua = os.environ.get("LUA_EXECUTABLE", "C:/Program Files/lua/bin/lua5.1.exe")
        if not Path(cls.lua).is_file():
            raise RuntimeError("Set LUA_EXECUTABLE to a Lua 5.1 executable")

    def setUp(self):
        self.db = ReceiptDatabase(self.bundle)
        self.service = ArchiveService(App(self.db), self.bundle, self.lua)

    @property
    def archive(self):
        return self.db.profile["save"]["archive"]

    @property
    def stats(self):
        return self.db.profile["save"]["gameplay_stats"]

    def command(self, kind, match="offline-full-match", **fields):
        return {"id": match + ":" + kind + ":operation", "kind": kind, **fields}

    def payload(self, kind, match="offline-full-match", digest=None, **fields):
        return {"account_id": "100", "config_hash": digest or self.bundle.hash,
                "command": self.command(kind, match, **fields)}

    def send(self, kind, match="offline-full-match", **fields):
        result = self.service.command(self.payload(kind, match, **fields))
        self.assertTrue(result["ok"], result)
        return result

    def effects(self, row):
        return dict(zip(row["effect_ids"], map(float, row["effect_values"])))

    def expected_effects(self, rows):
        result = {}
        for row in rows:
            for field, amount in self.effects(row).items():
                result[field] = result.get(field, 0) + amount
        return result

    def test_test_bundle_does_not_change_game_configuration(self):
        self.assertEqual((ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua").read_bytes(),
                         self.game_hash_before)
        self.assertEqual((ROOT / "server/bundles/current.json").read_bytes(), self.pointer_before)

    def test_every_production_game_command_has_an_accepted_field_contract(self):
        samples = {
            "commerce_catalog": {},
            "commerce_purchase": {"sku": next(iter(self.bundle.tables["commerce_catalog"])), "request_id": "offline-purchase-123"},
            "clear": {"difficulty_id": "n1", "count": 1, "cooperative_win": 0, "day_key": "99999"},
            "boss_kill": {}, "endless": {"wave": 1, "difficulty": 1},
            "endless_reconcile": {}, "starjoy_reconcile": {}, "welfare_reconcile": {},
            "challenge": {"challenge_id": "shadow_1", "kill_sequence": 1, "difficulty_id": "n1", "day_key": "99999"},
            "social_draw": {"pool_id": "friend"}, "promotion": {"fragment_id": "fragment_01", "day_key": "99999"},
            "daily_init": {"today": 99999}, "daily_claim": {"today": 99999, "target_day": 20000},
            "vip_claim": {"reward_id": "vip_privilege_01"}, "vip_purchase": {"reward_id": "vip_package_01"},
            "title_equip": {"title_id": "peak_perfection"},
            "work_upgrade": {"item_id": "work_01", "expected_level": 0},
            "building_upgrade": {"item_id": "building_01", "expected_level": 0},
            "lottery_draw": {"pool_id": "map", "count": 1, "request_id": "offline-draw"},
            "lottery_exchange": {"pool_id": "map", "item_id": next(iter(self.bundle.tables["lottery_item_definitions"])), "request_id": "offline-exchange"},
            "lottery_read": {"pool_id": "map", "revision": "offline-v1", "read_action": "visit", "request_id": "offline-read"},
        }
        self.assertEqual(set(samples), set(FIELDS))
        for kind, fields in samples.items():
            with self.subTest(kind=kind):
                command = self.command(kind, **fields)
                original = copy.deepcopy(command)
                accepted = self.service.validate(command)
                self.assertEqual(accepted["kind"], kind)
                self.assertNotIn("day_key", accepted)
                self.assertNotIn("today", accepted)
                self.assertEqual(command, original)
        for kind in ("faith_cheat", "social_ticket_cheat", "online_checkpoint", "grant"):
            with self.subTest(forbidden=kind):
                with self.assertRaisesRegex(ArchiveError, "^archive_command_fields_invalid$"):
                    self.service.validate(self.command(kind))

    def test_solo_clear_records_every_difficulty_and_first_win_rewards(self):
        for difficulty in range(1, 21):
            with self.subTest(difficulty=difficulty):
                self.db = ReceiptDatabase(self.bundle)
                self.service = ArchiveService(App(self.db), self.bundle, self.lua)
                before = copy.deepcopy(self.stats)
                self.send("clear", "offline-n" + str(difficulty), difficulty_id="n" + str(difficulty),
                          count=1, cooperative_win=0, day_key="99999")
                self.assertEqual(self.archive["clear_counts"], {"n" + str(difficulty): 1})
                self.assertEqual(self.archive.get("cooperative_clear_count", 0), 0)
                reward_rows = [row for row in self.bundle.configs["archive_achievements"]["rows"]
                               if row["enabled"] and row["difficulty_id"] == "n" + str(difficulty)
                               and row["required_count"] <= 1]
                reward_rows += [row for row in self.bundle.configs["archive_welfare_rewards"]["rows"]
                                if row["enabled"] and row["progress_kind"] == "victory" and row["required_wins"] <= 1]
                for row in reward_rows:
                    self.assertTrue(self.archive["completed"][row["achievement_id"]])
                for field, delta in self.expected_effects(reward_rows).items():
                    self.assertEqual(self.stats[field] - before[field], delta, field)
                rules = self.bundle.tables["archive_building_rules"]["default"]
                self.assertEqual(self.archive["buildings"]["faith"], rules["faith_per_clear"])
                self.assertEqual(self.archive["buildings"]["earned_by_day"], {"20000": rules["faith_per_clear"]})

    def test_same_match_early_and_regular_clear_cannot_double_record(self):
        first = self.payload("clear", difficulty_id="n1", count=1, cooperative_win=0, day_key="19999")
        self.assertTrue(self.service.command(first)["ok"])
        saved = copy.deepcopy(self.db.profile)
        second = copy.deepcopy(first)
        second["command"]["id"] = "offline-full-match:regular-clear-after-early"
        second["command"]["day_key"] = "20001"
        self.assertTrue(self.service.command(second)["ok"])
        self.assertEqual(self.db.profile, saved)
        self.assertEqual(self.db.commit_count, 1)

    def test_clear_lost_reply_retries_same_receipt_once(self):
        payload = self.payload("clear", difficulty_id="n20", count=1, cooperative_win=1)
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.command(payload)
        saved = copy.deepcopy(self.db.profile)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.db.profile, saved)
        self.assertEqual(self.archive["clear_counts"], {"n20": 1})
        self.assertEqual(self.archive["cooperative_clear_count"], 1)
        self.assertEqual(self.db.commit_count, 1)

    def test_cooperative_win_counts_one_per_match_and_unlocks_configured_welfare(self):
        first = next(row for row in self.bundle.configs["archive_welfare_rewards"]["rows"]
                     if row["enabled"] and row["progress_kind"] == "cooperative")
        target = first["required_wins"]
        for match in range(1, target + 1):
            payload = self.payload("clear", "offline-coop-" + str(match), difficulty_id="n1", count=1, cooperative_win=1)
            self.assertTrue(self.service.command(payload)["ok"])
            self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.archive["clear_counts"]["n1"], target)
        self.assertEqual(self.archive["cooperative_clear_count"], target)
        self.assertTrue(self.archive["completed"][first["achievement_id"]])
        saved = copy.deepcopy(self.stats)
        self.send("welfare_reconcile", "offline-after-coop")
        self.assertEqual(self.stats, saved)

    def test_welfare_backfill_uses_saved_solo_wins_without_inventing_cooperative_wins(self):
        self.archive["clear_counts"] = {"n1": 10}
        self.send("welfare_reconcile")
        victory = [row for row in self.bundle.configs["archive_welfare_rewards"]["rows"]
                   if row["enabled"] and row["progress_kind"] == "victory" and row["required_wins"] <= 10]
        self.assertTrue(all(self.archive["completed"].get(row["achievement_id"]) for row in victory))
        self.assertFalse(any(self.archive["completed"].get(row["achievement_id"])
                             for row in self.bundle.configs["archive_welfare_rewards"]["rows"]
                             if row["progress_kind"] == "cooperative"))
        saved = copy.deepcopy(self.stats)
        self.send("welfare_reconcile", "offline-next-match")
        self.assertEqual(self.stats, saved)

    def test_starjoy_saved_points_award_tiers_once_and_preserve_spent_progress(self):
        self.stats["starjoy_points"] = 200
        before = copy.deepcopy(self.stats)
        self.send("starjoy_reconcile")
        self.assertEqual(self.stats["starjoy_reward_level"], 2)
        self.assertEqual(self.stats["starjoy_points_earned"], 200)
        earned = [row for row in self.bundle.configs["archive_starjoy_levels"]["rows"]
                  if row["enabled"] and row["required_points"] <= 200]
        for field, delta in self.expected_effects(earned).items():
            self.assertEqual(self.stats[field] - before[field], delta)
        self.stats["starjoy_points"] = 0
        saved = copy.deepcopy(self.stats)
        self.send("starjoy_reconcile", "offline-spent-points")
        self.assertEqual(self.stats, saved)

    def test_vip_claim_requires_server_recharge_then_awards_once(self):
        denied = self.service.command(self.payload("vip_claim", reward_id="vip_privilege_01"))
        self.assertFalse(denied["ok"])
        self.assertEqual(denied["error"], "VIP等级不足")
        threshold = self.bundle.tables["archive_vip_levels"]["vip_level_01"]["required_recharge_fen"]
        self.stats["vip_recharge_total_fen"] = threshold
        self.send("vip_claim", "offline-vip-earned", reward_id="vip_privilege_01")
        self.assertTrue(self.archive["vip_claimed"]["vip_privilege_01"])
        saved = copy.deepcopy(self.stats)
        self.send("vip_claim", "offline-vip-second-request", reward_id="vip_privilege_01")
        self.assertEqual(self.stats, saved)

    def test_vip_purchase_debit_medal_and_package_share_one_receipt(self):
        package = self.bundle.tables["archive_vip_rewards"]["vip_package_01"]
        self.stats["vip_recharge_total_fen"] = self.bundle.tables["archive_vip_levels"]["vip_level_01"]["required_recharge_fen"]
        self.stats["shop_paid_currency"] = package["price"]
        before = copy.deepcopy(self.stats)
        payload = self.payload("vip_purchase", reward_id=package["reward_id"])
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.command(payload)
        saved = copy.deepcopy(self.db.profile)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.db.profile, saved)
        self.assertEqual(self.stats["shop_paid_currency"], 0)
        self.assertTrue(self.archive["vip_claimed"][package["reward_id"]])
        self.assertTrue(self.archive["vip_claimed"][package["medal_id"]])
        medal = self.bundle.tables["archive_vip_rewards"][package["medal_id"]]
        for field, delta in self.expected_effects([package, medal]).items():
            self.assertEqual(self.stats[field] - before[field], delta)
        self.send("vip_purchase", "offline-vip-repurchase", reward_id=package["reward_id"])
        self.assertEqual(self.stats, saved["save"]["gameplay_stats"])

    def test_title_equip_is_saved_without_granting_pending_gameplay_rewards(self):
        self.stats["starjoy_points"] = 200
        self.archive["clear_counts"] = {"n1": 10}
        saved = copy.deepcopy(self.stats)
        self.send("title_equip", title_id="peak_perfection")
        self.assertEqual(self.archive["equipped_title"], "peak_perfection")
        self.assertEqual(self.stats, saved)
        denied = self.service.command(self.payload("title_equip", "offline-locked-title", title_id="jinghong"))
        self.assertFalse(denied["ok"])
        self.assertEqual(self.archive["equipped_title"], "peak_perfection")
        self.send("title_equip", "offline-remove-title", title_id="")
        self.assertEqual(self.archive["equipped_title"], "")
        self.assertEqual(self.stats, saved)

    def test_daily_claim_uses_database_date_and_persists_item_counts_once(self):
        self.send("daily_init", today=99999)
        self.assertEqual(self.archive["daily_rewards"]["first_day"], 20000)
        payload = self.payload("daily_claim", "offline-daily-claim", today=99999, target_day=20000)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.archive["daily_rewards"]["count"], 1)
        self.assertTrue(self.archive["daily_rewards"]["claimed"]["20000"])
        self.assertGreater(sum(self.archive["daily_rewards"]["item_counts"].values()), 0)
        saved = copy.deepcopy(self.db.profile)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.db.profile, saved)

    def test_work_and_building_upgrade_debit_their_saved_currencies_once(self):
        work = self.bundle.tables["archive_work_items"]["work_01"]
        self.archive["online"] = {"actual_seconds": 0, "map_seconds": 0, "coins": work["cost"],
                                  "map_level": 0, "work_levels": {}, "cursors": {}}
        before = copy.deepcopy(self.stats)
        payload = self.payload("work_upgrade", item_id=work["item_id"], expected_level=0)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.archive["online"]["coins"], 0)
        self.assertEqual(self.archive["online"]["work_levels"][work["item_id"]], 1)
        for field, delta in self.effects(work).items():
            self.assertEqual(self.stats[field] - before[field], delta)
        saved = copy.deepcopy(self.db.profile)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.db.profile, saved)

        building = self.bundle.tables["archive_building_items"]["building_01"]
        self.archive["buildings"] = {"faith": building["cost"], "levels": {}, "earned_by_day": {}}
        before = copy.deepcopy(self.stats)
        payload = self.payload("building_upgrade", item_id=building["item_id"], expected_level=0)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.archive["buildings"]["faith"], 0)
        self.assertEqual(self.archive["buildings"]["levels"][building["item_id"]], 1)
        for field, delta in self.effects(building).items():
            self.assertEqual(self.stats[field] - before[field], delta)
        saved = copy.deepcopy(self.db.profile)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.db.profile, saved)

    def test_social_draw_spends_only_saved_tickets_and_rewards_once(self):
        rule = self.bundle.tables["archive_social_rules"]["friend"]
        self.archive["social_tickets"] = {rule["currency_id"]: rule["draw_cost"]}
        payload = self.payload("social_draw", pool_id="friend")
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.archive["social_tickets"][rule["currency_id"]], 0)
        self.assertEqual(sum(self.archive["social_counts"].values()), 1)
        saved = copy.deepcopy(self.db.profile)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.db.profile, saved)
        denied = self.service.command(self.payload("social_draw", "offline-social-empty", pool_id="friend"))
        self.assertFalse(denied["ok"])
        self.assertEqual(self.db.profile, saved)

    def test_low_difficulty_challenge_boss_and_endless_progress_are_persisted(self):
        self.send("boss_kill")
        self.assertEqual(self.archive["boss_kills"], 1)
        self.send("challenge", challenge_id="shadow_1", kill_sequence=1, difficulty_id="n1")
        self.assertEqual(sum(self.archive["shadow_counts"].values()), 2)
        self.send("challenge", "offline-hunt", challenge_id="hunt_01", kill_sequence=2, difficulty_id="n5")
        self.assertEqual(self.archive["fragment_counts"]["fragment_01"], 1)
        self.assertEqual(self.archive["fragment_totals"]["fragment_01"], 1)
        self.send("endless", wave=11, difficulty=10)
        self.assertEqual(self.archive["endless_best_wave"], 11)
        self.assertGreater(self.archive["endless_score"], 0)
        self.assertTrue(self.archive["completed"]["endless_51"])
        saved = copy.deepcopy(self.stats)
        self.send("endless_reconcile")
        self.assertEqual(self.stats, saved)

    def test_fragment_promotion_preserves_total_progress_and_cannot_double_spend(self):
        source = self.bundle.tables["archive_fragment_definitions"]["fragment_01"]
        self.archive["fragment_counts"] = {source["fragment_id"]: source["promotion_cost"]}
        self.archive["fragment_totals"] = {source["fragment_id"]: source["promotion_required_total"]}
        payload = self.payload("promotion", fragment_id=source["fragment_id"])
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.archive["fragment_counts"][source["fragment_id"]], 0)
        self.assertEqual(self.archive["fragment_totals"][source["fragment_id"]], source["promotion_required_total"])
        self.assertEqual(self.archive["fragment_counts"][source["promotion_target"]], 1)
        saved = copy.deepcopy(self.db.profile)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.db.profile, saved)

    def test_reconcile_rejects_client_supplied_rewards_or_progress(self):
        for kind in ("starjoy_reconcile", "welfare_reconcile", "endless_reconcile"):
            for field, value in (("cooperative_clear_count", 999), ("clear_counts", {"n20": 999}),
                                 ("points", 99999), ("wave", 461), ("effects", {})):
                with self.subTest(kind=kind, field=field):
                    with self.assertRaisesRegex(ArchiveError, "^archive_command_fields_invalid$"):
                        self.service.command(self.payload(kind, **{field: value}))
        self.assertEqual(self.db.commit_count, 0)

    def legacy_hash(self):
        aliases = self.bundle.compatible_config_hashes
        if not aliases:
            self.skipTest("Set SURVIVAL_ARCHIVE_FULL_BUNDLE to test candidate legacy compatibility")
        return next(iter(aliases))

    def test_legacy_clear_uses_current_archive_rules_without_changing_receipt_hash(self):
        digest = self.legacy_hash()
        payload = self.payload("clear", digest=digest, difficulty_id="n1", count=1, cooperative_win=1)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.archive["clear_counts"], {"n1": 1})
        self.assertEqual(self.archive["cooperative_clear_count"], 1)
        self.assertTrue(self.archive["completed"]["welfare_victory_01"])
        self.assertEqual(self.db.prepared_hashes, [digest])
        saved = copy.deepcopy(self.db.profile)
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.db.profile, saved)

    def test_legacy_completed_receipt_is_returned_before_running_new_reducer(self):
        digest = self.legacy_hash()
        command = self.service.validate(self.command("clear", difficulty_id="n1", count=1))
        fingerprint = hashlib.sha256(json.dumps(command, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        self.db.rpc("archive_prepare", {"p_id": command["id"], "p_hash": digest,
                                       "p_fingerprint": fingerprint, "p_command": command})
        self.db.ops[command["id"]]["done"] = True
        self.archive["clear_counts"] = {"n1": 1}
        saved = copy.deepcopy(self.db.profile)
        with patch.object(ArchiveService, "settle", side_effect=AssertionError("completed legacy receipt must not settle")):
            result = self.service.command(self.payload("clear", digest=digest, difficulty_id="n1", count=1))
        self.assertTrue(result["ok"])
        self.assertEqual(self.db.profile, saved)
        self.assertEqual(self.db.commit_count, 0)

    def test_same_operation_cannot_switch_configuration_hash(self):
        digest = self.legacy_hash()
        payload = self.payload("clear", digest=digest, difficulty_id="n1", count=1, cooperative_win=0)
        self.assertTrue(self.service.command(payload)["ok"])
        saved = copy.deepcopy(self.db.profile)
        payload["config_hash"] = self.bundle.hash
        self.assertEqual(self.service.command(payload)["error"], "archive_id_conflict")
        self.assertEqual(self.db.profile, saved)
        self.assertEqual(self.db.commit_count, 1)

    def test_unknown_hash_and_malformed_clear_have_no_writes(self):
        result = self.service.command(self.payload("clear", digest="f" * 64,
                                                  difficulty_id="n1", count=1, cooperative_win=0))
        self.assertEqual(result["error"], "archive_config_mismatch")
        for difficulty in ("n0", "n21", "n01", "N1", "n1junk", None):
            with self.subTest(difficulty=difficulty):
                with self.assertRaisesRegex(ArchiveError, "^archive_clear_invalid$"):
                    self.service.command(self.payload("clear", difficulty_id=difficulty, count=1))
        for flag in (-1, 2, True, "1"):
            with self.subTest(cooperative_win=flag):
                with self.assertRaisesRegex(ArchiveError, "^archive_number_invalid:cooperative_win$"):
                    self.service.command(self.payload("clear", difficulty_id="n1", count=1, cooperative_win=flag))
        self.assertEqual(self.db.commit_count, 0)

    def test_all_legacy_versions_accept_new_archive_commands_and_clear_rules(self):
        self.legacy_hash()
        required = {"clear", "starjoy_reconcile", "welfare_reconcile", "endless_reconcile",
                    "vip_claim", "vip_purchase", "title_equip", "challenge"}
        for digest, rule in self.bundle.compatible_config_hashes.items():
            with self.subTest(hash=digest):
                self.assertTrue(set(FIELDS) <= rule["commands"])
                self.assertTrue(required <= rule["upgrade_commands"])
                self.db = ReceiptDatabase(self.bundle)
                self.service = ArchiveService(App(self.db), self.bundle, self.lua)
                payload = self.payload("clear", digest=digest, difficulty_id="n1", count=1, cooperative_win=1)
                self.assertTrue(self.service.command(payload)["ok"])
                self.assertEqual(self.archive["clear_counts"], {"n1": 1})
                self.assertEqual(self.archive["cooperative_clear_count"], 1)
                self.assertTrue(self.archive["completed"]["welfare_victory_01"])
                self.assertEqual(self.db.prepared_hashes, [digest])


class FullArchiveReleasePreservationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = os.environ.get("SURVIVAL_ARCHIVE_FULL_BUNDLE")
        if not directory:
            raise unittest.SkipTest("Set SURVIVAL_ARCHIVE_FULL_BUNDLE to review the release candidate")
        cls.directory = Path(directory).resolve()
        cls.data = json.loads((cls.directory / "bundle.json").read_bytes())
        baseline_path = Path(os.environ.get("SURVIVAL_ARCHIVE_FULL_BASELINE", str(
            ROOT / "output/archive_full_sync_20261009/remote_baseline.json")))
        cls.baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        cls.old = json.loads(cls.baseline["bundle_raw"])

    def test_release_preserves_every_existing_stat_and_only_adds_six_zero_defaults(self):
        expected = {"starjoy_points_earned", "starjoy_reward_level", "hero_execute_health_threshold_pct",
                    "vip_level", "shop_paid_currency", "vip_recharge_total_fen"}
        before = {row["field_id"]: row for row in self.old["configs"]["player_gameplay_stats"]["rows"]}
        after = {row["field_id"]: row for row in self.data["configs"]["player_gameplay_stats"]["rows"]}
        self.assertEqual(len(before), 97)
        self.assertEqual(len(after), 103)
        self.assertEqual(set(after) - set(before), expected)
        for field, row in before.items():
            self.assertEqual(after[field], row, field)
        for field in expected:
            self.assertEqual(after[field]["default_value"], 0)

    def test_release_preserves_all_lottery_and_commerce_rules_and_csv_hashes(self):
        for name, config in self.old["configs"].items():
            if not name.startswith("archive_") and name != "player_gameplay_stats":
                self.assertEqual(self.data["configs"][name], config, name)
        for path, digest in self.old["csv_hashes"].items():
            if "/存档系统/" not in path and not path.endswith("/player_gameplay_stats.csv"):
                self.assertEqual(self.data["csv_hashes"][path], digest, path)
        for path in ("config/lottery_config.lua", "config/content_id_aliases.lua"):
            self.assertEqual(self.data["sources"][path], self.old["sources"][path], path)

    def test_release_retains_exact_known_hash_aliases_and_forbids_legacy_economic_reducer_upgrade(self):
        expected = {self.baseline["bundle"], "288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7"}
        self.assertEqual(set(self.data["compatible_config_hashes"]), expected)
        for digest, rule in self.data["compatible_config_hashes"].items():
            self.assertIn("clear", rule["upgrade_commands"])
            self.assertIn("cooperative_win", FIELDS["clear"])
            for kind in ("commerce_purchase", "lottery_draw", "lottery_exchange"):
                self.assertNotIn(kind, rule["upgrade_commands"], digest + ":" + kind)


if __name__ == "__main__":
    unittest.main()
