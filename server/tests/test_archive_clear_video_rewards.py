"""Reviewed video -> CSV -> real packaged Lua worker reward regressions."""
from __future__ import annotations

from collections import Counter
from copy import deepcopy
from decimal import Decimal
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveService, object_maps

REFERENCE = ROOT / "data/references/archive_clear_rewards_20261020.json"
TARGET = ROOT / "data/csv/存档系统/archive_achievements.csv"

# A separate semantic expectation, rather than accepting any registered field
# named by the import reference. Wording variants in the recording stay intact.
DESCRIPTION_FIELDS = {
    "金矿收益": "gold_mine_efficiency_pct", "金矿效率": "gold_mine_efficiency_pct",
    "每秒金币": "gold_per_second", "每秒木材": "wood_per_second",
    "英雄攻击减甲": "hero_attack_armor_reduction", "英雄攻击加成": "hero_attack_bonus_pct",
    "英雄三围加成": "hero_attribute_bonus_pct", "英雄全属性加成": "hero_attribute_bonus_pct",
    "英雄攻击全属性": "hero_attribute_growth", "英雄攻击属性成长": "hero_attribute_growth",
    "英雄造成伤害属性": "hero_attributes_per_damage",
    "英雄每秒全属性": "hero_attributes_per_second", "英雄每秒属性": "hero_attributes_per_second",
    "英雄攻击成长": "hero_basic_attack_growth", "英雄暴击伤害": "hero_critical_damage_bonus_pct",
    "英雄造成伤害加攻击": "hero_damage_attack_growth", "英雄造成伤害攻击": "hero_damage_attack_growth",
    "英雄最终伤害": "hero_final_damage_bonus_pct", "人口": "initial_population_cap",
    "木材": "initial_wood", "伐木工攻击成长": "lumberjack_attack_growth",
    "伐木工攻速": "lumberjack_attack_speed_bonus_pct", "伐木效率": "lumberjack_efficiency",
    "箭塔攻击减甲": "tower_attack_armor_reduction", "箭塔攻击加成": "tower_attack_bonus_pct",
    "箭塔攻击百分比": "tower_attack_bonus_pct", "箭塔攻击间隔": "tower_attack_interval_reduction",
    "箭塔攻击速度": "tower_attack_speed_bonus_pct", "箭塔攻速": "tower_attack_speed_bonus_pct",
    "箭塔暴击几率": "tower_critical_chance_pct", "箭塔暴击伤害": "tower_critical_damage_bonus_pct",
    "箭塔造成伤害攻击": "tower_damage_attack_growth", "箭塔最终伤害": "tower_final_damage_bonus_pct",
    "墙护甲": "wall_armor", "城墙防御加成": "wall_armor_bonus_pct",
    "墙护甲加成": "wall_armor_bonus_pct", "墙每秒护甲": "wall_armor_per_second",
    "墙减伤": "wall_damage_reduction_pct", "墙生命加成": "wall_health_bonus_pct",
    "墙每秒生命": "wall_health_per_second",
}


class ClearVideoRewardsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = os.environ.get("LUA_EXECUTABLE") or shutil.which("lua5.1") or shutil.which("lua")
        if not cls.lua:
            raise RuntimeError("Set LUA_EXECUTABLE to run the real archive bundle worker")
        cls.temporary = tempfile.TemporaryDirectory(prefix="archive-video-rewards-")
        cls.addClassCleanup(cls.temporary.cleanup)
        destination = Path(cls.temporary.name)
        cls.bundle = Bundle(destination / build(ROOT, destination=destination, update_game_config=False))
        cls.reference = json.loads(REFERENCE.read_text(encoding="utf-8"))
        cls.stats = cls.bundle.tables["player_gameplay_stats"]
        cls.achievements = cls.bundle.tables["archive_achievements"]

    def setUp(self):
        self.service = ArchiveService(SimpleNamespace(account_id_pepper="video-test-only"), self.bundle, self.lua)
        # Other victory-welfare milestones are already claimed in this fixture,
        # so their independent bonuses cannot obscure the clear reward delta.
        completed = {row["achievement_id"]: True
                     for row in self.bundle.configs["archive_welfare_rewards"]["rows"]}
        self.profile = {"account_id": "video-rewards-account", "revision": 1, "entitlements": {},
                        "save": {"archive": {"completed": completed},
                                 "gameplay_stats": {key: row["default_value"] for key, row in self.stats.items()}}}
        self.sequence = 0

    def clear(self, mode, difficulty="n1", *, operation_id=None, commit=True):
        self.sequence += 1
        command = {"id": operation_id or f"video-match-{self.sequence:03d}:{mode}_clear",
                   "kind": "mode_clear", "mode_id": mode, "difficulty_id": difficulty,
                   "count": 1, "day_key": "22000"}
        result = self.service.settle(self.profile, command, False)
        if result.get("ok") and commit:
            self.profile["save"]["archive"] = result["archive"]
            self.profile["save"]["gameplay_stats"] = result["gameplay_stats"]
            self.profile["revision"] += 1
        return result

    def module_probe(self, *, archive=None, commands=None):
        script = r'''
package.path="./?.lua"
local decoder=require("core/json_decoder")
local encoder=require("core/json_encoder")
local input=decoder.decode(io.read("*a"))
for name,config in pairs(input.configs) do
 local module={rows=config.rows,by_id={}}
 for _,row in ipairs(config.rows) do module.by_id[row[config.key]]=row end
 package.loaded["config/generated/"..name]=module
end
local progress=require("systems/archive_clear_progress")
local archive=input.archive or {}
local before=encoder.encode(archive)
local stats,attempts={},{}
for _,command in ipairs(input.commands or {}) do
 local ok,reason=progress.record(archive,command,stats,function() error("unavailable_reward_granted") end)
 attempts[#attempts+1]={ok=ok,error=reason}
end
io.write(encoder.encode({rows=progress.rows(archive),attempts=attempts,
 archive_unchanged=before==encoder.encode(archive),stats=stats}))
'''
        result = subprocess.run([self.lua, "-e", script], cwd=self.bundle.directory,
            input=json.dumps({"configs": self.bundle.configs, "archive": archive or {},
                              "commands": commands or []}, ensure_ascii=False).encode(),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=10,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return object_maps(json.loads(result.stdout))

    def test_reference_has_all_199_literal_rewards_and_semantic_field_mapping(self):
        rows = self.reference["rows"]
        totals = {"cold": 50, "scourge": 50, "rich": 22, "guixu": 45, "tianyu": 32}
        prefixes = {"cold": "极寒", "scourge": "天灾", "rich": "丰饶", "guixu": "归墟", "tianyu": "天域"}
        self.assertEqual(len(rows), 199)
        self.assertEqual(Counter(row["mode_id"] for row in rows), totals)
        self.assertEqual(len({(row["mode_id"], row["difficulty_id"]) for row in rows}), 199)
        self.assertRegex(self.reference["source_sha256"], r"^[0-9a-f]{64}$")
        for mode, total in totals.items():
            self.assertEqual(sorted(int(row["difficulty_id"][1:]) for row in rows if row["mode_id"] == mode),
                             list(range(1, total + 1)))
        for row in rows:
            with self.subTest(mode=row["mode_id"], difficulty=row["difficulty_id"]):
                self.assertIs(row["verified"], True)
                self.assertEqual(row["name"], prefixes[row["mode_id"]] + row["difficulty_id"].upper())
                self.assertGreaterEqual(row["seconds"], 0)
                self.assertLessEqual(row["seconds"], self.reference["duration_seconds"])
                self.assertIs(type(row["reward_limit"]), int)
                self.assertIn(row["reward_limit"], (10, 20))
                match = re.fullmatch(r"(.+?)([+-])(\d+(?:\.\d+)?)(%)?", row["description"])
                self.assertIsNotNone(match, row["description"])
                label, sign, amount, _ = match.groups()
                self.assertEqual(row["effect_id"], DESCRIPTION_FIELDS[label])
                self.assertEqual(Decimal(str(row["effect_value"])), Decimal(amount))
                self.assertEqual(sign, "-" if label == "箭塔攻击间隔" else "+")
                self.assertIn(row["effect_id"], self.stats)

    def test_csv_retains_future_rewards_and_uses_valid_effects_and_counter_only_pure_rows(self):
        self.assertEqual(len(self.achievements), 253)
        groups = Counter(row.get("mode_id", "standard") for row in self.achievements.values())
        self.assertEqual(groups, {"standard": 44, "pure": 10, "cold": 50, "scourge": 50,
                                  "rich": 22, "guixu": 45, "tianyu": 32})
        for item in self.achievements.values():
            fields, values = item.get("effect_ids", []), item.get("effect_values", [])
            self.assertEqual(len(fields), len(values), item["achievement_id"])
            if item["mode_id"] == "pure":
                self.assertEqual(item["reward_mode"], "counter")
                self.assertEqual(fields, [])
            else:
                self.assertGreater(len(fields), 0)
            for field, value in zip(fields, values):
                self.assertIn(field, self.stats)
                self.assertTrue(Decimal(str(value)).is_finite())
                self.assertGreater(Decimal(str(value)), 0)
        for row in self.reference["rows"]:
            item = self.achievements[f"clear_{row['mode_id']}_{row['difficulty_id']}"]
            self.assertEqual(item["display_name"], row["name"])
            self.assertEqual(item["effect_ids"], [row["effect_id"]])
            self.assertEqual([Decimal(str(v)) for v in item["effect_values"]], [Decimal(str(row["effect_value"]))])
            self.assertEqual(item["reward_mode"], "per_clear")
            self.assertEqual(item["reward_start"], 0, "the video does not establish an unpaid initial ten wins")
            self.assertEqual((item["required_count"], item["reward_limit"]), (row["reward_limit"],) * 2)
            self.assertEqual(item["source_video_seconds"], row["seconds"])
            self.assertEqual(item["source_target"], row["source_target"])
        self.assertEqual(self.achievements["clear_tianyu_n1"]["source_target"], 30)
        self.assertEqual(self.achievements["clear_tianyu_n1"]["required_count"], 20)

    def test_rich_n1_grants_100_wood_on_each_clear_for_at_most_ten_claims(self):
        baseline = self.profile["save"]["gameplay_stats"]["initial_wood"]
        for number in range(1, 13):
            result = self.clear("rich")
            self.assertTrue(result["ok"], result)
            self.assertEqual(self.profile["save"]["gameplay_stats"]["initial_wood"],
                             baseline + min(number, 10) * 100)
        archive = self.profile["save"]["archive"]
        self.assertEqual(archive["mode_clear_counts"]["rich"]["n1"], 12)
        self.assertEqual(archive["mode_clear_rewards"]["rich:clear_rich_n1"], 10)
        self.assertNotIn("standard", archive["mode_clear_counts"])
        before = deepcopy(self.profile["save"])
        replay = self.clear("rich", operation_id="video-match-012:rich_clear")
        self.assertTrue(replay.get("duplicate"))
        self.assertEqual(self.profile["save"], before)

    def test_cold_scourge_and_rich_n1_counts_and_reward_receipts_are_independent(self):
        baseline = deepcopy(self.profile["save"]["gameplay_stats"])
        for mode in ("cold", "scourge", "rich"):
            result = self.clear(mode)
            self.assertTrue(result["ok"], result)
        archive, stats = self.profile["save"]["archive"], self.profile["save"]["gameplay_stats"]
        self.assertEqual(stats["lumberjack_attack_speed_bonus_pct"] - baseline["lumberjack_attack_speed_bonus_pct"], 1)
        self.assertEqual(stats["wood_per_second"] - baseline["wood_per_second"], 1)
        self.assertEqual(stats["initial_wood"] - baseline["initial_wood"], 100)
        for mode in ("cold", "scourge", "rich"):
            self.assertEqual(archive["mode_clear_counts"][mode], {"n1": 1})
            self.assertEqual(archive["mode_clear_rewards"][f"{mode}:clear_{mode}_n1"], 1)
        self.assertEqual(archive["clear_counts"], {})
        self.assertEqual(archive["standard_clear_counts"], {})

    def test_standard_legacy_milestones_do_not_repeat_and_pure_only_records_its_own_progress(self):
        archive = self.profile["save"]["archive"]
        archive.update(clear_counts={"n1": 3}, standard_clear_counts={"n1": 3})
        archive["completed"].update(clear_n1_1=True, clear_n1_3=True)
        self.profile["save"]["gameplay_stats"]["initial_wood"] = 777
        self.assertTrue(self.clear("standard")["ok"])
        self.assertEqual(self.profile["save"]["gameplay_stats"]["initial_wood"], 777)
        self.assertTrue(self.clear("standard")["ok"])
        self.assertEqual(self.profile["save"]["gameplay_stats"]["initial_wood"], 877)
        before = deepcopy(self.profile["save"]["gameplay_stats"])
        self.assertTrue(self.clear("pure")["ok"])
        archive = self.profile["save"]["archive"]
        self.assertEqual(self.profile["save"]["gameplay_stats"], before,
                         "pure counters cannot claim the ordinary N1 rewards")
        self.assertEqual(archive["mode_clear_counts"]["standard"]["n1"], 5)
        self.assertEqual(archive["mode_clear_counts"]["pure"]["n1"], 1)
        self.assertEqual(archive["standard_clear_counts"]["n1"], 5)
        self.assertTrue(archive["completed"]["clear_n1_1"])
        self.assertTrue(archive["completed"]["clear_n1_3"])
        self.assertNotIn("pure:clear_pure_n1", archive["mode_clear_rewards"])
        display = {row["id"]: row for row in self.module_probe(archive=archive)["rows"]}
        self.assertEqual((display["clear_pure_n1"]["count"], display["clear_pure_n1"]["completed"]), (1, 1))

    def test_unavailable_modes_and_literal_n20_n50_remain_configured_but_are_hidden_and_rejected(self):
        for key in ("clear_cold_n20", "clear_cold_n50", "clear_scourge_n20", "clear_scourge_n50",
                    "clear_rich_n20", "clear_guixu_n1", "clear_tianyu_n1"):
            self.assertIn(key, self.achievements)
        unavailable = [("rich", "n20"), ("cold", "n50"), ("scourge", "n20"),
                       ("guixu", "n1"), ("tianyu", "n1"), ("fishing", "n1")]
        commands = [dict(mode_id=mode, difficulty_id=difficulty, count=1) for mode, difficulty in unavailable]
        probe = self.module_probe(commands=commands)
        self.assertTrue(probe["archive_unchanged"])
        self.assertEqual(probe["stats"], {})
        self.assertTrue(all(attempt["ok"] is False for attempt in probe["attempts"]))
        self.assertEqual(len(probe["attempts"]), len(unavailable))
        self.assertTrue(all(row["mode_id"] in {"standard", "pure", "rich", "cold", "scourge"}
                            and int(row["difficulty_id"][1:]) <= 10 for row in probe["rows"]))
        visible = {row["id"] for row in probe["rows"]}
        for mode in ("cold", "scourge"):
            self.assertEqual(sorted(int(row["difficulty_id"][1:]) for row in probe["rows"]
                                    if row["mode_id"] == mode), list(range(1, 11)),
                             "archive display has ten difficulties even before all combat profiles exist")
        self.assertNotIn("clear_cold_n20", visible)
        self.assertNotIn("clear_cold_n50", visible)
        self.assertNotIn("clear_guixu_n1", visible)
        self.assertNotIn("clear_tianyu_n1", visible)
        for mode, difficulty in unavailable:
            before = deepcopy(self.profile)
            result = self.clear(mode, difficulty)
            self.assertFalse(result["ok"], (mode, difficulty, result))
            self.assertEqual(self.profile, before)

    def test_importer_is_idempotent_on_a_temporary_target_without_writing_the_game_csv(self):
        spec = importlib.util.spec_from_file_location("archive_video_importer_test", ROOT / "tools/import_archive_clear_video.py")
        importer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(importer)
        original, reference = TARGET.read_bytes(), REFERENCE.read_bytes()
        with tempfile.TemporaryDirectory(prefix="archive-video-importer-") as directory:
            target = Path(directory) / "archive_achievements.csv"
            target.write_bytes(original)
            with patch.object(importer, "TARGET", target):
                self.assertEqual(importer.build(), 253)
                first = target.read_bytes()
                self.assertEqual(importer.build(), 253)
                self.assertEqual(target.read_bytes(), first)
                self.assertEqual(first, original)
        self.assertEqual(TARGET.read_bytes(), original)
        self.assertEqual(REFERENCE.read_bytes(), reference)


if __name__ == "__main__":
    unittest.main()
