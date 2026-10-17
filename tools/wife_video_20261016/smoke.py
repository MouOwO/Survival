"""Pure packaged-worker tests; never loads accounts or calls a live command API."""
from __future__ import annotations

import copy
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def run(directory, lua):
    directory = Path(directory)
    # Lua 5.1's Windows CRT cannot reliably open a module when a long release
    # directory plus the require path crosses MAX_PATH. Test an exact short
    # temporary copy on D:, without changing the immutable packaged candidate.
    if os.name == "nt" and len(str(directory.resolve())) > 180:
        short_root = Path(__file__).resolve().parents[2] / "output/wife_workers"
        short_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="worker-", dir=short_root) as temporary:
            destination = Path(temporary) / "bundle"
            shutil.copytree(directory, destination)
            return run(destination, lua)
    bundle = json.loads((directory / "bundle.json").read_bytes())
    configs = bundle["configs"]
    definitions = {r["field_id"]: r for r in configs["player_gameplay_stats"]["rows"]}
    display_items = [r for r in configs["archive_social_items"]["rows"] if r["pool_id"] == "wife" and r.get("enabled") is True]
    items = [r for r in display_items if r.get("draw_enabled") is not False]
    unavailable = [r for r in display_items if r.get("draw_enabled") is False]
    rule = next(r for r in configs["archive_social_rules"]["rows"] if r["pool_id"] == "wife")
    currency, cost = rule["currency_id"], rule["draw_cost"]

    def profile():
        return {"account_id": "synthetic-no-database", "save": {"gameplay_stats": {
            k: r.get("default_value", 0) for k, r in definitions.items()}, "content_inventory": {},
            "archive": {"social_counts": {r["item_id"]: r["max_owned"] for r in items},
                        "social_tickets": {currency: cost * 2}}}}

    def invoke(saved, command):
        payload = {"configs": configs, "profile": saved, "command": command,
                   "has_pass": False, "seed": 1337, "server_time": 2000000000}
        completed = subprocess.run([str(lua), "worker.lua"], cwd=directory,
            input=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            capture_output=True, check=True, timeout=10,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return json.loads(completed.stdout)

    def probe(saved, command=None):
        script = '''local decoder=require("core/json_decoder")
local encoder=require("core/json_encoder")
local input=decoder.decode(io.read("*a"))
for name,config in pairs(input.configs) do
 local module={rows=config.rows,by_id={}}
 for _,row in ipairs(config.rows) do module.by_id[row[config.key]]=row end
 package.loaded["config/generated/"..name]=module
end
local social=require("systems/archive_social_rewards")
local result={rows=social.rows(input.save,"wife"),info=social.info(input.save,"wife")}
if input.command then
 result.ok,result.error=social.apply(input.command,input.save,input.stats,function() error("full pool must not apply effects") end)
 result.save=input.save
end
io.write(encoder.encode(result))'''
        data = {"configs": configs, "save": saved["save"]["archive"], "stats": saved["save"]["gameplay_stats"]}
        if command:
            data["command"] = command
        completed = subprocess.run([str(lua), "-e", script], cwd=directory,
            input=json.dumps(data, ensure_ascii=False).encode("utf-8"), capture_output=True,
            check=True, timeout=10, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return json.loads(completed.stdout)

    projection = probe(profile())
    need([r["id"] for r in projection["rows"]] == sorted(r["item_id"] for r in display_items), "wife_rows_not_complete_and_sorted")
    projected = {r["id"]: r for r in projection["rows"]}
    for item in display_items:
        row = projected[item["item_id"]]
        enabled = item.get("draw_enabled") is not False
        need(row["draw_enabled"] == (1 if enabled else 0), "wife_rows_wrong_draw_availability")
        if not enabled:
            need(row["description"] == item["description"] and row["availability_note"] == item["availability_note"], "wife_pending_original_tooltip_or_note_lost")
            need("按数量叠加" not in row["description"] and "（每件）" not in row["description"], "wife_pending_description_promises_effects")
        else:
            need(row["description"].startswith(item["description"] + "（每件）"), "wife_active_description_changed")
    need(projection["info"]["remaining"] == 0, "pending_wives_counted_as_drawable_remaining")

    cases = []
    for item in items:
        saved = profile()
        saved["save"]["archive"]["social_counts"][item["item_id"]] = 0
        before = copy.deepcopy(saved["save"]["gameplay_stats"])
        command = {"id": "wife-worker:" + item["item_id"], "kind": "social_draw", "pool_id": "wife"}
        first = invoke(saved, command)
        need(first.get("ok") is True, "wife_worker_draw_failed:" + item["item_id"])
        need(first["archive"]["social_counts"][item["item_id"]] == 1, "wife_worker_wrong_item")
        need(first["archive"]["social_tickets"][currency] == cost, "wife_worker_wrong_currency_charge")
        expected = copy.deepcopy(before)
        for field, raw in zip(item["effect_ids"], item["effect_values"]):
            value = expected[field] + float(raw)
            spec = definitions[field]
            if "max_value" in spec:
                value = min(value, spec["max_value"])
            if "min_value" in spec:
                value = max(value, spec["min_value"])
            expected[field] = value
        actual = first["gameplay_stats"]
        need(set(actual) == set(expected) and all(math.isclose(actual[k], v, rel_tol=1e-12, abs_tol=1e-9)
             for k, v in expected.items()), "wife_worker_stat_delta_wrong:" + item["item_id"])
        saved["save"]["archive"] = first["archive"]
        saved["save"]["gameplay_stats"] = first["gameplay_stats"]
        replay = invoke(saved, command)
        need(replay.get("ok") is True and replay.get("duplicate") is True, "wife_worker_replay_not_deduplicated")
        need(replay["archive"] == first["archive"] and replay["gameplay_stats"] == actual, "wife_worker_replay_changed_reward")
        cases.append(item["item_id"])

    saved = profile()
    saved["save"]["archive"]["social_counts"][items[0]["item_id"]] = 0
    saved["save"]["archive"]["social_tickets"][currency] = 0
    denied = invoke(saved, {"id": "wife-worker:no-ticket", "kind": "social_draw", "pool_id": "wife"})
    need(denied.get("ok") is False and denied.get("error") == rule["currency_name"] + "不足", "wife_worker_empty_currency_not_denied")
    full = invoke(profile(), {"id": "wife-worker:full-pool", "kind": "social_draw", "pool_id": "wife"})
    need(full.get("ok") is False and full.get("error") == "本奖池已全部集满", "wife_worker_full_pool_not_denied")
    full_probe = probe(profile(), {"id": "wife-worker:full-direct", "kind": "social_draw", "pool_id": "wife"})
    need(full_probe.get("ok") is False and full_probe.get("error") == "本奖池已全部集满", "wife_direct_full_pool_not_denied")
    need(full_probe["save"]["social_tickets"][currency] == cost * 2, "wife_pending_consumed_currency_after_active_pool_full")
    need(all(full_probe["save"]["social_counts"].get(r["item_id"], 0) == 0 for r in unavailable), "wife_pending_item_was_drawn")
    # Trusted challenge reward remains rate limited by the existing daily rule.
    saved = profile()
    saved["save"]["archive"]["social_tickets"][currency] = 0
    daily = rule["daily_limit"]
    for index in range(daily + 2):
        result = invoke(saved, {"id": "wife-worker:ticket:" + str(index), "kind": "challenge",
            "challenge_id": "social_wife", "difficulty_id": "n1", "kill_sequence": index + 1,
            "day_key": "20000"})
        need(result.get("ok") is True, "wife_worker_challenge_failed")
        saved["save"]["archive"], saved["save"]["gameplay_stats"] = result["archive"], result["gameplay_stats"]
    need(saved["save"]["archive"]["social_tickets"][currency] == daily, "wife_worker_daily_ticket_limit_incorrect")
    return {"status": "PASS", "wife_count": len(items), "display_count": len(display_items),
        "unavailable_ids": sorted(r["item_id"] for r in unavailable), "original_tooltips_and_order_verified": True,
        "full_active_pool_does_not_charge_for_pending": True, "individual_effects_verified": cases,
        "duplicate_replays": len(cases), "empty_currency_denied": True, "full_pool_denied": True,
        "daily_ticket_cap_verified": daily, "persistent_writes": 0, "real_account_commands": 0}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--lua", default="C:/Program Files/lua/bin/lua5.1.exe")
    args = parser.parse_args()
    print(json.dumps(run(args.directory, args.lua), ensure_ascii=False))
