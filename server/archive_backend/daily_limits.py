"""Read-only quota projection from durable account acquisition counters."""
from __future__ import annotations

import math
import time


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return int(value) if math.isfinite(value) and value >= 0 and value == int(value) else 0


def snapshot(profile, bundle, now=None):
    current = time.time() if now is None else now
    day = str(math.floor((current + 28800) / 86400))
    save = profile.get("save", {})
    archive = save.get("archive", {})
    bucket = archive.get("daily", {}).get(day, {})
    entitlement = profile.get("entitlements", {}).get("archive_pass", {})
    expiry = entitlement.get("expires_at")
    active = entitlement.get("active") is True and (
        expiry is None or isinstance(expiry, (int, float)) and expiry > current)
    result = {"day_key": day, "rows": [], "by_key": {}}
    for definition in bundle.tables.get("archive_daily_limits", {}).values():
        key = definition["limit_id"]
        earned = number(bucket.get(definition["storage_key"]))
        if key == "faith":
            earned = max(earned, number(archive.get("buildings", {}).get("earned_by_day", {}).get(day)))
        external = save.get("daily_limits", {})
        if key == "fishing" and str(external.get("day_key")) == day:
            earned = max(earned, number(external.get("by_key", {}).get("fishing", {}).get("earned")))
        limit = definition.get("pass_daily_limit") if active else definition.get("daily_limit")
        if limit is None:
            limit = definition["daily_limit"]
        limit = number(limit)
        row = {"key": key, "name": definition["display_name"], "earned": earned,
               "limit": limit, "remaining": max(0, limit-earned), "capped": int(earned >= limit),
               "implemented": int(definition.get("implemented") is True),
               "sort_order": definition.get("sort_order", 0)}
        result["rows"].append(row)
        result["by_key"][key] = row
    result["rows"].sort(key=lambda row: row["sort_order"])
    return result
