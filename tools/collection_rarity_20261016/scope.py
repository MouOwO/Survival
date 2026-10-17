"""Independent allow-list checks for the reviewed rarity-only bundle delta."""
from __future__ import annotations
import copy
import hashlib
import re

POOLS = ("ex", "friend", "wife", "beast")
QUALITIES = ("N", "R", "SR", "SSR", "UR")
WEIGHTS = dict(zip(QUALITIES, (6000, 2500, 1000, 450, 50)))
TABLES = ("archive_social_items", "archive_social_rules")
SOURCE = "systems/archive_social_rewards.lua"
COMMANDS = ["boss_kill", "building_upgrade", "challenge", "clear", "commerce_catalog",
    "commerce_purchase", "daily_claim", "daily_init", "endless", "endless_reconcile",
    "lottery_draw", "lottery_exchange", "lottery_read", "lottery_snapshot", "promotion",
    "social_draw", "starjoy_reconcile", "title_equip", "vip_claim", "vip_purchase",
    "welfare_reconcile", "work_upgrade"]

def need(value, reason):
    if not value:
        raise ValueError(reason)

def quality(identity):
    match = re.fullmatch(r"(ex|friend|wife|beast)_(\d{2})", identity)
    need(match is not None and 1 <= int(match[2]) <= 40, "unexpected_social_item_identity:" + str(identity))
    index = int(match[2])
    return "N" if index <= 5 else "R" if index <= 15 else "SR" if index <= 27 else "SSR" if index <= 37 else "UR"

def transformed_table(name, table):
    result = copy.deepcopy(table)
    if name == "archive_social_items":
        need(len(result["rows"]) == 160, "social_item_count_not_160")
        for pool in POOLS:
            need({r["item_id"] for r in result["rows"] if r["pool_id"] == pool} ==
                {pool + "_" + str(i).zfill(2) for i in range(1, 41)}, "pool_identities_not_complete:" + pool)
        for row in result["rows"]:
            row["quality"] = quality(row["item_id"])
    elif name == "archive_social_rules":
        need({r["pool_id"] for r in result["rows"]} == set(POOLS), "pool_rules_not_exact")
        for row in result["rows"]:
            for grade, weight in WEIGHTS.items():
                row["quality_weight_" + grade.lower()] = weight
    else:
        raise ValueError("unapproved_table_transform:" + name)
    return result

def check(before, after, base_hash, source_sha256):
    need(set(after) == set(before), "bundle_top_level_shape_changed")
    need(set(after["configs"]) == set(before["configs"]), "bundle_config_set_changed")
    for name, original in before["configs"].items():
        expected = transformed_table(name, original) if name in TABLES else original
        need(after["configs"][name] == expected, "unapproved_configuration_delta:" + name)
    need(set(after["sources"]) == set(before["sources"]), "bundle_source_set_changed")
    for name, original in before["sources"].items():
        if name == SOURCE:
            need(after["sources"][name] != original and
                hashlib.sha256(after["sources"][name].encode("utf-8")).hexdigest() == source_sha256,
                "reviewed_social_source_checksum_mismatch")
        else:
            need(after["sources"][name] == original, "unapproved_settlement_source_delta:" + name)
    allowed_csv = {"data/csv/存档系统/" + name + ".csv" for name in TABLES}
    need(set(after["csv_hashes"]) == set(before["csv_hashes"]), "bundle_csv_set_changed")
    need(all(after["csv_hashes"][name] == digest for name, digest in before["csv_hashes"].items()
        if name not in allowed_csv), "unapproved_csv_checksum_delta")
    expected_aliases = copy.deepcopy(before.get("compatible_config_hashes", {}))
    need(base_hash not in expected_aliases, "baseline_self_alias_unexpected")
    expected_aliases[base_hash] = {"commands": COMMANDS, "upgrade_commands": []}
    need(after.get("compatible_config_hashes", {}) == expected_aliases, "historical_compatibility_changed")
    for name in set(before) - {"configs", "sources", "csv_hashes", "compatible_config_hashes"}:
        need(after[name] == before[name], "bundle_metadata_changed:" + name)
    pending = [r["item_id"] for r in after["configs"]["archive_social_items"]["rows"] if r.get("draw_enabled") is False]
    need(sorted(pending) == ["wife_31", "wife_39"], "pending_draw_availability_changed")
    return {"changed_configs": list(TABLES), "changed_sources": [SOURCE],
        "existing_rewards_caps_currency_costs_preserved": True, "historical_compatibility_preserved": True,
        "item_count": 160, "drawable_count": 158, "pending_ids": sorted(pending), "tier_weights": WEIGHTS}
