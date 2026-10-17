"""Rarity migration/import preservation tests; no network or profile writes."""
from __future__ import annotations

import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from collection_rarity_config import ensure_collection_rarity, quality_for_index, QUALITY_WEIGHTS

CSV = ROOT / "data/csv/存档系统"
BASELINE = "eb49cbe03cd338757949a3d7449457005d9e79ddd0f51b9ec1d8becc9e66a261"


def read(path):
    lines = [line for line in path.read_text("utf-8-sig").splitlines() if not line.startswith("#types:")]
    return list(csv.DictReader(lines))


class CollectionRarityConfigTests(unittest.TestCase):
    def test_four_pools_have_reviewed_five_tiers_and_weights(self):
        items = read(CSV / "archive_social_items.csv")
        rules = read(CSV / "archive_social_rules.csv")
        self.assertEqual(len(items), 160)
        for pool in ("ex", "friend", "wife", "beast"):
            rows = [r for r in items if r["pool_id"] == pool]
            self.assertEqual(len(rows), 40)
            for row in rows:
                self.assertEqual(row["quality"], quality_for_index(int(row["item_id"].rsplit("_", 1)[1])))
            rule = next(r for r in rules if r["pool_id"] == pool)
            self.assertEqual({q: int(rule["quality_weight_" + q.lower()]) for q in QUALITY_WEIGHTS}, QUALITY_WEIGHTS)

    def test_reviewed_changes_preserve_every_existing_reward_and_rule_field(self):
        # This immutable baseline is the package read by the current client at
        # task start. Do not follow a pointer which deployment may now advance.
        base = json.loads((ROOT / "server/bundles" / BASELINE / "bundle.json").read_text("utf-8"))
        sys.path.insert(0, str(ROOT / "server"))
        from archive_backend.bundle import read_csv
        now = read_csv(CSV / "archive_social_items.csv")["rows"]
        old = base["configs"]["archive_social_items"]["rows"]
        self.assertEqual(len(now), len(old))
        for a, b in zip(now, old):
            self.assertEqual({k:v for k,v in a.items() if k != "quality"},
                             {k:v for k,v in b.items() if k != "quality"})
        now = read_csv(CSV / "archive_social_rules.csv")["rows"]
        old = base["configs"]["archive_social_rules"]["rows"]
        self.assertEqual(len(now), len(old))
        for a, b in zip(now, old):
            self.assertEqual({k:v for k,v in a.items() if not k.startswith("quality_weight_")}, b)

    def test_import_upgrades_legacy_quality_and_is_byte_idempotent(self):
        with tempfile.TemporaryDirectory(prefix="collection-rarity-") as temporary:
            directory = Path(temporary)
            original = 'item_id,pool_id,display_name,max_owned,quality,description,effect_ids,effect_values,enabled\r\n#types:string,string,string,number,string,string,list,list,boolean\r\n"friend_28","friend","测试角色","7","N","加成,保持原值","tower_attack_flat","1000","1"\r\n'
            rules = 'pool_id,display_name,currency_id,currency_name,daily_limit,draw_cost,unlock_count,enabled\n#types:string,string,string,string,number,number,number,boolean\nfriend,原名称,yitie,义帖,10,1,100,1\n'
            (directory / "archive_social_items.csv").write_bytes(original.encode())
            (directory / "archive_social_rules.csv").write_bytes(rules.encode())
            before = read(directory / "archive_social_items.csv")[0]
            ensure_collection_rarity(directory)
            after = read(directory / "archive_social_items.csv")[0]
            self.assertEqual(after["quality"], "SSR")
            self.assertEqual({k:v for k,v in after.items() if k != "quality"},
                             {k:v for k,v in before.items() if k != "quality"})
            self.assertIn(b'\r\n', (directory / "archive_social_items.csv").read_bytes())
            first = {path.name: path.read_bytes() for path in directory.iterdir()}
            ensure_collection_rarity(directory)
            self.assertEqual({path.name: path.read_bytes() for path in directory.iterdir()}, first)


if __name__ == "__main__":
    unittest.main()
