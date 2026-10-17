"""Append the reviewed wife collection to the deployed immutable archive bundle.

The working tree contains other tasks: only wife rows and explicitly approved
new zero-default stat definitions may enter this release. No active pointer is
changed by building or testing the candidate.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from archive_backend.bundle import Bundle, read_csv
from social_source_patch import transform as social_transform

BASE = "caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59"
OLD_RELEASE = "/opt/goufayu/releases/20261016-commerce-points-v1"
OLD_MANIFEST = "532123ec2d9cf334be62112e1fb3ffbca75f9e7ffff744020e984a4cd6100df9"
OLD_SERVICE = "3f87fd4b219c20fedac5176c2ea7153f4e639dced48badc571781019755b6993"
OLD_SYNC = "fa656dc096838c8cf8a6df00bee570acb56469d9d561fdc090cf15db6dbe529b"
PAYMENT_RELEASE = "/opt/goufayu/payments/20261015-payment02"
OUTPUT = ROOT / "output/wife_video_20261016/release"
TABLES = {
    "archive_social_items": ("存档系统", "pool_id", "wife"),
    "archive_social_rules": ("存档系统", "pool_id", "wife"),
    "archive_categories": ("存档系统", "category_id", "wife"),
    "archive_challenge_definitions": ("存档系统", "challenge_id", "social_wife"),
    "archive_challenge_stats": ("存档系统", "challenge_id", "social_wife"),
}
COMMANDS = ["boss_kill", "building_upgrade", "challenge", "clear", "commerce_catalog",
    "commerce_purchase", "daily_claim", "daily_init", "endless", "endless_reconcile",
    "lottery_draw", "lottery_exchange", "lottery_read", "lottery_snapshot", "promotion",
    "social_draw", "starjoy_reconcile", "title_equip", "vip_claim", "vip_purchase",
    "welfare_reconcile", "work_upgrade"]


def need(value, reason):
    if not value:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def write(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        need(path.read_bytes() == raw, "candidate_file_already_differs:" + path.name)
    else:
        with path.open("xb") as stream:
            stream.write(raw)


def positive_integer(value, label):
    need(type(value) in (int, float) and math.isfinite(value)
         and value == int(value) and value > 0, label)


def build(expected_count, allowed_stats=()):
    original = Bundle(ROOT / "server/bundles" / BASE)
    base = json.loads((original.directory / "bundle.json").read_bytes())
    data = copy.deepcopy(base)
    inputs, excluded = {}, {}
    for name, (folder, selector, selected) in TABLES.items():
        path = ROOT / "data/csv" / folder / (name + ".csv")
        local = read_csv(path)
        inputs[path.relative_to(ROOT).as_posix()] = sha(path.read_bytes())
        added = [row for row in local["rows"] if row.get(selector) == selected]
        need(added, "wife_rows_missing:" + name)
        key = base["configs"][name]["key"]
        previous = {row[key]: row for row in base["configs"][name]["rows"]}
        need(not any(row.get(selector) == selected for row in previous.values()), "baseline_already_contains_wife")
        need(not any(row[key] in previous for row in added), "wife_id_reuses_existing_identity")
        # Exclude unrelated dirty-tree changes rather than publishing them.
        local_existing = {row[key]: row for row in local["rows"] if row.get(selector) != selected}
        drift = sorted(k for k in previous.keys() | local_existing.keys()
                       if previous.get(k) != local_existing.get(k))
        if drift:
            excluded[name] = drift
        data["configs"][name]["rows"].extend(copy.deepcopy(added))
        # A source hash is meaningful only when it represents these exact rows.
        need(not drift, "affected_table_has_unrelated_changes:" + name + ":" + ",".join(drift))
        data["csv_hashes"][path.relative_to(ROOT).as_posix()] = sha(path.read_bytes().replace(b"\r\n", b"\n"))

    wives = [r for r in data["configs"]["archive_social_items"]["rows"] if r["pool_id"] == "wife"]
    need(len(wives) == expected_count, "wife_count_mismatch")
    need(len({r["item_id"] for r in wives}) == len(wives), "wife_id_duplicate")
    need(len({r["display_name"] for r in wives}) == len(wives), "wife_name_duplicate")
    wife_rules = [r for r in data["configs"]["archive_social_rules"]["rows"] if r["pool_id"] == "wife"]
    wife_categories = [r for r in data["configs"]["archive_categories"]["rows"] if r["category_id"] == "wife"]
    need(len(wife_rules) == len(wife_categories) == 1, "wife_rule_or_category_not_unique")
    rule = wife_rules[0]
    need(rule.get("enabled") is True and rule.get("currency_id") and rule.get("currency_name"), "wife_rule_invalid")
    positive_integer(rule["draw_cost"], "wife_draw_cost_invalid")
    positive_integer(rule["daily_limit"], "wife_daily_limit_invalid")
    need(wife_categories[0].get("enabled") is True and wife_categories[0].get("renderer") == "collection", "wife_category_invalid")
    challenge = [r for r in data["configs"]["archive_challenge_definitions"]["rows"] if r["challenge_id"] == "social_wife"]
    need(len(challenge) == 1 and challenge[0].get("enabled") is True
         and challenge[0].get("reward_kind") == "social_ticket" and challenge[0].get("reward_key") == "wife",
         "wife_challenge_invalid")
    combat = [r for r in data["configs"]["archive_challenge_stats"]["rows"] if r["challenge_id"] == "social_wife"]
    need(len(combat) == 10 and {r["difficulty_id"] for r in combat} == {"N" + str(i) for i in range(1, 11)}
         and all(r.get("enabled") is True for r in combat), "wife_challenge_difficulty_stats_incomplete")
    required, disabled = set(), []
    for row in wives:
        need(row["item_id"].startswith("wife_") and row.get("enabled") is True, "wife_item_invalid")
        positive_integer(row["max_owned"], "wife_max_owned_invalid:" + row["item_id"])
        need(row.get("description"), "wife_description_missing")
        if row.get("draw_enabled") is False:
            need(row["item_id"] in {"wife_31", "wife_39"} and row.get("availability_note")
                 and not row.get("effect_ids") and not row.get("effect_values"), "wife_unavailable_item_invalid:" + row["item_id"])
            disabled.append(row["item_id"])
            continue
        need(row.get("effect_ids") and len(row["effect_ids"]) == len(row.get("effect_values", [])), "wife_effect_shape_invalid:" + row["item_id"])
        for field, amount in zip(row["effect_ids"], row["effect_values"]):
            need(math.isfinite(float(amount)), "wife_effect_nonfinite")
            required.add(field)
    if expected_count == 40:
        need(set(disabled) == {"wife_31", "wife_39"}, "approved_two_unavailable_wives_missing")

    stats_name = "player_gameplay_stats"
    old_stats = {r["field_id"]: r for r in base["configs"][stats_name]["rows"]}
    missing = required - old_stats.keys()
    need(missing == set(allowed_stats), "new_stat_approval_must_exactly_match_missing_effect_fields:" + ",".join(sorted(missing)))
    added_stats = []
    if missing:
        path = ROOT / "data/csv/玩家档案系统/player_gameplay_stats.csv"
        local = read_csv(path)
        by_id = {r["field_id"]: r for r in local["rows"]}
        for field in sorted(missing):
            row = by_id.get(field)
            need(row and row.get("default_value") == 0 and row.get("min_value") == 0
                 and row.get("enabled") is True and row.get("storage_type") in {"integer", "decimal", "percentage"},
                 "new_stat_must_be_enabled_zero_default_nonnegative:" + field)
            added_stats.append(copy.deepcopy(row))
        need(all(by_id.get(k) == v for k, v in old_stats.items()), "existing_stat_definition_changed")
        need(set(by_id) == old_stats.keys() | missing, "unrelated_new_stat_definition")
        inputs[path.relative_to(ROOT).as_posix()] = sha(path.read_bytes())
        data["configs"][stats_name]["rows"].extend(added_stats)
        data["csv_hashes"][path.relative_to(ROOT).as_posix()] = sha(path.read_bytes().replace(b"\r\n", b"\n"))

    data.setdefault("compatible_config_hashes", {})[BASE] = {"commands": COMMANDS, "upgrade_commands": []}
    changed = sorted(k for k in data["configs"] if data["configs"][k] != base["configs"][k])
    need(set(changed) == set(TABLES) | ({stats_name} if missing else set()), "unexpected_configuration_change")
    source_name = "systems/archive_social_rewards.lua"
    source_path = ROOT / "scripts/vscripts" / source_name
    source = source_path.read_text(encoding="utf-8-sig")
    need(source == social_transform(base["sources"][source_name]), "social_source_contains_unreviewed_changes")
    inputs[source_path.relative_to(ROOT).as_posix()] = sha(source_path.read_bytes())
    data["sources"][source_name] = source
    need([name for name in data["sources"] if data["sources"][name] != base["sources"][name]] == [source_name], "settlement_source_changed")
    need(all(data["compatible_config_hashes"].get(k) == v for k, v in base.get("compatible_config_hashes", {}).items()), "historical_compatibility_changed")
    raw = canonical(data)
    digest = sha(raw)
    destination = OUTPUT / digest
    bundle_path = destination / "bundle" / digest
    write(bundle_path / "bundle.json", raw)
    for name, source in data["sources"].items():
        write(bundle_path / name, source.encode("utf-8"))
    if missing:
        write(destination / "addon/data/csv/玩家档案系统/player_gameplay_stats.csv",
              (ROOT / "data/csv/玩家档案系统/player_gameplay_stats.csv").read_bytes().replace(b"\r\n", b"\n"))
    Bundle(bundle_path)
    file_hashes = {p.relative_to(destination).as_posix(): sha(p.read_bytes())
                   for p in sorted(bundle_path.rglob("*")) if p.is_file()}
    if missing:
        relative = "addon/data/csv/玩家档案系统/player_gameplay_stats.csv"
        file_hashes[relative] = sha((destination / relative).read_bytes())
    plan = {"version": 1, "base": BASE, "candidate": digest, "old_release": OLD_RELEASE,
        "old_manifest": OLD_MANIFEST, "old_service": OLD_SERVICE, "old_sync_function": OLD_SYNC,
        "payment_release": PAYMENT_RELEASE, "wife_count": len(wives),
        "wife_draw_count": len(wives) - len(disabled), "unavailable_wife_ids": disabled,
        "wife_ids": [r["item_id"] for r in wives], "added_stat_definitions": added_stats,
        "changed_configs": changed, "changed_sources": [source_name], "input_hashes": inputs,
        "files": file_hashes, "historical_compatibility_preserved": True,
        "existing_social_items_preserved": True, "old_client_operations_upgrade": False,
        "requires_schema_migration": bool(missing), "active_pointers_changed": False}
    write(destination / "release_plan.json", canonical(plan))
    archive = destination / "wife_patch.tar.gz"
    if not archive.exists():
        with tarfile.open(archive, "x:gz") as tar:
            for name in [*file_hashes, "release_plan.json"]:
                info = tar.gettarinfo(str(destination / name), arcname=name)
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = "root"
                info.mode = 0o644
                with (destination / name).open("rb") as stream:
                    tar.addfile(info, stream)
    record = {"status": "BUILT_NOT_DEPLOYED", "candidate": digest, "wife_count": len(wives),
        "wife_draw_count": len(wives) - len(disabled), "unavailable_wife_ids": disabled,
        "directory": str(destination), "tar_sha256": sha(archive.read_bytes()),
        "changed_configs": changed, "added_stats": sorted(missing), "active_pointers_changed": False}
    write(destination / "build_result.json", canonical(record))
    return record


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-count", type=int, required=True)
    parser.add_argument("--allow-new-stat", action="append", default=[])
    args = parser.parse_args()
    print(json.dumps(build(args.expected_count, args.allow_new_stat), ensure_ascii=False))
