"""Check committed video evidence, CSV provenance and isolated mode generation.

Run with Python's standard library only. No source video or output/ file is an
input: archived crops, reviewed JSON and authored CSVs are the audit boundary.
"""
from __future__ import annotations

import copy
import csv
import hashlib
import importlib.util
import json
import math
import re
import shutil
import sys
import tempfile
import unittest
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SOURCE = "data/balance/mode_monsters_20261020.json"
EVIDENCE = Path("docs/evidence/mode_monsters_20261020")
FIELDS = ("health", "attack", "war3_armor")
SUPPORT = {"cold": ("N1", "N2", "N3", "N4"), "scourge": ("N1", "N2")}
RICH_TABLES = (
    "data/csv/怪物与波次系统/rich_wave_definitions.csv",
    "data/csv/挑战与奖励系统/rich_challenge_combat_profiles.csv",
    "data/csv/怪物与波次系统/rich_wave_stat_variants.csv",
)
# Captured before this task materialized N4. Ignore serialization/newline
# differences, but preserve every authored non-N4 field and row.
LEGACY_DIGESTS = (
    "f168c4a50b9ba6c670112d15752e30c207619c83e56da9ec47d451c8b50d255b",
    "f7b4da615c5be3d8341434ba73469b8b953d0dac3cf5319d1486685b47ab4920",
    "d61a6a06c705e3ebd1115be1817be354609151fba5fcc6a57e235492bbaef02e",
)


def load(relative, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_rows(path):
    with Path(path).open(encoding="utf-8-sig", newline="") as stream:
        return [row for row in csv.DictReader(stream)
                if not next(iter(row.values())).startswith("#")]


def quantity(raw):
    """Return the displayed maximum and its resolution, using decimal math."""
    text = str(raw).strip().split("/")[-1].strip()
    text = text.replace(",", "").replace("，", "").replace(" ", "")
    # Curated OCR may preserve 方 for the visually reviewed green 万 glyph.
    text = text.replace("方", "万").replace("萬", "万").replace("億", "亿")
    match = re.fullmatch(r"(\d+(?:\.\d+)?)(万亿|亿|万|兆)?", text)
    assert match, f"Unrecognized numeric display: {raw!r}"
    scale = {None: 1, "万": 10_000, "亿": 100_000_000,
             "万亿": 1_000_000_000_000, "兆": 1_000_000_000_000}[match[2]]
    decimals = len(match[1].split(".")[1]) if "." in match[1] else 0
    return Decimal(match[1]) * scale, Decimal(scale) / (10 ** decimals)


def raw_display(record, field):
    names = {
        "health": ("health_display", "health_max_raw", "health_raw"),
        "attack": ("attack_display", "attack_raw"),
        "war3_armor": ("war3_armor_display", "armor_display", "war3_armor_raw", "armor_raw"),
    }
    for key in names[field]:
        if record.get(key) is not None:
            return record[key]
    for key in ("raw_display", "display_raw", "displayed_raw"):
        values = record.get(key)
        if isinstance(values, dict) and values.get(field) is not None:
            return values[field]
    return None


def wave_number(record):
    return record.get("wave_number", record.get("wave"))


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate_observations(data, root=ROOT):
    records = data["observations"]
    assert records, "No reviewed observations"
    ids, frames = set(), {}
    for record in records:
        rid = record["record_id"]
        assert rid and rid not in ids, f"Duplicate observation: {rid}"
        ids.add(rid)
        mode, difficulty = record["mode_id"], record["difficulty_id"]
        allowed = SUPPORT.get(mode, ("N4",) if mode == "rich" else ())
        assert difficulty in allowed, (rid, "unsupported observation difficulty")
        assert not record.get("estimated", False), (rid, "estimate inside observations")
        stats, displayed = record["stats"], record.get("displayed_stats", {})
        assert set(FIELDS).issubset(stats), (rid, "incomplete stats schema")
        for field in FIELDS:
            value = stats[field]
            if value is not None:
                assert finite(value) and (value >= 0 if field == "war3_armor" else value > 0), (rid, field)
            shown = displayed.get(field)
            if shown is not None:
                assert finite(shown) and (shown >= 0 if field == "war3_armor" else shown > 0), (rid, field, "display")
                assert value is None or shown == value, (rid, field, "derived base passed off as observation")
            raw = raw_display(record, field)
            if raw is not None:
                converted, resolution = quantity(raw)
                assert shown is not None or value is not None, (rid, field, "raw display without a numeric observation")
                assert Decimal(str(shown if shown is not None else value)) == converted, (rid, field, raw)
                declared = record.get("display_resolution", {}).get(field)
                if declared is not None:
                    assert Decimal(str(declared)) == resolution, (rid, field, "false display precision")
        health_raw = raw_display(record, "health")
        assert health_raw is not None and stats["health"] is not None, (rid, "maximum health evidence missing")
        basis = str(record.get("health_basis", "")).lower()
        assert "/" in str(health_raw) or re.search(r"maximum|max|最大|斜线", basis), (rid, "current health used without maximum basis")
        if stats["war3_armor"] is None:
            assert displayed.get("war3_armor") is not None, (rid, "unknown armor lost its displayed evidence")
        if "video_seconds" in record:
            assert finite(record["video_seconds"]) and record["video_seconds"] >= 0, (rid, "invalid timestamp")
        evidence = record["evidence"]
        relative = Path(evidence["frame"])
        path = (root / relative).resolve()
        assert not relative.is_absolute() and path.is_relative_to((root / EVIDENCE).resolve()), (rid, "unarchived evidence path")
        digest = evidence["frame_sha256"]
        assert re.fullmatch(r"[0-9a-f]{64}", digest), (rid, "invalid evidence digest")
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, (rid, "evidence hash mismatch")
        identity = (mode, difficulty, wave_number(record), tuple(stats[f] for f in FIELDS))
        assert digest not in frames or frames[digest] == identity, (rid, "one crop assigned incompatible stats")
        frames[digest] = identity
    return {record["record_id"]: record for record in records}


def validate_origins(rows, observations, root=ROOT):
    cache = {}
    for row in rows:
        identity = next(iter(row.values()))
        sources = json.loads(row.get("field_sources") or row["rich_field_sources"])
        measured = 0
        mode = row.get("mode_id", "rich")
        for field in FIELDS:
            source = sources[field]
            method = source["method"]
            assert source.get("explanation"), (identity, field, "missing provenance explanation")
            if method == "video_panel":
                measured += 1
                observed = observations[source["record_id"]]
                assert (mode, row["difficulty_id"]) == (observed["mode_id"], observed["difficulty_id"]), (identity, field, "cross-mode value mislabeled measured")
                assert observed["stats"][field] is not None and float(row[field]) == observed["stats"][field], (identity, field, "measured value changed")
                if row.get("member_id"):
                    assert row["member_id"] == observed.get("member_id"), (identity, field, "wrong selected member")
                else:
                    assert int(row["wave_number"]) == wave_number(observed), (identity, field, "wrong selected wave")
                    if row.get("member_role") == "assault_boss":
                        assert observed.get("role") == "assault_boss" or observed.get("category") in ("wave_boss", "assault_boss"), (identity, "ordinary monster used as boss measurement")
            else:
                assert "estimate" in method, (identity, field, "unidentified derivation")
                refs = source.get("reference_record_ids")
                assert refs, (identity, field, "estimate without observed references")
                modes = {observations[rid]["mode_id"] for rid in refs}
                if modes != {mode}:
                    assert "cross_mode" in method and source.get("reference_mode_id") in modes, (identity, field, "undisclosed cross-mode calibration")
                relative = source["reference_table"]
                path = (root / relative).resolve()
                assert path.is_relative_to((root / "data/csv").resolve()), (identity, field, "invalid reference table")
                if relative not in cache:
                    cache[relative] = read_rows(path)
                reference_rows = cache[relative]
                candidates = [r for r in reference_rows if r["difficulty_id"] == source["reference_difficulty_id"]]
                if any("mode_id" in r for r in candidates):
                    reference_mode = source.get("reference_mode_id", mode)
                    candidates = [r for r in candidates if r.get("mode_id") == reference_mode]
                if row.get("member_id"):
                    member = source.get("reference_member_id") or row["member_id"]
                    candidates = [r for r in candidates if r.get("member_id") == member]
                else:
                    wave = str(source.get("reference_wave_number") or row["wave_number"])
                    batch = source.get("reference_batch_id") or row["batch_id"]
                    candidates = [r for r in candidates if r.get("wave_number") == wave and r.get("batch_id") == batch]
                    if "variant_index" in row and "variant" in relative:
                        index = str(source.get("reference_variant_index") or row["variant_index"])
                        candidates = [r for r in candidates if r.get("variant_index") == index]
                assert any(float(r[field]) == source["input_value"] for r in candidates), (identity, field, "input differs from declared reference row")
                additive, quantum = source.get("additive", 0), source.get("rounding_quantum", 1)
                expected = math.floor(((source["input_value"] - additive) * source["factor"] + additive) / quantum + .5) * quantum
                assert float(row[field]) == expected, (identity, field, "estimate formula mismatch")
                if method == "cross_difficulty_estimate":
                    assert source["reference_difficulty_id"] != row["difficulty_id"], (identity, "self-referencing difficulty estimate")
                    ratio_table = source["ratio_reference_table"]
                    assert ratio_table in RICH_TABLES, (identity, "undeclared old difficulty relationship")
                    if ratio_table not in cache:
                        cache[ratio_table] = read_rows(root / ratio_table)
                    related = cache[ratio_table]
                    if row.get("member_id"):
                        related = [r for r in related if r.get("member_id") == row["member_id"]]
                    else:
                        related = [r for r in related if r.get("wave_number") == row["wave_number"] and r.get("batch_id") == row["batch_id"]]
                    target = next(r for r in related if r["difficulty_id"] == row["difficulty_id"])
                    sibling = next(r for r in related if r["difficulty_id"] == source["reference_difficulty_id"])
                    assert math.isclose(source["factor"], float(target[field]) / float(sibling[field]), rel_tol=1e-12), (identity, field, "changed existing difficulty ratio")
        status = "video_observed" if measured == 3 else "mixed" if measured else "estimated"
        assert row["data_status"] == status, (identity, "incorrect overall provenance status")
        flag = row.get("rich_stats_estimated", row.get("estimated"))
        assert flag in (("0", "false") if measured == 3 else ("1", "true")), (identity, "incorrect estimate flag")


class RecordedModeData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load("tools/build_recorded_mode_configs.py", "recorded_modes_independent_audit")
        cls.data = json.loads((ROOT / SOURCE).read_text(encoding="utf-8"))
        cls.observations = {r["record_id"]: r for r in cls.data["observations"]}
        cls.tables = [read_rows(ROOT / relative) for relative in cls.builder.TABLES]

    def test_archived_units_maximum_health_and_evidence(self):
        validate_observations(self.data)
        self.assertEqual(quantity("700/42.300万")[0], 423000)
        self.assertEqual(quantity("21.150亿")[0], 2115000000)
        self.assertEqual(quantity("1.34亿")[0], 134000000)
        self.assertEqual(quantity("1.250万亿")[0], 1250000000000)
        altered = copy.deepcopy(self.data)
        altered["observations"][0]["evidence"]["frame_sha256"] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "evidence hash mismatch"):
            validate_observations(altered)

    def test_independent_hand_reviewed_panels(self):
        # Constants were read from source video panels, not derived from CSV or
        # the data builder. Large attacks retain the video's display precision.
        cases = (
            ("scourge", "N1", 1, 423000, 1693, 60),
            ("scourge", "N2", 1, 561500, 2247, 56),
            ("scourge", "N1", 8, 16920000, 761402, 900),
            ("scourge", "N2", 20, 617700000, 24706002, 3640),
            ("scourge", "N1", 25, 2115000000, 43992000, 4800),
            ("scourge", "N2", 25, 2807500000, 58396000, 4480),
            ("scourge", "N2", 30, 6738000000, 134000000, 5180),
            ("cold", "N3", 29, 63000000, 3780002, 1440),
            ("rich", "N4", 30, 63600000, 3180002, 1663),
        )
        for mode, difficulty, wave, health, attack, armor in cases:
            with self.subTest(mode=mode, difficulty=difficulty, wave=wave):
                found = [r for r in self.data["observations"] if r["mode_id"] == mode and r["difficulty_id"] == difficulty and wave_number(r) == wave and r["stats"]["health"] == health and r["stats"]["attack"] == attack]
                self.assertTrue(found, "Known source panel missing or rescaled")
                self.assertTrue(any(r.get("displayed_stats", {}).get("war3_armor", r["stats"]["war3_armor"]) == armor for r in found))
        for difficulty, health, attack, armor in (("N1", 16807800000, 74080800, 2210), ("N2", 21850200000, 92601000, 2380)):
            found = [r for r in self.data["observations"] if r["mode_id"] == "scourge" and r["difficulty_id"] == difficulty and re.search(r"B[O0]+SS\s*10", r.get("name", ""), re.I)]
            self.assertTrue(any(r["stats"]["health"] == health and r["stats"]["attack"] == attack and r.get("displayed_stats", {}).get("war3_armor", r["stats"]["war3_armor"]) == armor for r in found), "Known rebirth maximum/attack/armor changed")
        for difficulty, wave, health, attack, shown_armor in (
            ("N1", 10, 25384230, 3384002, 5970),
            ("N1", 20, 423000000, 51183000, 14970),
            ("N2", 10, 33695610, 4492002, 5572),
            ("N2", 15, 168500000, 16845002, 13972),
            ("N2", 30, 8984000000, 179000000, 13972),
        ):
            found = [r for r in self.data["observations"] if r["mode_id"] == "scourge" and r["difficulty_id"] == difficulty and wave_number(r) == wave and r["stats"]["health"] == health and r["stats"]["attack"] == attack and r.get("role") == "assault_boss"]
            self.assertTrue(found, (difficulty, wave, "known explicit boss missing"))
            self.assertTrue(any(r["stats"]["war3_armor"] is None and r["displayed_stats"]["war3_armor"] == shown_armor for r in found), "Debuffed boss armor must stay displayed evidence, not an observed clean base")
        for r in self.data["observations"]:
            if r["mode_id"] == "scourge" and r["difficulty_id"] == "N2" and wave_number(r) == 28:
                self.assertNotEqual(r["stats"]["attack"], 24649000000, "Sword-spirit attack leaked through the LV28 selection transition")
        # Check integration as well as the archive. These are the selected
        # existing ground members, not the lower-attack flying model used by a
        # naive minimum-across-all-models calibration.
        for wave, batch, health, attack, armor in (
            (11, "11N1", 16920000, 1692002, 600),
            (14, "14N1", 33840000, 846002, 1050),
        ):
            row = next(r for r in self.tables[0] if r["mode_id"] == "scourge" and r["difficulty_id"] == "N1" and int(r["wave_number"]) == wave and r["batch_id"] == batch)
            self.assertEqual(tuple(float(row[f]) for f in FIELDS), (health, attack, armor), "Known selected ground member was calibrated against another model")
        boss = next(r for r in self.tables[0] if r["mode_id"] == "scourge" and r["difficulty_id"] == "N1" and r["wave_number"] == "10" and r["member_role"] == "assault_boss")
        self.assertEqual((float(boss["health"]), float(boss["attack"])), (25384230, 3384002))
        boss_sources = json.loads(boss["rich_field_sources"])
        self.assertEqual(boss_sources["health"]["method"], "video_panel")
        self.assertEqual(boss_sources["attack"]["method"], "video_panel")
        self.assertNotEqual(boss_sources["war3_armor"]["method"], "video_panel")

    def test_field_sources_and_model_roles(self):
        self.assertEqual(self.builder.DIFFICULTIES, SUPPORT)
        self.builder.validate_tables(ROOT)
        all_rows = [row for rows in self.tables for row in rows]
        all_rows += [r for relative in RICH_TABLES for r in read_rows(ROOT / relative) if r["difficulty_id"] == "N4"]
        validate_origins(all_rows, self.observations)
        template = {(r["difficulty_id"], r["wave_number"], r["batch_id"]): r for r in read_rows(ROOT / RICH_TABLES[0])}
        counts = defaultdict(int)
        for row in self.tables[0]:
            self.assertIn(row["difficulty_id"], SUPPORT[row["mode_id"]])
            if row["enabled"].lower() not in ("1", "true"):
                continue
            key = row["difficulty_id"], row["wave_number"], row["batch_id"]
            for field in ("archetype_id", "member_role", "monster_count", "spawn_order", "wait_seconds", "spawn_interval", "attack_speed", "is_boss", "boss_warning", "movement_type_override", "model_scale_multiplier"):
                self.assertEqual(row[field], template[key][field], (key, field))
            counts[(row["mode_id"], row["difficulty_id"], int(row["wave_number"]))] += int(row["monster_count"])
        expected = {(mode, difficulty, wave) for mode, difficulties in SUPPORT.items() for difficulty in difficulties for wave in range(1, 26 if difficulty == "N1" else 31)}
        self.assertEqual(set(counts), expected)
        self.assertTrue(all(count == 60 for count in counts.values()), "Leader/boss included total must stay 60")

    def test_previously_recorded_rich_difficulties_unchanged(self):
        for relative, expected in zip(RICH_TABLES, LEGACY_DIGESTS):
            rows = [r for r in read_rows(ROOT / relative) if r["difficulty_id"] != "N4"]
            canonical = json.dumps(rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
            self.assertEqual(hashlib.sha256(canonical).hexdigest(), expected, relative)

    def test_csv_generation_is_current_and_read_only(self):
        outputs = ["scripts/vscripts/config/generated/" + Path(relative).stem + ".lua" for relative in self.builder.TABLES]
        outputs.append("scripts/vscripts/config/generated/index.lua")
        before = {relative: (ROOT / relative).read_bytes() for relative in (*self.builder.TABLES, *outputs, SOURCE)}
        rendered = self.builder.build(ROOT, check=True)
        self.assertEqual(set(rendered), set(outputs))
        for relative, original in before.items():
            self.assertEqual((ROOT / relative).read_bytes(), original, "--check modified " + relative)
        registry = (ROOT / outputs[-1]).read_text(encoding="utf-8")
        for relative in self.builder.TABLES:
            entry = 'M["' + Path(relative).stem + '"] = require("config/generated/' + Path(relative).stem + '")'
            self.assertEqual(registry.splitlines().count(entry), 1, entry)
        # A stale artifact must be rejected without being silently repaired.
        with tempfile.TemporaryDirectory(prefix="mode_monster_check_") as folder:
            fixture = Path(folder)
            for relative in (*self.builder.TABLES, *RICH_TABLES, *outputs, SOURCE, "tools/build_configs.py"):
                target = fixture / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            stale = fixture / outputs[0]
            stale.write_text("-- deliberately stale test fixture\n", encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "Stale generated table"):
                self.builder.build(fixture, check=True)
            self.assertEqual(stale.read_text(encoding="utf-8"), "-- deliberately stale test fixture\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
