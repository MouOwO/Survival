"""Quoted tooltip records must match in-game generated data and server bundles."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import read_csv


class ArchiveCsvRecords(unittest.TestCase):
    def test_quoted_multiline_tooltip_preserves_hash_body_and_quotes(self):
        with tempfile.TemporaryDirectory(prefix="archive-csv-record-") as directory:
            path = Path(directory) / "sample.csv"
            path.write_text('id,description,count,enabled,effect_ids\n'
                            '#中文表头:编号,说明,次数,启用,词条\n'
                            '#types:string,string,number,boolean,list\n'
                            'first,"第一段\n#这一行是正文\n含""引号""与,逗号\n最后一段",2,1,one|two\n'
                            'second,第二项,3,0,\n', encoding="utf-8")
            result = read_csv(path)
        self.assertEqual(result["key"], "id")
        self.assertEqual(result["rows"][0], {
            "id": "first", "description": '第一段\n#这一行是正文\n含"引号"与,逗号\n最后一段',
            "count": 2, "enabled": True, "effect_ids": ["one", "two"]})
        self.assertEqual(result["rows"][1], {"id": "second", "description": "第二项", "count": 3, "enabled": False})

    def test_short_existing_records_keep_optional_empty_columns(self):
        with tempfile.TemporaryDirectory(prefix="archive-csv-short-") as directory:
            path = Path(directory) / "sample.csv"
            path.write_text('id,name,draw_enabled,note\n#types:string,string,boolean,string\nfirst,旧物品\n', encoding="utf-8")
            self.assertEqual(read_csv(path)["rows"], [{"id": "first", "name": "旧物品"}])

    def test_real_generated_mechanics_and_tooltip_paragraphs_match_source(self):
        names = ["archive_fragment_definitions", "archive_fragment_levels", "archive_cage_items",
                 "archive_social_rules", "archive_social_items", "archive_daily_limits", "archive_categories",
                 "archive_challenge_definitions", "archive_challenge_stats", "archive_challenge_gear_items",
                 "archive_challenge_gear_quality_rules"]
        source = 'package.path="./scripts/vscripts/?.lua;"..package.path;local json=require("core/json_encoder");'
        for name in names:
            source += f'io.write("{name}\\t",json.encode(require("config/generated/{name}").rows),"\\n");'
        completed = subprocess.run([r"C:\Program Files\lua\bin\lua5.1.exe", "-e", source], cwd=ROOT,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
                                   timeout=15, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        actual = dict(line.split("\t", 1) for line in completed.stdout.decode("utf-8").splitlines())

        def normalized(value):
            if isinstance(value, dict):
                return {key: normalized(entry) for key, entry in value.items() if entry not in (None, "", [], {})}
            if isinstance(value, list):
                return [normalized(entry) for entry in value]
            # Panorama displays the generated Lua's literal '\n' as a newline.
            if isinstance(value, str):
                return value.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\r\n", "\n")
            return value

        for name in names:
            with self.subTest(table=name):
                expected = read_csv(ROOT / "data/csv/存档系统" / (name + ".csv"))["rows"]
                self.assertEqual(normalized(json.loads(actual[name])), normalized(expected))
        definitions = read_csv(ROOT / "data/csv/存档系统/archive_challenge_definitions.csv")["rows"]
        shadow = next(row for row in definitions if row["challenge_id"] == "shadow_3")
        self.assertIn("\n", shadow["description"])


if __name__ == "__main__":
    unittest.main()
