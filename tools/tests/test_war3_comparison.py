"""Independent fixtures for reference-only current-contract comparisons."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import unittest

REPO = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("war3_comparison", REPO / "tools/war3_extract/comparison.py")
comparison = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(comparison)


def unit(raw, hp, name="fixture", *, hero=False, attack=100, armor=70):
    fields = ["hp", "armor", "attack1_base", "attack1_dice", "attack1_sides", "attack1_interval", "strength"]
    return {"raw_id": raw, "name": name, "hp": hp, "armor": armor, "attack1_base": attack,
            "attack1_dice": 1, "attack1_sides": 2, "attack1_interval": .4,
            "strength": 1 if hero else None, "primary_attribute": "STR" if hero else "_",
            "provenance": {key: {"file": "Units/UnitBalance.slk", "line": 10 + index, "field": key}
                           for index, key in enumerate(fields)}}


def member(raw, cls, name="fixture", **extra):
    return {"raw_id": raw, "class": cls, "name": name, "key": raw, "initial_count": 1,
            "source": [{"member": "war3map.j", "line": 50, "function": "Fixture"}], **extra}


def hp_rules():
    return {"hero_native_inputs": {"coefficients": {"StrHitPointBonus": {
        "value": 5, "source": {"file": "war3mapMisc.txt", "line": 33}}}}}


def compare(units=(), waves=None, nonwave=(), current=None):
    return comparison.compare_current({"schema": "war3_units_base_v1", "units": list(units)},
        waves or {}, {"units": list(nonwave)}, current or {})


class CurrentContractComparisonTests(unittest.TestCase):
    def test_ten_commandments_last_four_keep_user_values_and_report_4960(self):
        names = ["沉默", "纯洁", "敬神", "慈爱"]
        raws = ["h08W", "h08X", "h08Y", "h090"]
        original = [50104960, 55104960, 60104960, 70104960]
        units = [unit(raw, hp, name) for raw, hp, name in zip(raws, original, names)]
        nonwave = [member(raw, "ten_commandments", name) for raw, name in zip(raws, names)]
        current = {"special_bosses": [{"name": name, "health": hp - 4960}
                                      for name, hp in zip(names, original)]}
        before = deepcopy(current)
        result = compare(units, nonwave=nonwave, current=current)
        differences = result["differences"]
        self.assertEqual(len(differences), 4)
        self.assertEqual({d["current_minus_original"] for d in differences}, {-4960})
        self.assertEqual({d["raw_id"] for d in differences}, set(raws))
        self.assertTrue(all(d["decision"] == "retain_current_contract" for d in differences))
        self.assertTrue(all(d["source"]["unit_field"]["line"] == 10 for d in differences))
        self.assertEqual(current, before)
        self.assertEqual(result["source_contract"], "reference_only")
        self.assertFalse(result["policy"]["current_spec_used_to_fill_original_values"])

    def test_duplicate_wuyu_is_not_a_substitute_for_active_h08U(self):
        current = {"special_bosses": [{"name": "无欲", "health": 40104960}]}
        wrong = member("h091", "ten_commandments", "无欲")
        result = compare([unit("h091", 160195520, "无欲")], nonwave=[wrong], current=current)
        self.assertEqual(result["matches"], [])
        self.assertEqual(result["differences"], [])
        self.assertIn("h08U", result["unmatched"][0]["reason"])
        result = compare([unit("h091", 160195520, "无欲"), unit("h08U", 40104960, "无欲")],
            nonwave=[wrong, member("h08U", "ten_commandments", "无欲")], current=current)
        self.assertEqual(result["matches"][0]["raw_id"], "h08U")
        self.assertEqual(result["matches"][0]["original"], 40104960)

    def test_wave_array_identity_wins_over_list_position_and_same_name(self):
        waves = {"wave_unit_arrays": [{"array": "udg_GW", "wave": 1, "rawid": "h00F", "source": {"line": 26110}}]}
        result = compare([unit("h00G", 150, "LV1"), unit("h00F", 100, "LV1")], waves,
            current={"waves": {"1": {"health": 100}}})
        self.assertEqual(result["matches"][0]["raw_id"], "h00F")
        self.assertEqual(result["matches"][0]["source"]["identity_binding"]["line"], 26110)

    def test_missing_original_value_remains_unmatched(self):
        current = {"special_bosses": [{"name": "真实", "health": 19104960}]}
        result = compare([unit("h08Z", None)], nonwave=[member("h08Z", "ten_commandments", "真实")], current=current)
        self.assertEqual(result["matches"], [])
        self.assertEqual(result["differences"], [])
        self.assertEqual(result["unmatched"][0]["field"], "health")

    def test_hero_hp_offset_and_attack_dice_have_separate_bases(self):
        waves = hp_rules()
        waves["wave_unit_arrays"] = [{"array": "udg_BOSS", "wave": 5, "rawid": "H012"}]
        result = compare([unit("H012", 10000, hero=True, attack=650, armor=100)], waves,
            current={"attack_bosses": {"5": {"health": 10005, "attack": 650, "war3_armor": 98}}})
        hp = next(r for r in result["matches"] if r["field"] == "health")
        self.assertEqual(hp["original"], 10005)
        self.assertEqual(hp["object_hp"], 10000)
        self.assertFalse(hp["hero_native_hp_verified"])
        attack = next(r for r in result["matches"] if r["field"] == "attack")
        self.assertEqual(attack["comparison_basis"], "SLK_damage_base_component")
        self.assertEqual(attack["attack_dice"]["sides"], 2)
        armor = next(r for r in result["differences"] if r["field"] == "war3_armor")
        self.assertEqual(armor["comparison_basis"], "object_armor_vs_corrected_contract")

    def test_archive_final_values_are_not_scaled_twice_or_called_native_damage(self):
        current = {"save_challenges": [{"name": "虚空之影1", "boss": "虚空之影1", "health": 9000010,
            "attack": 189002, "war3_armor": 998, "count": 1, "scale": 1.8, "attack_speed": 250}]}
        source = member("H09B", "archive_shadow", "虚空之影1", entry_item_scale=1.8)
        result = compare([unit("H09B", 5000000, hero=True, attack=105000, armor=1000)], hp_rules(), [source], current)
        hp = next(r for r in result["differences"] if r["field"] == "health")
        self.assertEqual(hp["original"], 9000009)
        self.assertEqual(hp["current"], 9000010)
        attack = next(r for r in result["differences"] if r["field"] == "attack")
        self.assertEqual((attack["current"], attack["original"]), (189002, 189000))
        self.assertEqual(attack["comparison_basis"], "final_attack_vs_scaled_base_component")
        self.assertFalse(attack["native_attack_verified"])
        self.assertEqual(attack["attack_dice"], {"count": 1, "sides": 2})

    def test_archive_wrong_family_or_missing_original_scale_is_unmatched(self):
        current = {"save_challenges": [{"name": "神兽狩猎-巫妖王", "boss": "巫妖王", "scale": 9, "health": 270000000}]}
        result = compare([unit("H09C", 30000000)], hp_rules(),
            [member("H09C", "archive_dragon", "巫妖王", entry_item_scale=9)], current)
        self.assertEqual(result["matches"], [])
        self.assertEqual(result["differences"], [])
        self.assertEqual(result["unmatched"][0]["field"], "identity")
        result = compare([unit("H09C", 30000000)], hp_rules(),
            [member("H09C", "archive_beast_hunt", "巫妖王", entry_item_scale=None)], current)
        self.assertEqual(result["unmatched"][0]["field"], "scale")

    def test_unreachable_difficulty_rows_are_not_compared_as_main_values(self):
        rows = [
            {"mode_id": 1, "difficulty": 1, "directly_bound_to_matching_N_label": False,
             "selector_mode_compatible": True, "multipliers": {"xgdg_pAAA": 999}},
            {"mode_id": 1, "difficulty": 1, "directly_bound_to_matching_N_label": True,
             "selector_mode_compatible": True, "multipliers": {"xgdg_pAAA": 2}},
            {"mode_id": 1, "difficulty": 10, "directly_bound_to_matching_N_label": True,
             "selector_mode_compatible": False, "multipliers": {"xgdg_pAAA": 63}},
        ]
        result = compare(waves={"difficulty_rows_all_variants": rows}, current={"modes": {
            "standard": {"1": {"hp_multiplier": 2}, "10": {"hp_multiplier": 63}}}})
        hp = next(r for r in result["matches"] if r["field"] == "hp_multiplier")
        self.assertEqual(hp["original"], 2)
        self.assertTrue(any(r["key"] == "standard/N10" and r["field"] == "identity" for r in result["unmatched"]))
        self.assertFalse(any(r["key"] == "standard/N10" for r in result["matches"]))

    def test_counts_keep_timer_iterations_separate_from_actual_first_three(self):
        profile = {"mode_id": 1, "difficulty": 1, "dialog_mode_compatible": True,
            "bands": [{"wave_min": 1, "wave_max": 10, "timer_iterations": 15,
                       "actual_units_on_wave_1_2_3": 14, "actual_units_on_other_waves": 15,
                       "spawn_interval_seconds": 1, "assignment_sources_refs": [{"line": 26650}]}]}
        current = {"counts": [{"mode_id": "standard", "min_difficulty": 1, "max_difficulty": 1,
            "min_wave": 1, "max_wave": 10, "count": 15, "spawn_interval": 1}]}
        result = compare(waves={"main_schedule_profiles": [profile]}, current=current)
        difference = next(r for r in result["differences"] if r["field"] == "count")
        self.assertEqual((difference["current"], difference["original"], difference["timer_iterations"]), (15, 14, 15))
        self.assertTrue(any(r["field"] == "count" and r["original"] == 15 for r in result["matches"]))

    def test_inputs_are_not_mutated_and_current_corrections_remain_policy(self):
        inputs = ({"units": []}, {}, {"units": []}, {"corrections_already_included": [{"对象": "首领06", "修正": "保留最终值"}]})
        before = deepcopy(inputs)
        result = comparison.compare_current(*inputs)
        result["current_corrections_preserved"][0]["修正"] = "mutated output"
        self.assertEqual(inputs, before)

    def test_real_reference_report_contains_four_4960_differences(self):
        root = REPO / "output/original_map_extract_20261025"
        paths = [root / "units/units_base.json", root / "waves/wave_rules.json",
                 root / "challenges/reproduced/challenge_rules.json", REPO / comparison.CURRENT_FILE]
        if not all(path.exists() for path in paths):
            self.skipTest("local ignored original-map audit not installed")
        inputs = [json.loads(path.read_text(encoding="utf-8")) for path in paths]
        result = comparison.compare_current(*inputs)
        ten = [r for r in result["differences"] if r["category"] == "ten_commandments" and r["field"] == "health"]
        self.assertEqual({r["key"] for r in ten}, {"沉默", "纯洁", "敬神", "慈爱"})
        self.assertTrue(all(r["current_minus_original"] == -4960 for r in ten))
        self.assertTrue(all(r["decision"] == "retain_current_contract" for r in result["differences"]))
        self.assertTrue(any(r["category"] == "special_rotation" and r["key"] == "wave8/slot2" for r in result["differences"]))
        self.assertTrue(any(r["category"] == "attack_boss" and r["key"] == "5" and r["field"] == "health" for r in result["matches"]))


if __name__ == "__main__":
    unittest.main()
