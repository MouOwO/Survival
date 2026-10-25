import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import extract_original_monsters as extractor


class ExtractionTests(unittest.TestCase):
    def test_inventory_only_indexes_calls(self):
        source = """function example takes nothing returns nothing
//call SetHeroLevel(x, 99, false)
call SetUnitState(u, UNIT_STATE_MAX_LIFE, 200.5)
set text = \"SetUnitState(fake)\"
call UnitAddAbility(u, 'A009')
endfunction
"""
        rows = extractor.stat_write_inventory(source)
        self.assertEqual([r["native"] for r in rows], ["SetUnitState", "UnitAddAbility"])
        self.assertEqual([r["line"] for r in rows], [3, 5])
        self.assertTrue(all(r["function"] == "example" for r in rows))

    def test_revision_rejected_before_output_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "absent"
            with patch.object(extractor.units_parser, "read_members", return_value=({"war3map.j": b"unreviewed"}, {})):
                with self.assertRaisesRegex(ValueError, "unsupported_source_revision"):
                    extractor.extract(Path(folder) / "source.w3x", output)
            self.assertFalse(output.exists())

    def test_slk_product_is_distinct_from_corrected_game_hp(self):
        units = {"units": [{"raw_id": "h08W", "hp": 50104960, "armor": 800,
            "attack1_base": 2600000, "attack1_interval": 0.5}]}
        rules = {"units": [{"class": "ten_commandments", "key": "ten7", "raw_id": "h08W", "name": "沉默"}]}
        tiers = {"rows": [{"mode_id": 1, "difficulty": 2, "multiplier_exact_decimal": {
            "xgdg_oBAA": "2.5", "xgdg_MBAA": "2"}}]}
        before = json.dumps(units)
        row = extractor.standard_n2_challenges(units, rules, tiers)[0]
        self.assertEqual(row["hp_slk_product"], "125262400.0")
        self.assertEqual(row["attack_base_slk_product"], "5720000.0")
        self.assertNotEqual(row["hp_slk_product"], "125250000")
        self.assertEqual(before, json.dumps(units))

    def test_legacy_button_branch_cannot_replace_primary_difficulty(self):
        def tier(classification, hp):
            return {"mode_id": 1, "difficulty": 2, "classification": classification,
                "multiplier_exact_decimal": {"xgdg_oBAA": hp, "xgdg_MBAA": "2"}}
        tiers = {"rows": [tier("alternate_button_or_unbound_legacy_row", "99"),
            tier("primary_dialog_row", "2.5")]}
        self.assertEqual(len(extractor.compact_difficulties(tiers)), 1)
        self.assertEqual(len(extractor.compact_difficulties(tiers, primary=False)), 1)
        data = {"units": [{"raw_id": "test", "hp": 100, "armor": 2,
            "attack1_base": 3, "attack1_interval": 1}]}
        rules = {"units": [{"class": "four_rooms", "raw_id": "test", "key": "room", "name": "room"}]}
        self.assertEqual(extractor.standard_n2_challenges(data, rules, tiers)[0]["hp_slk_product"], "250.0")


if __name__ == "__main__":
    unittest.main()
