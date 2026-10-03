"""Validate a screenshot-defined lottery pool against a real immutable settlement bundle."""
import argparse
import csv
from collections import Counter
import json
from pathlib import Path
import subprocess


def verify(bundle, lua, reference):
    data = json.loads((bundle / "bundle.json").read_bytes())
    configs = data["configs"]
    definition = json.loads(reference.read_text(encoding="utf-8"))
    pool = definition["pool_id"]
    wanted = {r["item_id"]: r for r in definition["items"]}
    expected_counts = {"map": {"n": 10, "r": 5, "sr": 5, "ssr": 10},
                       "cultivation": {"r": 5, "sr": 5, "ssr": 9, "ur": 7},
                       "dragon_knight": {"r": 5, "sr": 5, "ssr": 10, "ur": 7},
                       "summer": {"r": 5, "sr": 5, "ssr": 8, "ur": 6}}[pool]
    assert Counter(r["quality"] for r in wanted.values()) == expected_counts
    pending = set(definition.get("pending_items", {}))
    if definition.get("configuration_status") == "draft_missing_effects":
        assert pool == "summer" and len(pending) == 10
        assert definition["probability_status"] == "pending_user_values"
        assert definition["ticket_content_id"] == "special_lottery_ticket" and definition["ten_guarantee"] == "ur"
        current = {r["item_id"]: r for r in configs["lottery_item_definitions"]["rows"]}
        assert set(wanted) - set(current) == pending
        for key in set(wanted) - pending:
            assert current[key]["display_name"] == wanted[key]["display_name"]
            assert current[key]["quality"] == wanted[key]["quality"]
        assert {key for key, item in wanted.items() if item["quality"] == "ur"} <= pending
        def draft_rows(name):
            lines = (reference.parent / "drafts" / name).read_text(encoding="utf-8").splitlines()
            return list(csv.DictReader(line for line in lines if not line.startswith("#")))
        members = draft_rows("summer_pool_items.csv")
        assert len(members) == 24 and {r["item_id"] for r in members} == set(wanted)
        assert all(r["enabled"] == "0" and r["pool_id"] == pool for r in members)
        placeholders = draft_rows("summer_new_item_definitions.csv")
        assert len(placeholders) == 10 and {r["item_id"] for r in placeholders} == pending
        for row in placeholders:
            assert row["enabled"] == row["exchange_enabled"] == "0"
            assert row["effect_status"] == "missing_source"
            assert not any(row[field] for field in ("effect_ids", "effect_values", "duplicate_points", "exchange_points", "icon"))
            assert row["quality"] == wanted[row["item_id"]]["quality"]
            assert row["display_name"] == wanted[row["item_id"]]["display_name"]
        print("POOL_DRAFT_PASS: summer, 24 registered, 14 mapped existing, 10 missing definitions; all draft rows disabled; no draw validation claimed")
        return
    members = [r for r in configs["lottery_pool_items"]["rows"] if r["pool_id"] == pool]
    assert len(members) == len(wanted) and {r["item_id"] for r in members} == set(wanted)
    available = {r["item_id"] for r in members if r.get("enabled", True)}
    assert available == set(wanted) - pending
    items = {r["item_id"]: r for r in configs["lottery_item_definitions"]["rows"]}
    for key, row in wanted.items():
        assert items[key]["quality"] == row["quality"]
        assert items[key]["display_name"] == row["display_name"]
    for key in pending:
        assert not items[key]["enabled"] and not items[key]["exchange_enabled"]
        assert items[key]["effect_status"] == "missing_source"
    guarantee = "ur" if pool == "dragon_knight" else "ssr"
    weights = {r["quality"]: r["weight"] for r in configs["lottery_quality_weights"]["rows"] if r["pool_id"] == pool and r.get("enabled", True)}
    assert sum(weights.values()) == 10000
    if definition.get("single_draw_probabilities"):
        probabilities = definition["single_draw_probabilities"]
        assert sum(probabilities.values()) == 100
        assert {q: value / 100 for q, value in weights.items() if value > 0} == probabilities
        notice = next(row for row in configs["lottery_pool_updates"]["rows"] if row["pool_id"] == pool)
        for quality, value in probabilities.items():
            assert f"{quality.upper()}：{value:g}%" in notice["single_draw_probabilities"]
    assert {q for q, weight in weights.items() if weight > 0} == set(expected_counts)
    profile = {"account_id": "isolated-map-reference", "revision": 1, "save": {
        "gameplay_stats": {r["field_id"]: r["default_value"] for r in configs["player_gameplay_stats"]["rows"]},
        "archive": {"lottery_state": {"pools": {"map": {"draws": 100}}}}, "content_inventory": {"lottery_ticket": 100, "special_lottery_ticket": 100}}}
    for seed in [0, 1, 7, 42, 100, 65535, 123456, 987654321]:
        for count in [1, 10]:
            payload = {"profile": profile, "configs": configs, "seed": seed, "has_pass": False,
                "command": {"kind": "lottery_draw", "pool_id": pool, "count": count, "id": "map-ref", "request_id": "map-ref"}}
            result = subprocess.run([lua, "worker.lua"], cwd=bundle, input=json.dumps(payload), capture_output=True, text=True, check=True)
            output = json.loads(result.stdout)
            assert output["ok"], output
            response = output["response"]
            assert len(response["results"]) == count
            for reward in response["results"]:
                assert reward["id"] in available, reward
                assert reward["quality"] == wanted[reward["id"]]["quality"]
            if count == 10:
                assert response["guarantee_quality"] == guarantee and response["guarantee_satisfied"]
                assert any(r["quality"] in (("ur",) if guarantee == "ur" else ("ssr", "ur")) for r in response["results"])
            else:
                assert response["guarantee_quality"] == ""
    print(f"POOL_REFERENCE_PASS: {pool}, {len(wanted)} registered/{len(available)} active, screenshot names/qualities, pending excluded, 8 seeds single/ten, {guarantee.upper()} batch guarantee")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--lua", required=True)
    parser.add_argument("--reference", type=Path, default=Path(__file__).resolve().parents[1] / "data/lottery/map_pool_reference_20260929.json")
    args = parser.parse_args()
    verify(args.bundle.resolve(), args.lua, args.reference)
