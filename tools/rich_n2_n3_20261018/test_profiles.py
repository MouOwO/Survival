"""Exercise archived evidence and the authoritative CSV generation boundary."""
from pathlib import Path
import contextlib
import copy
import csv
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
RICH_OUTPUTS = {
    "scripts/vscripts/config/generated/rich_wave_definitions.lua",
    "scripts/vscripts/config/generated/rich_wave_stat_variants.lua",
    "scripts/vscripts/config/generated/rich_challenge_combat_profiles.lua",
}
RETIRED_OUTPUTS = ("rich_wave_profiles.lua", "rich_monster_profiles.lua")
RICH_TABLES = (
    "data/csv/怪物与波次系统/rich_wave_definitions.csv",
    "data/csv/挑战与奖励系统/rich_challenge_combat_profiles.csv",
    "data/csv/怪物与波次系统/rich_wave_stat_variants.csv",
)
LUA = (os.environ.get("LUA") or shutil.which("lua5.1") or shutil.which("lua")
       or "C:/Program Files/lua/bin/lua5.1.exe")


def load(relative, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Profiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load("tools/rich_n2_n3_20261018/build_profiles.py", "reviewed_profiles")
        cls.csv_builder = load("tools/build_rich_configs.py", "authoritative_rich_csv")
        cls.temporary = tempfile.TemporaryDirectory(prefix="rich_profiles_", dir=ROOT / "output")
        cls.fixture = Path(cls.temporary.name)
        assert cls.fixture.resolve().is_relative_to((ROOT / "output").resolve())
        (cls.fixture / "scripts/vscripts/config/generated").mkdir(parents=True)
        cls.original = json.loads((ROOT / cls.builder.SOURCE).read_text(encoding="utf-8"))
        files = [cls.builder.SOURCE, "data/balance/rich_n1_wave_stats.json",
            "tools/build_configs.py", "tools/build_rich_configs.py",
            "tools/rich_waves_20261018/build_profiles.py",
            "tools/rich_n2_n3_20261018/build_profiles.py"]
        # Include the real cross-table inputs required by the main builder.
        # Unrelated tables can have independent authoring errors and are outside
        # the rich lifecycle fixture.
        required_names = {
            "wave_definitions.csv", "challenge_combat_profiles.csv", "enums.csv",
            "monster_visual_assets.csv", "monster_visual_components.csv",
            "monster_visual_effects.csv", "wave_visual_definitions.csv",
            "rogue_reward_cards.csv", "rogue_reward_effects.csv",
            "rogue_reward_effect_params.csv", "rogue_reward_effect_lifecycle.csv",
        } | {Path(relative).name for relative in RICH_TABLES}
        files += [str(path.relative_to(ROOT)) for path in (ROOT / "data/csv").rglob("*.csv")
                  if path.name in required_names]
        files += [row["evidence"]["frame"] for row in cls.original["observations"]
                  if row["difficulty_id"] != "N1"]
        for relative in files:
            target = cls.fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.data = copy.deepcopy(self.original)

    def generate(self):
        (self.fixture / self.builder.SOURCE).write_text(
            json.dumps(self.data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        return self.builder.generate(self.fixture)

    @contextlib.contextmanager
    def edited_csv(self, relative, edit):
        path = self.fixture / relative
        original = path.read_bytes()
        rows = list(csv.reader(io.StringIO(original.decode("utf-8-sig"), newline="")))
        index = next(index for index, row in enumerate(rows[1:], 1)
                     if row and row[0] and not row[0].startswith("#"))
        edit(rows, index)
        stream = io.StringIO(newline="")
        csv.writer(stream, lineterminator="\n").writerows(rows)
        path.write_text(stream.getvalue(), encoding="utf-8", newline="\n")
        try:
            yield rows[index]
        finally:
            path.write_bytes(original)

    def assert_outputs(self, expected):
        for relative, rendered in expected.items():
            self.assertEqual((self.fixture / relative).read_text(encoding="utf-8"), rendered)

    def lua_check(self, code):
        subprocess.run([LUA, "-"], input=code, encoding="utf-8", capture_output=True, check=True)

    def test_real_outputs_and_managed_regeneration(self):
        historical = self.generate()
        self.assertEqual(set(historical), {self.builder.LEDGER})
        rendered = self.builder.build(root=self.fixture)
        self.assertEqual(set(rendered), RICH_OUTPUTS)
        expected = {relative: text.encode("utf-8") for relative, text in rendered.items()}
        for relative, data in expected.items():
            self.assertEqual((self.fixture / relative).read_bytes(), data)

        # Exercise actual discovery, index generation and stale-file cleanup.
        # Native unit-name projection has its own fixtures and is outside this
        # test's CSV output lifecycle; the generation/cleanup code is unchanged.
        configs = load("tools/build_configs.py", "managed_configs")
        configs.ROOT = self.fixture
        configs.CSV_ROOT = self.fixture / "data/csv"
        configs.OUT_ROOT = self.fixture / "scripts/vscripts/config/generated"
        stale = (*RETIRED_OUTPUTS, "unowned_stale_fixture.lua")
        for filename in stale:
            (configs.OUT_ROOT / filename).write_text("-- stale fixture\n", encoding="utf-8")
        preserved = configs.OUT_ROOT / "building_white_shells.lua"
        preserved.write_text("-- separately owned asset fixture\n", encoding="utf-8")
        with mock.patch.object(configs.subprocess, "run") as child, contextlib.redirect_stdout(io.StringIO()):
            child.return_value.returncode = 0
            self.assertEqual(configs.main(), 0)
        for filename in stale:
            self.assertFalse((configs.OUT_ROOT / filename).exists(), filename)
        self.assertEqual(preserved.read_text(encoding="utf-8"), "-- separately owned asset fixture\n")
        index = (configs.OUT_ROOT / "index.lua").read_text(encoding="utf-8")
        for relative, data in expected.items():
            self.assertEqual((self.fixture / relative).read_bytes(), data)
            self.assertIn('require("config/generated/' + Path(relative).stem + '")', index)
        for filename in RETIRED_OUTPUTS:
            self.assertNotIn('require("config/generated/' + Path(filename).stem + '")', index)

        self.builder.build(root=self.fixture, check=True)
        stale_output = self.fixture / sorted(RICH_OUTPUTS)[0]
        stale_output.write_text("-- stale generated CSV module\n", encoding="utf-8")
        with self.assertRaisesRegex(AssertionError, "[Ss]tale"):
            self.builder.build(root=self.fixture, check=True)
        self.assertEqual(stale_output.read_text(encoding="utf-8"), "-- stale generated CSV module\n")
        self.builder.build(root=self.fixture)

        # An authored CSV value must reach Lua and survive the old compatibility
        # command, even though it differs from the historical JSON observation.
        changed_health = {}
        def increase_health(rows, index):
            column = rows[0].index("health")
            changed_health["value"] = int(rows[index][column]) + 1
            rows[index][column] = str(changed_health["value"])
        try:
            with self.edited_csv(RICH_TABLES[0], increase_health) as edited:
                updated = self.csv_builder.build(root=self.fixture)
                self.assertNotEqual(updated, rendered)
                self.builder.build(root=self.fixture)
                self.assert_outputs(updated)
                output = self.fixture / "scripts/vscripts/config/generated/rich_wave_definitions.lua"
                self.lua_check("local data=dofile(" + json.dumps(output.as_posix(), ensure_ascii=False) + ")\n"
                               "local row=assert(data.by_id[" + json.dumps(edited[0]) + "])\n"
                               "assert(row.health==" + str(changed_health["value"])
                               + ", 'CSV health edit was overwritten')\n")
        finally:
            self.csv_builder.build(root=self.fixture)

        # Archived JSON can fail its audit without affecting CSV runtime output.
        archived = self.fixture / self.builder.SOURCE
        archived_bytes = archived.read_bytes()
        try:
            self.data["difficulties"]["N2"]["waves"]["1"]["batches"]["1N1"]["health"] += 1
            archived.write_text(json.dumps(self.data, ensure_ascii=False), encoding="utf-8")
            self.builder.build(root=self.fixture)
            for relative, data in expected.items():
                self.assertEqual((self.fixture / relative).read_bytes(), data)
            with self.assertRaisesRegex(AssertionError, "Observed value changed"):
                self.builder.build(root=self.fixture, check=True)
        finally:
            archived.write_bytes(archived_bytes)

        n1 = load("tools/rich_waves_20261018/build_profiles.py", "archived_n1_profiles")
        self.assertEqual(set(n1.build(root=self.fixture)), RICH_OUTPUTS)
        n1.build(root=self.fixture, check=True)
        for filename in RETIRED_OUTPUTS:
            self.assertFalse((configs.OUT_ROOT / filename).exists(), filename)
        self.assertFalse((self.fixture / self.builder.LEDGER).exists(),
                         "compatibility builds must not rewrite the archived ledger")

    def test_truncated_csv_rows_are_rejected_without_partial_writes(self):
        expected = self.csv_builder.build(root=self.fixture)
        for relative in RICH_TABLES:
            with self.subTest(table=relative):
                with self.edited_csv(relative, lambda rows, index: rows[index].pop()):
                    with self.assertRaisesRegex(ValueError, "column count mismatch"):
                        self.csv_builder.build(root=self.fixture)
                    self.assert_outputs(expected)

    def test_duplicate_csv_identities_are_rejected(self):
        for relative in RICH_TABLES:
            with self.subTest(table=relative):
                with self.edited_csv(relative, lambda rows, index: rows.append(list(rows[index]))):
                    with self.assertRaisesRegex(AssertionError, "Duplicate rich identity"):
                        self.csv_builder.build(root=self.fixture)

    def test_enabled_flags_and_nonfinite_timings_cannot_bypass_validation(self):
        expected = self.csv_builder.build(root=self.fixture)
        for relative in RICH_TABLES:
            for invalid in ("", "unknown"):
                with self.subTest(table=relative, enabled=invalid):
                    def edit(rows, index):
                        rows[index][rows[0].index("enabled")] = invalid
                    with self.edited_csv(relative, edit):
                        with self.assertRaisesRegex(AssertionError, "enabled flag must be explicit"):
                            self.csv_builder.validate_tables(self.fixture)

        # Nil generated enabled flags spawn at runtime. An extra 61st monster
        # must not escape the quota check by being skipped only by validation.
        def add_extra_monster(rows, index):
            extra = list(rows[index])
            extra[0] += "_empty_enabled"
            extra[rows[0].index("batch_id")] += "_extra"
            extra[rows[0].index("spawn_order")] = "999"
            extra[rows[0].index("monster_count")] = "1"
            extra[rows[0].index("enabled")] = ""
            rows.append(extra)
        with self.edited_csv(RICH_TABLES[0], add_extra_monster):
            with self.assertRaisesRegex(AssertionError, "enabled flag must be explicit"):
                self.csv_builder.build(root=self.fixture)
            self.assert_outputs(expected)

        for field in ("attack_speed", "model_scale_multiplier", "wait_seconds", "spawn_interval"):
            with self.subTest(field=field, value="Infinity"):
                def edit(rows, index):
                    rows[index][rows[0].index(field)] = "Infinity"
                with self.edited_csv(RICH_TABLES[0], edit):
                    with self.assertRaisesRegex(AssertionError, "Invalid rich " + field):
                        self.csv_builder.validate_tables(self.fixture)

    def test_json_provenance_preserves_strings_without_executing_them(self):
        payload = '"}; _G.rich_csv_injected=true; --\\' + "".join(chr(code) for code in range(32)) + "123"
        metadata = {"payload": payload, payload: {"flags": [True, False], "value": 3.5}}
        def edit(rows, index):
            rows[index][rows[0].index("rich_field_sources")] = json.dumps(metadata)
        try:
            with self.edited_csv(RICH_TABLES[0], edit) as edited:
                self.csv_builder.build(root=self.fixture)
                output = self.fixture / "scripts/vscripts/config/generated/rich_wave_definitions.lua"
                expected_bytes = ",".join(str(byte) for byte in payload.encode("utf-8"))
                self.lua_check("local data=dofile(" + json.dumps(output.as_posix(), ensure_ascii=False) + ")\n"
                               "local value=assert(data.by_id[" + json.dumps(edited[0]) + "]).rich_field_sources\n"
                               "local expected=string.char(" + expected_bytes + ")\n"
                               "assert(value.payload==expected and _G.rich_csv_injected==nil)\n"
                               "assert(value[expected].flags[1]==true and value[expected].flags[2]==false)\n"
                               "assert(value[expected].value==3.5)\n")
        finally:
            self.csv_builder.build(root=self.fixture)

    def test_json_null_and_nonfinite_values_are_rejected_without_partial_writes(self):
        expected = self.csv_builder.build(root=self.fixture)
        for raw in ('null', '{"value":null}', '{"nested":[null]}', '{"value":NaN}',
                    '{"nested":[Infinity]}', '{"value":-Infinity}', '{"value":1e309}'):
            with self.subTest(value=raw):
                def edit(rows, index):
                    rows[index][rows[0].index("rich_field_sources")] = raw
                with self.edited_csv(RICH_TABLES[0], edit):
                    with self.assertRaisesRegex(ValueError, "null|finite"):
                        self.csv_builder.build(root=self.fixture)
                    self.assert_outputs(expected)

    def test_missing_wave_batch_is_rejected(self):
        del self.data["difficulties"]["N2"]["waves"]["1"]["batches"]["1N1"]
        with self.assertRaisesRegex(AssertionError, "wave batches"):
            self.generate()

    def test_observed_value_cannot_be_rewritten(self):
        self.data["difficulties"]["N2"]["waves"]["1"]["batches"]["1N1"]["health"] += 1
        with self.assertRaisesRegex(AssertionError, "Observed value changed"):
            self.generate()

    def test_estimate_cannot_be_claimed_as_observation(self):
        self.data["difficulties"]["N3"]["encounters"]["encounter_rebirth_10"]["estimated"] = False
        with self.assertRaisesRegex(AssertionError, "Estimated flag"):
            self.generate()

    def test_estimate_operands_must_match_the_result(self):
        profile = self.data["difficulties"]["N3"]["encounters"]["encounter_rebirth_10"]
        profile["health"] += 1
        with self.assertRaisesRegex(AssertionError, "operands"):
            self.generate()

    def test_large_health_display_units_are_checked(self):
        record = next(row for row in self.data["observations"] if row["record_id"] == "N2-REBIRTH-10")
        record["stats"]["health"] /= 10
        with self.assertRaisesRegex(AssertionError, "unit conversion"):
            self.generate()

    def test_evidence_bytes_cannot_change_silently(self):
        record = next(row for row in self.data["observations"] if row["difficulty_id"] == "N2")
        path = self.fixture / record["evidence"]["frame"]
        original = path.read_bytes()
        try:
            path.write_bytes(original[:-1] + bytes([original[-1] ^ 1]))
            with self.assertRaisesRegex(AssertionError, "Evidence changed"):
                self.generate()
        finally:
            path.write_bytes(original)


if __name__ == "__main__":
    unittest.main(verbosity=2)
