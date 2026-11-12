"""Validate/append public wire IDs and export canonical JSON for the cipher tool.

Only explicit --update writes the JSON schema. Existing field/symbol/template IDs
are never reordered or removed. The encrypted Lua catalogue is produced by the
separate reviewed cipher builder; this tool never writes its output or keys.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "server/player_web_auth/business_wire_schema.json"
DAILY_PATH = ROOT / "data/csv/存档系统/archive_daily_limits.csv"
STATS_PATH = ROOT / "data/csv/玩家档案系统/player_gameplay_stats.csv"
INITIAL_FIELDS = """schema_version account_id revision entitlements achievements save public
profile account_profile match_session_id mode game_mode progression daily_limits
rows by_key key name earned limit remaining capped implemented sort_order active
expires_at progress unlocked ok terminal done error response config_hash id kind
request_id session_id final authenticated loaded highest_difficulty clear_counts
standard_clear_counts mode_clear_counts gameplay_stats archive content_inventory
permanent_effects match_boss_effects stackable_projection_applied quantity count
level vip_level vip_badge equipped owned owned_count balance amount currency
day_key updated_at created_at operation_id reward_id rewards items status value
enabled source_id display_name message reason type inventory tickets draws
total earned_today daily_cap period day can_claim claimed can_upgrade has_pass
""".split()
_SYMBOL = re.compile(r"[a-z][a-z0-9_:.+-]{2,127}\Z")
_FIELD = re.compile(r"[a-z_][a-z0-9_]{0,95}\Z")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False,
                      sort_keys=True, separators=(",", ":")).encode("utf-8")


def public_symbols():
    values = {"pure", "standard", "rich", "cold", "scourge", "ruins", "celestial"}
    # These are public, account-free catalogue identifiers. No code, redemption
    # secret, account save, .env, database or remote service is read.
    directory = ROOT / "data/csv/存档系统"
    for path in sorted(directory.glob("*.csv")):
        with path.open(encoding="utf-8-sig", newline="") as stream:
            rows = csv.reader(stream)
            next(rows, None)
            for row in rows:
                if row and _SYMBOL.fullmatch(row[0]):
                    values.add(row[0])
    return sorted(values)


def initial_field_candidates():
    counts = Counter()
    paths = sorted((ROOT / "server/archive_backend").glob("*.py"))
    paths.append(ROOT / "server/fishing_api_overrides/match_profiles.py")
    for path in paths:
        tree = ast.parse(path.read_text(encoding="utf-8-sig"))
        for node in ast.walk(tree):
            values = []
            if isinstance(node, ast.Dict):
                values = node.keys
            elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "get":
                values = node.args[:1]
            elif isinstance(node, ast.Subscript):
                values = [node.slice]
            for value in values:
                if isinstance(value, ast.Constant) and type(value.value) is str and _FIELD.fullmatch(value.value):
                    counts[value.value] += 1
    # This selection is used only at first creation. Later executions preserve
    # the existing registry and append explicitly required new public fields.
    result = list(INITIAL_FIELDS)
    for key, _ in sorted(counts.items(), key=lambda pair: (-pair[1], pair[0])):
        if key not in result:
            result.append(key)
        if len(result) >= 300:
            break
    return result


def daily_templates():
    values = []
    with DAILY_PATH.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            if row["limit_id"].startswith("#"):
                continue
            limit = int(float(row["daily_limit"]))
            defaults = {"key": row["limit_id"], "name": row["display_name"],
                        "earned": 0, "limit": limit, "remaining": limit,
                        "capped": 0, "implemented": int(row["implemented"] == "1"),
                        "sort_order": int(float(row["sort_order"]))}
            suffix = hashlib.sha256(canonical(defaults)).hexdigest()[:12]
            values.append({"name": "daily." + row["limit_id"] + "." + suffix,
                           "defaults": defaults})
            # The pass changes only the server-selected allowance. Keep both
            # complete defaults locally; earned/remaining differences remain
            # explicit. Immutable normal-template IDs are never rewritten.
            pass_limit = int(float(row.get("pass_daily_limit") or row["daily_limit"]))
            if pass_limit != limit:
                pass_defaults = dict(defaults, limit=pass_limit, remaining=pass_limit)
                pass_suffix = hashlib.sha256(canonical(pass_defaults)).hexdigest()[:12]
                values.append({"name": "daily.pass." + row["limit_id"] + "." + pass_suffix,
                               "defaults": pass_defaults})
    values.extend([
        {"name": "flag.active.false", "defaults": {"active": False}},
        {"name": "entitlement.inactive.permanent", "defaults": {"active": False, "expires_at": None}},
        {"name": "achievement.zero.locked", "defaults": {"progress": 0, "unlocked": False}},
    ])
    return values


def gameplay_templates():
    """Public numeric defaults; the backend still supplies every changed value.

    Pure-mode projections normalize integral numbers while the durable account
    retains decimal/percentage JSON numbers. Two complete shapes preserve both
    representations exactly; no player/account fixture is used as a source.
    """
    integral, storage = {}, {}
    with STATS_PATH.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            if row["field_id"].startswith("#") or row["enabled"] != "1":
                continue
            number = float(row["default_value"])
            value = int(number) if number.is_integer() else number
            integral[row["field_id"]] = value
            storage[row["field_id"]] = int(number) if row["storage_type"] == "integer" else number
    values = []
    for name, defaults in (("integral", integral), ("storage", storage)):
        suffix = hashlib.sha256(canonical(defaults)).hexdigest()[:12]
        values.append({"name": "gameplay." + name + "." + suffix, "defaults": defaults})
    return values


def updated_schema(existing=None):
    schema = existing or {"version": 1, "fields": initial_field_candidates(), "symbols": [], "templates": []}
    # Copy lists to preserve the caller's input and immutable ID prefix.
    schema = dict(schema, fields=list(schema["fields"]), symbols=list(schema["symbols"]),
                  templates=list(schema["templates"]))
    gameplay = gameplay_templates()
    for field in [*INITIAL_FIELDS, *gameplay[0]["defaults"]]:
        if field not in schema["fields"]:
            schema["fields"].append(field)
    for symbol in public_symbols():
        if symbol not in schema["symbols"]:
            schema["symbols"].append(symbol)
    names = {template["name"]: template for template in schema["templates"]}
    for template in [*daily_templates(), *gameplay]:
        if template["name"] in names:
            if names[template["name"]] != template:
                raise ValueError("business_wire_existing_template_changed")
        else:
            schema["templates"].append(template)
    return schema


def verify_committed_prefix(schema):
    relative = SCHEMA_PATH.relative_to(ROOT).as_posix()
    listing = subprocess.run(["git", "-C", str(ROOT), "ls-tree", "--name-only", "HEAD", "--", relative],
                             capture_output=True, check=True).stdout.decode("utf-8").strip()
    if not listing:
        return {"committed_baseline_present": False,
                "committed_prefix_verified": False,
                "baseline_status": "FIRST_VERSION_NO_COMMITTED_SCHEMA"}
    raw = subprocess.run(["git", "-C", str(ROOT), "show", "HEAD:" + relative],
                         capture_output=True, check=True).stdout
    baseline = json.loads(raw)
    if baseline.get("version") != schema.get("version"):
        raise ValueError("business_wire_committed_version_changed")
    for name in ("fields", "symbols", "templates"):
        previous = baseline[name]
        if (type(previous) is not list or len(schema[name]) < len(previous)
                or canonical(schema[name][:len(previous)]) != canonical(previous)):
            raise ValueError("business_wire_committed_id_prefix_changed:" + name)
    return {"committed_baseline_present": True, "committed_prefix_verified": True,
            "committed_baseline_sha256": hashlib.sha256(canonical(baseline)).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check source/config parity without writing")
    parser.add_argument("--update", action="store_true", help="Create registry or append new public IDs")
    parser.add_argument("--canonical", action="store_true", help="Write canonical schema JSON to stdout")
    args = parser.parse_args()
    if args.check and args.update:
        parser.error("--check and --update are mutually exclusive")
    existing = json.loads(SCHEMA_PATH.read_text(encoding="utf-8-sig")) if SCHEMA_PATH.exists() else None
    expected = updated_schema(existing)
    baseline = verify_committed_prefix(expected)
    if args.update:
        SCHEMA_PATH.write_text(json.dumps(expected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    elif existing != expected:
        raise ValueError("business_wire_registry_update_required_run_explicit_update")
    # Only import after a deliberate first creation; import validates the exact
    # schema limits and static template indexes used by the serving process.
    sys.path.insert(0, str(ROOT / "server"))
    from player_web_auth import business_wire
    business_wire.validate_schema(expected)
    raw = canonical(expected)
    if args.canonical:
        sys.stdout.buffer.write(raw)
    else:
        print(json.dumps({"ok": True, "schema_hash": hashlib.sha256(raw).hexdigest(),
                          "fields": len(expected["fields"]), "symbols": len(expected["symbols"]),
                          "templates": len(expected["templates"]),
                          "existing_ids_preserved": True, "lua_written": False, **baseline}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
