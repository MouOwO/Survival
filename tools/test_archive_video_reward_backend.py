"""Real bundled Lua reducer plus transactional in-memory RPC; no live accounts."""
from __future__ import annotations
import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveService
from server.tests.test_archive_backend import App, Database


class VideoRewardBackend(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = os.environ.get("LUA_EXECUTABLE", r"C:\Program Files\lua\bin\lua5.1.exe")
        cls.temp = tempfile.TemporaryDirectory(prefix="archive-video-rewards-")
        cls.addClassCleanup(cls.temp.cleanup)
        before = {path: path.read_bytes() for path in (
            ROOT / "server/bundles/current.json", ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua")}
        digest = build(ROOT, destination=Path(cls.temp.name), update_game_config=False)
        cls.bundle = Bundle(Path(cls.temp.name) / digest)
        for path, value in before.items():
            if path.read_bytes() != value:
                raise AssertionError("test changed a runtime pointer")

    def setUp(self):
        self.db = Database(self.bundle)
        self.app = App(self.db)
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.sequence = 0

    def profile(self, account="100"):
        return self.db.profile(self.app._database_account_id(account))

    def payload(self, challenge, *, account="100", session=None):
        self.sequence += 1
        definition = self.bundle.tables["archive_challenge_definitions"][challenge]
        return {"account_id": account, "config_hash": self.bundle.hash,
                "command": {"id": (session or "offline-video-" + str(self.sequence)) + ":challenge:1",
                            "kind": "challenge", "challenge_id": challenge, "kill_sequence": 1,
                            "difficulty_id": "n" + str(definition["min_difficulty"])}}

    def test_each_cooperative_recipient_observes_own_strict_gate(self):
        self.profile("100")["save"]["archive"] = {"social_draw_counts": {"beast": 100}}
        self.profile("101")["save"]["archive"] = {"social_draw_counts": {"beast": 101}}
        self.profile("102")["save"]["archive"] = {
            "social_tickets": {"blessing_ticket": 1000000}, "social_unlocks": {"ex_100": True}}
        self.profile("103")["save"]["archive"] = {"social_counts": {"beast_01": 60, "beast_02": 41}}
        for account, expected in (("100", 0), ("101", 1), ("102", 0), ("103", 1)):
            payload = self.payload("social_ex", account=account, session="same-cooperative-source")
            result = self.service.command(payload)
            self.assertTrue(result["ok"])
            self.assertEqual(result["response"]["awarded"], expected)
            archive = self.profile(account)["save"]["archive"]
            self.assertEqual(archive.get("social_tickets", {}).get("invitation", 0), expected)
            if not expected:
                self.assertIn("累计抽奖次数需大于100", result["response"]["skipped_reason"])
            retry = self.service.command(payload)
            self.assertTrue(retry["ok"])
            self.assertEqual(archive.get("social_tickets", {}).get("invitation", 0), expected)
        self.assertTrue(all(operation["done"] and not operation.get("error") for operation in self.db.ops.values()))

    def test_points_grant_exact_video_amounts_and_finish_at_daily_cap(self):
        for challenge, amount, maximum, daily_key in (("football", 10, 100, "football_total"),
                                                      ("watermelon", 1, 10, "watermelon_total")):
            for _ in range(10):
                result = self.service.command(self.payload(challenge))
                self.assertTrue(result["ok"])
                self.assertEqual(result["response"]["awarded"], amount)
            result = self.service.command(self.payload(challenge))
            self.assertTrue(result["ok"])
            self.assertEqual(result["response"]["awarded"], 0)
            archive = self.profile()["save"]["archive"]
            self.assertEqual(archive["challenge_points"][challenge], maximum)
            self.assertEqual(archive["daily"]["20000"][daily_key], maximum)
        self.assertTrue(all(operation["done"] for operation in self.db.ops.values()))

    def test_salary_lost_commit_reply_does_not_double_grant(self):
        self.profile()["save"]["archive"] = {"social_draw_counts": {"friend": 101}}
        payload = self.payload("social_concubine")
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.command(payload)
        result = self.service.command(payload)
        self.assertTrue(result["ok"])
        archive = self.profile()["save"]["archive"]
        self.assertEqual(archive["social_tickets"]["salary"], 1)
        self.assertEqual(archive["daily"]["20000"]["salary_total"], 1)

    def test_salary_draw_effect_and_counter_persist_and_retry_once(self):
        self.profile()["save"]["archive"] = {"social_tickets": {"salary": 2}}
        before = copy.deepcopy(self.profile()["save"]["gameplay_stats"])
        payload = {"account_id": "100", "config_hash": self.bundle.hash,
                   "command": {"id": "offline-video-draw:1", "kind": "social_draw", "pool_id": "concubine"}}
        first = self.service.command(payload)
        self.assertTrue(first["ok"])
        archive = self.profile()["save"]["archive"]
        self.assertEqual(archive["social_tickets"]["salary"], 1)
        self.assertEqual(archive["social_draw_counts"]["concubine"], 1)
        self.assertEqual(sum(archive["social_counts"].values()), 1)
        self.assertNotEqual(self.profile()["save"]["gameplay_stats"], before)
        snapshot = copy.deepcopy(self.profile()["save"])
        self.assertTrue(self.service.command(payload)["ok"])
        self.assertEqual(self.profile()["save"], snapshot)

    def test_four_new_fragment_ids_and_three_new_cage_pools_persist(self):
        for index in range(13, 17):
            result = self.service.command(self.payload(f"hunt_{index:02d}"))
            self.assertTrue(result["ok"])
            self.assertEqual(self.profile()["save"]["archive"]["fragment_counts"][f"fragment_{index:02d}"], 1)
        for index in range(7, 10):
            result = self.service.command(self.payload("cage_" + str(index)))
            self.assertTrue(result["ok"])
            items = self.bundle.tables["archive_cage_items"]
            self.assertTrue(any(items[key]["pool_id"] == "cage_" + str(index)
                                for key in self.profile()["save"]["archive"]["cage_counts"]))

    def test_old_collection_count_migrates_to_cumulative_draw_cursor(self):
        self.profile()["save"]["archive"] = {"social_counts": {"beast_01": 60, "beast_02": 40},
                                              "social_tickets": {"blessing_ticket": 1}}
        payload = {"account_id": "100", "config_hash": self.bundle.hash,
                   "command": {"id": "offline-video-migration:1", "kind": "social_draw", "pool_id": "beast"}}
        self.assertTrue(self.service.command(payload)["ok"])
        archive = self.profile()["save"]["archive"]
        self.assertEqual(archive["social_draw_counts"]["beast"], 101)
        self.assertEqual(archive["social_tickets"]["blessing_ticket"], 0)
        self.assertEqual(self.service.command(self.payload("social_ex"))["response"]["awarded"], 1)


if __name__ == "__main__":
    unittest.main()
