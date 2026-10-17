"""Real packaged Lua tests using synthetic profiles only; no database or account API."""
from __future__ import annotations
import copy
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

POOLS = ("ex", "friend", "wife", "beast")
RATES = {"N": .6, "R": .25, "SR": .1, "SSR": .045, "UR": .005}

def need(value, reason):
    if not value:
        raise RuntimeError(reason)

def run(directory, lua):
    directory = Path(directory)
    if os.name == "nt" and len(str(directory.resolve())) > 180:
        short_root = Path(__file__).resolve().parents[2] / "output/rarity_workers"
        short_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="worker-", dir=short_root) as temporary:
            destination = Path(temporary) / "bundle"
            shutil.copytree(directory, destination)
            return run(destination, lua)
    bundle = json.loads((directory / "bundle.json").read_bytes())
    configs = bundle["configs"]
    definitions = {r["field_id"]: r for r in configs["player_gameplay_stats"]["rows"]}
    visible = [r for r in configs["archive_social_items"]["rows"] if r.get("enabled") is True and r["pool_id"] in POOLS]
    drawable = [r for r in visible if r.get("draw_enabled") is not False]
    pending = [r for r in visible if r.get("draw_enabled") is False]
    rules = {r["pool_id"]: r for r in configs["archive_social_rules"]["rows"]}

    def profile():
        return {"account_id": "synthetic-no-database", "save": {"gameplay_stats": {
            key: row.get("default_value", 0) for key, row in definitions.items()}, "content_inventory": {},
            "archive": {"social_counts": {r["item_id"]: r["max_owned"] for r in drawable},
                "social_tickets": {rule["currency_id"]: rule["draw_cost"] * 2 for rule in rules.values()}}}}

    def invoke(saved, command):
        payload = {"configs": configs, "profile": saved, "command": command,
            "has_pass": False, "seed": 1337, "server_time": 2000000000}
        completed = subprocess.run([str(lua), "worker.lua"], cwd=directory,
            input=json.dumps(payload, ensure_ascii=False).encode("utf-8"), capture_output=True,
            check=True, timeout=15, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return json.loads(completed.stdout)

    def script(source, timeout):
        # Windows Lua's argv is ANSI. A UTF-8 file preserves Chinese assertions
        # while stdin remains the exact JSON config payload used by the worker.
        with tempfile.NamedTemporaryFile("wb", suffix=".lua", dir=directory.parent, delete=False) as stream:
            path = Path(stream.name)
            stream.write(source.encode("utf-8"))
        try:
            result = subprocess.run([str(lua), str(path)], cwd=directory,
                input=json.dumps({"configs": configs}, ensure_ascii=False).encode("utf-8"),
                capture_output=True, timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            need(result.returncode == 0, "packaged_lua_probe_failed:" + result.stderr.decode("utf-8", errors="replace"))
            return result
        finally:
            path.unlink()

    wrapper = '''package.path="./?.lua"
local decoder=require("core/json_decoder")
local encoder=require("core/json_encoder")
local input=decoder.decode(io.read("*a"))
for name,config in pairs(input.configs) do
 local module={rows=config.rows,by_id={}}
 for _,row in ipairs(config.rows) do module.by_id[row[config.key]]=row end
 package.loaded["config/generated/"..name]=module
end
'''
    rarity_test = Path(__file__).with_name("rarity_probe.lua").read_text(encoding="utf-8")
    need(rarity_test.count('package.path = "scripts/vscripts/?.lua;" .. package.path') == 1, "rarity_probe_shape_changed")
    rarity_test = rarity_test.replace('package.path = "scripts/vscripts/?.lua;" .. package.path', "", 1)
    tested = script(wrapper + rarity_test, 45)
    need(b"PASS" in tested.stdout, "actual_lua_probability_probe_failed")

    projection_script = wrapper + '''local social=require("systems/archive_social_rewards")
local result={}
for _,pool in ipairs({"ex","friend","wife","beast"}) do
 local save={social_counts={}}
 result[pool]={rows=social.rows(save,pool),info=social.info(save,pool)}
end
io.write(encoder.encode(result))'''
    projected = script(projection_script, 10)
    projection = json.loads(projected.stdout)
    for pool in POOLS:
        rows = projection[pool]["rows"]
        need(len(rows) == 40, "projected_pool_incomplete:" + pool)
        need(math.isclose(sum(r["draw_probability"] for r in rows), 1, abs_tol=1e-10), "projected_probabilities_do_not_sum_to_one")
        need(all(math.isclose(projection[pool]["info"]["rarity_probabilities"][q], p, abs_tol=1e-10)
            for q, p in RATES.items()), "projected_tier_probabilities_incorrect")
        expected = {r["item_id"]: r for r in visible if r["pool_id"] == pool}
        for row in rows:
            item = expected[row["id"]]
            need(row["name"] == item["display_name"] and row["quality"] == item["quality"] and row["target"] == item["max_owned"], "projected_identity_rarity_cap_changed")
            need(all(key in row for key in ("draw_probability", "initial_draw_probability", "quality_draw_probability")), "authority_projection_omits_probability")
            if item.get("draw_enabled") is False:
                need(row["draw_probability"] == 0 and row["initial_draw_probability"] == 0 and row["description"] == item["description"], "pending_projection_changed")

    effects_cases = []
    for item in drawable:
        saved = profile()
        rule = rules[item["pool_id"]]
        currency, cost = rule["currency_id"], rule["draw_cost"]
        saved["save"]["archive"]["social_counts"][item["item_id"]] = 0
        before = copy.deepcopy(saved["save"]["gameplay_stats"])
        command = {"id": "rarity-worker:" + item["item_id"], "kind": "social_draw", "pool_id": item["pool_id"]}
        first = invoke(saved, command)
        need(first.get("ok") is True, "worker_draw_failed:" + item["item_id"])
        need(first["archive"]["social_counts"][item["item_id"]] == 1, "worker_chose_wrong_item")
        need(first["archive"]["social_tickets"][currency] == cost, "worker_currency_charge_changed")
        expected = copy.deepcopy(before)
        for field, raw in zip(item["effect_ids"], item["effect_values"]):
            value = expected[field] + float(raw)
            specification = definitions[field]
            if "max_value" in specification:
                value = min(value, specification["max_value"])
            if "min_value" in specification:
                value = max(value, specification["min_value"])
            expected[field] = value
        actual = first["gameplay_stats"]
        need(set(actual) == set(expected) and all(math.isclose(actual[key], value, rel_tol=1e-12, abs_tol=1e-9)
            for key, value in expected.items()), "worker_effect_delta_changed:" + item["item_id"])
        saved["save"]["archive"], saved["save"]["gameplay_stats"] = first["archive"], actual
        replay = invoke(saved, command)
        need(replay.get("ok") is True and replay.get("duplicate") is True, "worker_replay_not_idempotent")
        need(replay["archive"] == first["archive"] and replay["gameplay_stats"] == actual, "worker_replay_reward_changed")
        effects_cases.append(item["item_id"])

    daily_limits = {}
    for pool in POOLS:
        rule = rules[pool]
        currency, cost = rule["currency_id"], rule["draw_cost"]
        saved = profile()
        first_item = next(item for item in drawable if item["pool_id"] == pool)
        saved["save"]["archive"]["social_counts"][first_item["item_id"]] = 0
        saved["save"]["archive"]["social_tickets"][currency] = 0
        denied = invoke(saved, {"id": "rarity-worker:no-ticket:" + pool, "kind": "social_draw", "pool_id": pool})
        need(denied.get("ok") is False and denied.get("error") == rule["currency_name"] + "不足", "empty_currency_not_denied")
        full = invoke(profile(), {"id": "rarity-worker:full:" + pool, "kind": "social_draw", "pool_id": pool})
        need(full.get("ok") is False and full.get("error") == "本奖池已全部集满", "full_pool_not_denied")
        saved = profile()
        saved["save"]["archive"]["social_tickets"][currency] = 0
        for index in range(rule["daily_limit"] + 2):
            result = invoke(saved, {"id": "rarity-worker:ticket:" + pool + ":" + str(index), "kind": "challenge",
                "challenge_id": "social_" + pool, "difficulty_id": "n1", "kill_sequence": index + 1, "day_key": "20000"})
            need(result.get("ok") is True, "challenge_failed:" + pool)
            saved["save"]["archive"], saved["save"]["gameplay_stats"] = result["archive"], result["gameplay_stats"]
        need(saved["save"]["archive"]["social_tickets"][currency] == rule["daily_limit"], "daily_ticket_limit_changed")
        daily_limits[pool] = rule["daily_limit"]
    return {"status": "PASS", "visible_count": len(visible), "drawable_count": len(drawable),
        "pending_ids": sorted(item["item_id"] for item in pending), "tier_probabilities": RATES,
        "exact_10000_roll_distribution_and_boundaries": True, "all_four_probability_projections_verified": True,
        "individual_effects_verified": effects_cases, "duplicate_replays": len(effects_cases),
        "empty_currency_denied": True, "full_pool_denied": True, "daily_ticket_caps": daily_limits,
        "persistent_writes": 0, "real_account_commands": 0}

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--lua", default="C:/Program Files/lua/bin/lua5.1.exe")
    arguments = parser.parse_args()
    print(json.dumps(run(arguments.directory, arguments.lua), ensure_ascii=False))
