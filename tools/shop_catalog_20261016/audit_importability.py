"""Summarize video evidence against formal reward capabilities; no production writes."""
import csv, hashlib, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"server"))
from archive_backend.commerce_catalog import build_catalog
from payment_backend.csv_catalog import build as build_cash
OUT=ROOT/"design_refs/shop_catalog_20261016/audit"

def rows(path):
    return [r for r in csv.DictReader(path.open(encoding="utf-8-sig",newline="")) if not next(iter(r.values()),"").startswith("#")]

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    source=ROOT/"design_refs/shop_catalog_20261016/video/new_items_reviewed.json"
    videos=json.loads(source.read_text(encoding="utf-8"))["items"]
    maps={
        "P140":{"wood_per_second":1},
        "P145":{"map_level":1,"hero_attack_armor_reduction":25,"hero_basic_attack_growth":25,"hero_attribute_growth":25,"hero_attack_bonus_pct":25,"hero_attribute_bonus_pct":25,"hero_final_damage_bonus_pct":25,"starjoy_points":200},
        "P146":{"hero_final_damage_bonus_pct":40,"hero_attack_armor_reduction":40,"hero_attribute_bonus_pct":40,"hero_attribute_growth":40,"hero_critical_damage_bonus_pct":300,"hero_attack_bonus_pct":35,"starjoy_points":200,"hero_attack_attribute_efficiency_pct":20},
        "P147":{"hero_attack_armor_reduction":25,"hero_basic_attack_growth":25,"hero_attribute_growth":25,"hero_attack_bonus_pct":25,"hero_attribute_bonus_pct":25,"hero_final_damage_bonus_pct":25,"hero_attack_armor_reduction_pct":8,"hero_attack_attribute_efficiency_pct":8},
        "P148":{"gold_per_second":100,"wood_per_second":100,"lumberjack_efficiency":20,"gold_mine_efficiency_pct":30,"hero_attribute_bonus_pct":50,"hero_final_damage_bonus_pct":50,"hero_attributes_per_second":5000,"hero_attack_bonus_pct":50,"hero_attribute_growth":50,"hero_attack_armor_reduction":50,"starjoy_points":200},
        "P149":{"hero_initial_attributes":500000,"hero_damage_attack_growth":80,"hero_critical_damage_bonus_pct":200,"hero_attack_armor_reduction":50,"hero_attribute_growth":50,"hero_attribute_bonus_pct":50,"hero_final_damage_bonus_pct":50,"starjoy_points":200},
        "P150":{"tower_attack_armor_reduction":1.5,"tower_final_damage_bonus_pct":60,"tower_attack_bonus_pct":60,"hero_attribute_bonus_pct":60,"hero_final_damage_bonus_pct":60,"hero_damage_attack_growth":60,"hero_attack_armor_reduction":60,"starjoy_points":200},
        "P151":{"map_level":1,"wall_armor":1000,"wall_armor_per_second":0.15,"hero_final_damage_bonus_pct":35,"hero_attribute_bonus_pct":35,"hero_attribute_growth":35,"hero_attack_armor_reduction":35,"hero_damage_attack_growth":35,"starjoy_points":200},
    }
    blockers={
        "P145":["New hero assets/definition/skills absent; must not substitute an existing hero.","Rose-blade bond, independent EX multipliers and inherited stun/health-removal/ultimate-tower skills need complete mechanics."],
        "P146":["Specified pet skin is not bound to any current pet asset or runtime entitlement."],
        "P147":["Independent EX attribute/final-damage multipliers are not equivalent to existing additive percentage stats.","Existing hero_skill_choice_service reroll bank can be reused, but requires once-per-match ownership grant and exact reset/reconnect handling for five extra rerolls."],
        "P148":["Permanent double-legendary equipment instances and additional two random legendary affixes have no complete current consumer."],
        "P149":["Existing early-final unlock is 60 seconds, so minus 180 seconds cannot silently match original gameplay.","Existing early-final encounter has no referenced extra difficulty coefficient to halve.","Lethal wall damage AoE stun needs new authoritative damage/ownership/event handling; ordinary boss wall stun stat is a different trigger."],
        "P150":["Pet affix slots and treasure reroll count are not current hero/rogue reroll fields.","Video literally says hero attack attributes +60%; no silent flat-60 conversion is valid."],
    }
    stats={r["field_id"] for r in rows(ROOT/"data/csv/玩家档案系统/player_gameplay_stats.csv")}
    items=[]
    for item in videos:
        sid=item["source_id"];mapping=maps.get(sid,{})
        assert set(mapping)<=stats,(sid,set(mapping)-stats)
        reasons=blockers.get(sid,[])
        if not item.get("full_effect_text"):reasons=["Name/SSR/permanent/2388-point price visible; no tooltip/effect description in the recording."]
        status="ready_reuse_formal_stat" if sid=="P140" else "ready_with_source_projection" if sid=="P151" else "blocked_complete_effect"
        items.append({"source_id":sid,"title":item["video_name"],"price":item.get("video_price"),"currency":item.get("currency"),
            "evidence_seconds":item.get("evidence_seconds"),"status":status,"static_stat_candidates":mapping,
            "blockers":reasons,"full_effect_text":item.get("full_effect_text"),
            "runtime_for_extra_effect":"systems/commerce_archive_source_bonus.lua, authenticated save.archive.shadow_counts/cage_counts + formal definitions * 0.2, marker commerce_p151; no save mutation" if sid=="P151" else None})
    table=ROOT/"data/csv/商城兑换系统/commerce_import_status.csv"
    statuses=rows(table);wallet=build_catalog(ROOT);cash=build_cash(ROOT)["catalog"]
    report={"scope":"Read-only compile/audit; video evidence and formal stat IDs are retained separately from shop authority.",
        "new_video_items":items,"old_status_counts":{s:sum(r["status"]==s for r in statuses) for s in sorted({r["status"] for r in statuses})},
        "formal_catalog_snapshot":{"commerce_count":len(wallet["products"]),"commerce_enabled":sum(p["enabled"] for p in wallet["products"]),"cash_count":len(cash["products"]),"cash_enabled":sum(p["enabled"] for p in cash["products"])},
        "payload":{"wallet":["sku","purchase_limit","owned","enabled","disabled_reason","required_vip_level","reward_lines","source_id","original_price"],
            "cash":["sku","item_id","purchase_limit","owned","enabled","disabled_reason","required_vip_level","max_quantity","original_u_coin_price","u_coin_price","amount_fen"],
            "no_max_owned_payload":True,"note":"purchase_limit is the SKU ownership/purchase limit; max_owned belongs to component source items and is not a generic product field. max_quantity is current order capacity, never infer permanent uniqueness from max_quantity=1."},
        "visibility":{"hide_uniques":"purchase_limit strictly 1 and authoritative owned >= 1; preserve repeatable products with owned > 0.",
            "hide_formally_blocked":["already_owned","purchase_limit_reached","component_already_owned","entitlement_already_owned","attribute_limit_reached","ownership_limit_reached","shop_gold_not_open","product_unavailable"],
            "keep_with_reason":["commerce_balance_insufficient","vip_level_required","vip_level_insufficient"],
            "never_authorize":["preview_only","payment_catalog_pending","payment_product_unavailable","payment_price_unavailable","bundle_pending_assets"],
            "VIP_reason":"Display required_vip_level from authenticated row, e.g. 需VIP3. Backend uses vip_level_required for cash and vip_level_insufficient for wallet.",
            "ownership_risk":"Cash historical delivery or free VIP claim can make already_owned true while inventory marker owned is zero; honor server reason rather than local balance/owned guesses."},
        "safe_import":"Append only evidence-reviewed new products/rewards. Do not re-run tools/import_commerce_batch2.py --enable: it rewrites the entire B batch and may reverse current closed-gold/descriptions. Compile both commerce and cash catalogs; preserve original rows/markers/prices/rewards byte-for-byte or equivalent field comparison.",
        "evidence_sha256":{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (source,table)},
        "no_network_or_orders":True}
    (OUT/"importability.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"video_items":len(items),"ready":[i["source_id"] for i in items if i["status"].startswith("ready")],"blocked":[i["source_id"] for i in items if i["blockers"]],"catalog":report["formal_catalog_snapshot"]},ensure_ascii=False,indent=2))

if __name__=="__main__":main()
