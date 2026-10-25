"""Static non-wave extraction fixtures and an optional real-source replay.

Run with: python -m unittest discover -s tools/tests -p test_war3_nonwave.py
The reviewed original source is private/ignored. Real replay runs automatically
when the local audit files exist, or when WAR3_NONWAVE_JASS, WAR3_NONWAVE_RAW_ROOT
and WAR3_NONWAVE_UNITS point to an extracted source bundle.
"""
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest

REPO = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("war3_nonwave", REPO / "tools/war3_extract/nonwave.py")
nonwave = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nonwave)


def fixture_unit(raw, hp, name="无欲"):
    return {"raw_id": raw, "name": name, "hp": hp, "armor": 70,
            "attack1_base": 100, "attack1_dice": 1, "attack1_sides": 6,
            "attack1_interval": .5, "attack1_range": 128, "primary_attribute": "_",
            "provenance": {"name": {"file": "Units\\CampaignUnitStrings.txt", "line": 9},
                "hp": {"file": "Units\\UnitBalance.slk", "line": 8, "field": "HP"}}}


class NonwaveExtractionTests(unittest.TestCase):
    def test_source_hash_guard_rejects_changed_revision(self):
        with self.assertRaisesRegex(nonwave.ExtractionError, "unsupported_source_revision"):
            nonwave.check_revision(b"function CreateUnits takes nothing returns nothing\nendfunction\n")

    def test_cli_all_inputs_required(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr), self.assertRaises(SystemExit) as error:
            nonwave.main(["--jass", "map.j"])
        self.assertEqual(error.exception.code, 2)
        self.assertIn("--raw-root", stderr.getvalue())
        self.assertIn("--units", stderr.getvalue())
        self.assertIn("--output", stderr.getvalue())

    def test_cli_wrong_revision_fails_before_other_inputs_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jass = root / "changed.j"
            jass.write_bytes(b"not the supported map source")
            stdout, stderr = io.StringIO(), io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                status = nonwave.main(["--jass", str(jass), "--raw-root", str(root / "absent"),
                    "--units", str(root / "also-absent.json"), "--output", str(root / "output")])
            self.assertEqual(status, 1)
            self.assertEqual(json.loads(stderr.getvalue())["error"], "unsupported_source_revision")
            self.assertEqual(stdout.getvalue(), "")
            self.assertFalse((root / "output").exists())

    def test_units_schema_and_duplicate_identity_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "units.json"
            path.write_text('{"schema":"other","units":[]}', encoding="utf-8")
            with self.assertRaisesRegex(nonwave.ExtractionError, "unsupported_units_schema"):
                nonwave.load_units(path)
            path.write_text(json.dumps({"schema": "war3_units_base_v1", "units": [
                fixture_unit("h08U", 40104960), fixture_unit("h08U", 160195520)]}), encoding="utf-8")
            with self.assertRaisesRegex(nonwave.ExtractionError, "invalid_unit_identity"):
                nonwave.load_units(path)

    def test_raw_identity_not_duplicate_name_or_index_selects_base(self):
        rows = {"h08U": fixture_unit("h08U", 40104960), "h091": fixture_unit("h091", 160195520)}
        source = SimpleNamespace(tables={"Units/UnitData.slk": {}, "Units/UnitAbilities.slk": {}})
        active = nonwave.unit_base("h08U", rows, source)
        unused = nonwave.unit_base("h091", rows, source)
        self.assertEqual(active["name"], unused["name"])
        self.assertEqual(active["hp"]["value"], 40104960)
        self.assertEqual(unused["hp"]["value"], 160195520)
        self.assertEqual(active["hp"]["line"], 8)
        self.assertEqual(active["attack1_base"]["value"], 100)
        self.assertEqual(active["attack1_dice"]["value"], 1)
        self.assertEqual(active["attack1_sides"]["value"], 6)
        with self.assertRaisesRegex(nonwave.ExtractionError, "missing_unit_record"):
            nonwave.unit_base("0001", rows, source)

    def test_missing_numeric_stat_is_not_zero_filled(self):
        rows = {"h08U": fixture_unit("h08U", None)}
        with self.assertRaisesRegex(nonwave.ExtractionError, "missing_unit_stat: h08U.hp"):
            nonwave.unit_base("h08U", rows, None)

    def test_raw_member_discovery_rejects_ambiguous_duplicate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for subdir, content in [("one", b"same"), ("two", b"same")]:
                path = root / subdir / "Units/ItemData.slk"
                path.parent.mkdir(parents=True)
                path.write_bytes(content)
            member = nonwave.resolve_member(root, "Units/ItemData.slk")
            self.assertEqual(member.read_bytes(), b"same")
            (root / "two/Units/ItemData.slk").write_bytes(b"different")
            with self.assertRaisesRegex(nonwave.ExtractionError, "ambiguous_source_member"):
                nonwave.resolve_member(root, "Units/ItemData.slk")
            with self.assertRaisesRegex(nonwave.ExtractionError, "missing_source_member"):
                nonwave.resolve_member(root, "Units/Missing.slk")

    def test_source_index_deduplicates_without_exporting_source_bodies(self):
        span = {"member": "war3map.j", "line": 4, "end_line": 7,
                "function": "SomeAction", "source_sha256": nonwave.SUPPORTED_JASS_SHA256,
                "span_utf8_lf_sha256": "span digest"}
        result = nonwave.source_index({"a": [span], "b": {"nested": span}})
        self.assertEqual(result["spans"], [span])
        self.assertNotIn('"text"', json.dumps(result))

    def test_real_source_replays_all_90_checks_and_separate_category_orders(self):
        names = ["WAR3_NONWAVE_JASS", "WAR3_NONWAVE_RAW_ROOT", "WAR3_NONWAVE_UNITS"]
        configured = [os.environ.get(name) for name in names]
        if any(configured) and not all(configured):
            self.fail("Set all three WAR3_NONWAVE_JASS/RAW_ROOT/UNITS variables together")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            if all(configured):
                jass, raw, units = map(Path, configured)
            else:
                jass = REPO / "output/war3_monster_feasibility_20261025/extracted/war3map.j"
                units = REPO / "output/original_map_extract_20261025/units/units_base.json"
                if not jass.exists() or not units.exists():
                    self.skipTest("private original-map source not installed")
                raw = root / "raw"
                target = raw / "Units"
                target.mkdir(parents=True)
                for filename in ["UnitBalance.slk", "UnitData.slk", "UnitWeapons.slk"]:
                    shutil.copyfile(jass.parent / "Units" / filename, target / filename)
                for filename in ["UnitAbilities.slk", "ItemData.slk"]:
                    shutil.copyfile(units.parent / "raw/Units" / filename, target / filename)
            output = root / "result"
            summary = nonwave.run(jass, raw, units, output)
            self.assertEqual(summary["rows"], 88)
            self.assertEqual(summary["archive_rows"], 29)
            self.assertEqual(summary["classes"], nonwave.EXPECTED_CLASSES)
            validation = json.loads((output / "validation.json").read_text(encoding="utf-8"))
            self.assertTrue(validation["passed"])
            self.assertEqual(validation["checks"], 90)
            self.assertGreaterEqual(validation["verified_SLK_fields"], 985)
            rules = json.loads((output / "challenge_rules.json").read_text(encoding="utf-8"))
            ten_first = next(r for r in rules["units"] if r["class"] == "ten_commandments" and r["order"] == 1)
            shadow_first = next(r for r in rules["units"] if r["class"] == "archive_shadow" and r["entry_item_prio"] == 1)
            self.assertEqual((ten_first["raw_id"], shadow_first["raw_id"]), ("h08Z", "H09B"))
            self.assertEqual(shadow_first["entry_item_scale"], 1.8)
            self.assertEqual(shadow_first["derived_slk_products"]["hp"], 9000000)
            self.assertEqual(shadow_first["derived_slk_products"]["attack_base"], 189000)
            self.assertNotIn("evidence_spans.json", {p.name for p in output.iterdir()})
            index = json.loads((output / "source_index.json").read_text(encoding="utf-8"))
            self.assertGreater(len(index["spans"]), 100)
            self.assertTrue(all(s["source_sha256"] == nonwave.SUPPORTED_JASS_SHA256 for s in index["spans"]))
            self.assertNotIn('"text"', json.dumps(index))
            changed_units = json.loads(units.read_text(encoding="utf-8"))
            next(r for r in changed_units["units"] if r["raw_id"] == "h08Z")["hp"] += 100
            changed_path = root / "modified-units.json"
            changed_path.write_text(json.dumps(changed_units, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(nonwave.ExtractionError, "unit_source_mismatch: h08Z.hp"):
                nonwave.run(jass, raw, changed_path, root / "must-not-be-written")
            self.assertFalse((root / "must-not-be-written").exists())


if __name__ == "__main__":
    unittest.main()
