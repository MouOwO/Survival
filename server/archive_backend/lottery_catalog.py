"""Public lottery presentation, independent of account state and settlement hashes."""
from __future__ import annotations

import hashlib
import json
import subprocess


ITEM_FIELDS = (
    "id", "name", "description", "quality", "item_type", "duration_type",
    "duration_text", "icon", "icon_type", "effect_status", "duplicate_points",
    "exchange_points", "exchange_enabled", "max_owned", "converted_currency",
)
POOL_FIELDS = (
    "id", "revision", "updated_at", "display_name", "description", "pool_group",
    "ticket_content_id", "ticket_name", "single_cost", "ten_cost",
    "unlock_pool_id", "unlock_pool_name", "unlock_required",
)
NOTICE_FIELDS = (
    "pool_id", "updated_at", "title", "description", "notice_title", "notice_text",
    "single_draw_probabilities", "enabled", "revision", "content", "summary", "effective_date",
)
PITY_FIELDS = ("quality", "trigger_mode", "batch_size", "label")
SNAPSHOT_FIELDS = ("version", "selected_pool_id", "ticket_content_id", "ticket_name", "single_cost", "ten_cost")


def fields(value, names):
    return {key: value[key] for key in names if key in value}


def public_pool(value):
    result = fields(value, POOL_FIELDS)
    result["pity"] = [fields(row, PITY_FIELDS) for row in value.get("pity", [])]
    result["update_notice"] = fields(value.get("update_notice", {}), NOTICE_FIELDS)
    return result


def public_catalog(snapshots):
    result = {"schema": 1, "snapshots": []}
    for source in snapshots:
        snapshot = fields(source, SNAPSHOT_FIELDS)
        snapshot["selected_pool"] = public_pool(source["selected_pool"])
        snapshot["pools"] = [public_pool(pool) for pool in source.get("pools", [])]
        snapshot["items"] = [fields(item, ITEM_FIELDS) for item in source.get("items", [])]
        snapshot["pity"] = [fields(row, PITY_FIELDS) for row in source.get("pity", [])]
        result["snapshots"].append(snapshot)
    return result


def catalog_document(bundle, lua):
    """Run the immutable bundle's existing, read-only snapshot projection."""
    empty_profile = {"account_id": "0", "save": {"archive": {}, "content_inventory": {}, "gameplay_stats": {}}}
    payload = {"configs": bundle.configs, "profile": empty_profile,
               "command": {"id": "lottery_catalog", "kind": "lottery_snapshot"},
               "has_pass": False, "seed": 1, "server_time": 0}
    completed = subprocess.run([lua, "worker.lua"], cwd=bundle.directory,
        input=json.dumps(payload, ensure_ascii=True, allow_nan=False).encode("ascii"),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    result = json.loads(completed.stdout)
    if not result.get("ok") or not isinstance(result.get("snapshots"), list):
        raise ValueError("lottery_catalog_projection_failed")
    catalog = public_catalog(result["snapshots"])
    document = json.dumps(catalog, ensure_ascii=True, sort_keys=True, separators=(",", ":"), allow_nan=False)
    return {"catalog": catalog, "catalog_json": document,
            "catalog_md5": hashlib.md5(document.encode("ascii"), usedforsecurity=False).hexdigest(),
            "config_hash": bundle.hash}


def build_catalog(service):
    return catalog_document(service.bundle, service.lua)
