"""Scope and real-worker regressions using synthetic data; no server access."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


builder = module("wife_overlay_builder", DIRECTORY / "build_overlay.py")
worker = module("wife_overlay_smoke", DIRECTORY / "smoke.py")


class OverlayTests(unittest.TestCase):
    def setUp(self):
        output = ROOT / "output/wife_video_20261016/test_fixtures"
        output.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="overlay-", dir=output)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = ROOT / "server/bundles" / builder.BASE
        shutil.copytree(source, self.root / "server/bundles" / builder.BASE)
        self.base = json.loads((source / "bundle.json").read_bytes())
        self.tables = {name: copy.deepcopy(self.base["configs"][name]) for name in builder.TABLES}
        item = {"item_id": "wife_01", "pool_id": "wife", "display_name": "合成测试角色",
            "max_owned": 60, "quality": "N", "description": "初始金币+30",
            "effect_ids": ["initial_gold"], "effect_values": ["30"], "enabled": True}
        self.tables["archive_social_items"]["rows"].append(item)
        self.tables["archive_social_rules"]["rows"].append({"pool_id": "wife", "display_name": "我的老婆",
            "currency_id": "rose", "currency_name": "玫瑰", "daily_limit": 10, "draw_cost": 1, "unlock_count": 0, "enabled": True})
        self.tables["archive_categories"]["rows"].append({"category_id": "wife", "display_name": "我的老婆",
            "renderer": "collection", "sort_order": 67, "enabled": True})
        row = next(r for r in self.tables["archive_challenge_definitions"]["rows"] if r["challenge_id"] == "social_ex")
        row = copy.deepcopy(row)
        row.update(challenge_id="social_wife", reward_key="wife", display_name="老婆挑战", slot_order=11)
        self.tables["archive_challenge_definitions"]["rows"].append(row)
        for row in list(self.tables["archive_challenge_stats"]["rows"]):
            if row["challenge_id"] == "social_ex":
                row = copy.deepcopy(row)
                row.update(challenge_id="social_wife", stats_id=row["stats_id"].replace("social_ex", "social_wife"))
                self.tables["archive_challenge_stats"]["rows"].append(row)
        for name, (folder, _, _) in builder.TABLES.items():
            path = self.root / "data/csv" / folder / (name + ".csv")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic-test-csv\n", "utf-8")
        source = self.root / "scripts/vscripts/systems/archive_social_rewards.lua"
        source.parent.mkdir(parents=True)
        source.write_text(builder.social_transform(self.base["sources"]["systems/archive_social_rewards.lua"]), "utf-8")

    def build(self, allowed=()):
        def read(path):
            return copy.deepcopy(self.tables[path.stem])
        with patch.object(builder, "ROOT", self.root), patch.object(builder, "OUTPUT", self.root / "candidate"), patch.object(builder, "read_csv", read):
            return builder.build(1, allowed)

    def test_preserves_all_existing_rows_sources_and_compatibility(self):
        result = self.build()
        current = json.loads((Path(result["directory"]) / "bundle" / result["candidate"] / "bundle.json").read_bytes())
        source_name = "systems/archive_social_rewards.lua"
        for name, source in self.base["sources"].items():
            self.assertEqual(current["sources"][name], builder.social_transform(source) if name == source_name else source)
        for name, original in self.base["configs"].items():
            expected = current["configs"][name]
            self.assertEqual(expected["rows"][:len(original["rows"])], original["rows"])
            if name not in builder.TABLES:
                self.assertEqual(expected, original)
        for key, value in self.base.get("compatible_config_hashes", {}).items():
            self.assertEqual(current["compatible_config_hashes"][key], value)
        self.assertEqual(current["compatible_config_hashes"][builder.BASE]["upgrade_commands"], [])
        self.assertFalse((self.root / "server/bundles/current.json").exists())
        self.assertFalse((self.root / "scripts/vscripts/config/generated/archive_http_bundle.lua").exists())
        self.assertEqual(self.build(), result, "repeated build is byte stable")

    def test_unrelated_existing_reward_change_is_rejected(self):
        self.tables["archive_social_items"]["rows"][0]["effect_values"] = ["999999"]
        with self.assertRaisesRegex(ValueError, "affected_table_has_unrelated_changes"):
            self.build()

    def test_unknown_stat_needs_exact_explicit_approval(self):
        self.tables["archive_social_items"]["rows"][-1]["effect_ids"] = ["unreviewed_reward"]
        with self.assertRaisesRegex(ValueError, "new_stat_approval_must_exactly_match"):
            self.build()

    def test_incomplete_challenge_difficulties_are_rejected(self):
        self.tables["archive_challenge_stats"]["rows"].pop()
        with self.assertRaisesRegex(ValueError, "difficulty_stats_incomplete"):
            self.build()

    def test_packaged_real_lua_worker_draw_effect_replay_and_daily_limit(self):
        result = self.build()
        report = worker.run(Path(result["directory"]) / "bundle" / result["candidate"], "C:/Program Files/lua/bin/lua5.1.exe")
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["wife_count"], 1)
        self.assertEqual(report["persistent_writes"], 0)

    def test_pending_items_remain_visible_but_never_consume_a_draw(self):
        for identity in ("wife_39", "wife_31"):
            self.tables["archive_social_items"]["rows"].append({"item_id": identity,
                "pool_id": "wife", "display_name": identity, "max_owned": 6, "quality": "N",
                "description": "原文保留测试", "enabled": True, "draw_enabled": False,
                "availability_note": "待适配，暂不参与抽取，不消耗玫瑰"})
        with patch.object(builder, "ROOT", self.root), patch.object(builder, "OUTPUT", self.root / "candidate"), patch.object(builder, "read_csv", lambda path: copy.deepcopy(self.tables[path.stem])):
            result = builder.build(3)
        report = worker.run(Path(result["directory"]) / "bundle" / result["candidate"], "C:/Program Files/lua/bin/lua5.1.exe")
        self.assertEqual(report["display_count"], 3)
        self.assertEqual(report["wife_count"], 1)
        self.assertEqual(report["unavailable_ids"], ["wife_31", "wife_39"])


if __name__ == "__main__":
    unittest.main()
