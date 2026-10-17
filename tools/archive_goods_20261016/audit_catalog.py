"""Read-only audit of archive goods ownership sources; never creates rewards."""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "design_refs/archive_goods_20261016"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    current = read_json(ROOT / "server/bundles/current.json")["hash"]
    bundle_path = ROOT / "server/bundles" / current / "bundle.json"
    bundle = read_json(bundle_path)
    assert hashlib.sha256(bundle_path.read_bytes()).hexdigest() == current
    products = bundle["configs"]["commerce_catalog"]["rows"]
    starjoy = bundle["configs"]["archive_starjoy_levels"]["rows"]
    vip = bundle["configs"]["archive_vip_rewards"]["rows"]
    cash_path = ROOT / "design_refs/shop_functional_20261016/release_v2/payment_catalog.json"
    cash = read_json(cash_path)["products"]
    enabled = [row for row in products if row["enabled"]]
    excluded = [
        {"sku": row["sku"], "name": row["title"], "reason": "not_enabled_in_current_published_catalog"}
        for row in products if not row["enabled"]
    ]
    goods, seen = [], set()
    for row in sorted(enabled, key=lambda r: (r["sort_order"], r["sku"])):
        if row["sku"] == "video_p001":
            excluded.append({"sku": row["sku"], "name": row["title"], "reason": "consumable_ticket_not_permanent_goods"})
            continue
        marker = row["item_id"]
        if marker in seen:
            excluded.append({"sku": row["sku"], "name": row["title"], "reason": "same_permanent_item_marker_already_included", "marker": marker})
            continue
        seen.add(marker)
        goods.append({"sku": row["sku"], "name": row["title"], "ownership_id": marker,
                      "count_source": f"save.content_inventory.{marker}", "kind": "commerce"})
    legacy = []
    for row in cash:
        if row["sku"].startswith("video_") or not row["enabled"]:
            continue
        if row["purchase_limit"] != 1:
            excluded.append({"sku": row["sku"], "name": row["title"], "reason":
                             "renewable_time_limited_entitlement" if row["sku"] == "archive_pass_monthly"
                             else "consumable_ticket_not_permanent_goods"})
            continue
        marker = row["item_id"]
        assert marker not in seen
        seen.add(marker)
        legacy.append({"sku": row["sku"], "name": row["title"], "ownership_id": marker,
                       "count_source": f"save.content_inventory.{marker}", "kind": "legacy_cash"})
    members = bundle["configs"]["commerce_bundle_members"]["rows"]
    starter = next(row for row in products if row["sku"] == "video_bundle_b003")
    starter_components = starter["grants"]["components"]
    expected = {"commerce_p028", "commerce_p020", "commerce_p018", "commerce_p032"}
    assert {row["item_id"] for row in starter_components} == expected
    assert all(starter["grants"]["items"][marker] == 1 for marker in expected)
    assert all(next(p for p in products if p["item_id"] == marker)["enabled"] for marker in expected)
    new_markers = {"P016": "commerce_p016", "P028": "commerce_p028", "P079": "lottery_monkey_king", "P147": "commerce_p147"}
    for source_id, marker in new_markers.items():
        row = next(row for row in enabled if row["source_id"] == source_id)
        assert row["item_id"] == marker and row["purchase_limit"] == 1
    assert {row["level"] for row in starjoy if row["enabled"]} == set(range(1, 25))
    vip_groups = {name: [row["reward_id"] for row in vip if row["enabled"] and row["group_id"] == name]
                  for name in ("privileges", "packages", "medals")}
    report = {
        "source_bundle_hash": current,
        "read_only": True,
        "writes_player_save": False,
        "needs_server_schema_or_economy_migration": False,
        "counts": {"commerce": len(products), "enabled_commerce": len(enabled),
                   "distinct_permanent_commerce": len(goods), "legacy_permanent_cash": len(legacy),
                   "starjoy": len(starjoy), "vip": len(vip), "total_proposed_goods": len(goods)+len(legacy)+len(starjoy)+len(vip)},
        "products": goods + legacy,
        "excluded_rows": excluded,
        "vip_groups": {name: len(ids) for name, ids in vip_groups.items()},
        "ownership_rules": {
            "product": "positive integer in save.content_inventory[ownership_id]; do not infer from stats, currency balances, price, or VIP level",
            "vip": "save.archive.vip_claimed[reward_id] is exactly true OR positive integer in save.content_inventory[reward_id]",
            "starjoy": "settled save.gameplay_stats.starjoy_reward_level >= tier.level, not current spendable points",
            "starter_bundle": "bundle root ownership and each child ownership remain separate; successful bundle delivery sets all four child markers atomically",
            "ember": "one entry for lottery_ember_of_legacy, retain actual permanent inventory count; 100-pack and 1-pack are purchasing quantities",
            "unknown": "missing/unloaded/malformed profile data is unknown, not a fabricated unlocked state",
        },
        "starter_bundle_child_markers": sorted(expected),
        "new_product_markers": new_markers,
        "not_imported_from_reference_screenshots": ["unimplemented skins", "unpublished items", "starjoy levels 25-28", "example quantities"],
        "receipt_notes": {
            "cash": "payments.orders has durable delivered receipts, but those are not in the ordinary archive UI profile; do not add broad order-query permissions for this read-only permanent inventory page",
            "wallet": "ordinary save.archive.commerce contains balances only; processed transaction IDs are not a durable SKU purchase-count register",
            "consumables": "ticket balances represent remaining usable tickets, never proof of total historical purchases",
        },
        "references": [
            "scripts/vscripts/systems/commerce_settlement.lua",
            "scripts/vscripts/systems/archive_vip_rewards.lua",
            "scripts/vscripts/systems/archive_starjoy_rewards.lua",
            "server/payment_backend/commerce_bundles.py",
            "server/payment_backend/upgrade_commerce_bundles.sql",
            "scripts/vscripts/systems/archive_service.lua",
        ],
    }
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / "catalog_audit.json"
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "report": str(target.relative_to(ROOT)), **report["counts"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
