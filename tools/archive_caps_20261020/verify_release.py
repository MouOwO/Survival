"""Offline validation of a pinned overlay using the actual Lua worker; no DB/SSH."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import time
from types import SimpleNamespace

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "tmp/archive_caps_20261020"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def validate(stage, lua):
    stage = stage.resolve()
    plan = json.loads((stage / "plan.json").read_bytes())
    digest = plan["candidate"]["bundle_hash"]
    runtime = ROOT / "tmp" / ("acv20_" + digest[:10])
    baseline = PACKAGE / "online_baseline"
    baseline_hashes = json.loads((stage / "baseline_hashes.json").read_bytes())
    for relative, expected in baseline_hashes.items():
        source = baseline / relative
        assert sha(source.read_bytes()) == expected
        target = runtime / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    for relative, expected in plan["candidate"]["overlay"].items():
        source = stage / "overlay" / relative
        assert sha(source.read_bytes()) == expected, relative
        target = runtime / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    sys.path.insert(0, str(runtime / "backend"))
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    from archive_backend.unique_points import legacy_lottery_error
    from archive_backend.config_compatibility import accepts, upgrades
    from fishing_api.postgres import DatabaseError, Parameter, PostgresRpcClient
    bundle = Bundle(runtime / "addon/server/bundles" / digest)
    parent = plan["expected"]["bundle_hash"]
    cases = []
    # Exercise the real transport converter without constructing a connector.
    converter = object.__new__(PostgresRpcClient)
    parameter = Parameter("p_mode", "text", "match_mode")
    for mode in ("pure", "standard", "rich", "cold", "scourge"):
        assert converter._convert(parameter, mode) == mode
    for mode in ("fishing", "unknown"):
        try:
            converter._convert(parameter, mode)
        except DatabaseError as error:
            assert str(error) == "database_rpc_parameters_invalid", str(error)
        else:
            raise AssertionError("unapproved_mode_accepted:" + mode)
    cases.append({"case": "real_postgres_converter_five_modes_accept_fishing_unknown_reject", "ok": True})
    class RPC:
        def __init__(self):
            self.calls = []
        def rpc(self, name, payload):
            self.calls.append((name, copy.deepcopy(payload)))
            assert name in {"archive_commit", "archive_commit_lottery"}, name
            return {"ok": True, "committed": name}
    rpc = RPC()
    application = SimpleNamespace(account_id_pepper="offline-fixture-only", rpc_client=rpc)
    service = ArchiveService(application, bundle, str(lua.resolve()))
    stats = bundle.configs["player_gameplay_stats"]
    defaults = {row[stats["key"]]: row.get("default_value", 0) for row in stats["rows"]}
    day = "19000"
    def profile(daily=None):
        return {"schema_version": 1, "account_id": "a" * 64, "revision": 1, "entitlements": {},
                "save": {"gameplay_stats": copy.deepcopy(defaults), "archive": {"daily": {day: daily or {}}},
                         "content_inventory": {}}}
    def clear(mode, number=1):
        return {"kind": "mode_clear", "id": "offline-session-0001:" + mode + "_clear",
                "mode_id": mode, "difficulty_id": "n" + str(number), "count": 1, "day_key": day}
    def run(case, saved, command):
        result = service.settle(saved, command, False)
        cases.append({"case": case, "ok": result.get("ok") is True, "error": result.get("error")})
        return result
    for mode, number in (("pure", 1), ("standard", 1), ("rich", 1), ("cold", 4), ("scourge", 2)):
        result = run("actual_" + mode + "_worker", profile(), clear(mode, number))
        assert result.get("ok") is True, (mode, result)
        assert result["archive"]["mode_clear_counts"][mode]["n" + str(number)] == 1
    for mode, number in (("cold", 5), ("scourge", 3)):
        result = run("future_" + mode + "_tier_rejected", profile(), clear(mode, number))
        assert result.get("ok") is False and result.get("error") == "archive_mode_difficulty_unavailable"
    for mode, daily in (("rich", {"clear_total": 20}), ("rich", {"mode_rich": 20}),
                        ("cold", {"mode_cold": 10}), ("scourge", {"mode_scourge": 10})):
        saved = profile(daily)
        result = run("capped_" + "_".join(daily), saved, clear(mode))
        assert result.get("ok") is True
        assert result["gameplay_stats"] == saved["save"]["gameplay_stats"]
        assert not result["archive"].get("mode_clear_counts", {}).get(mode, {}).get("n1")
    challenge_cases = (("shadow_1", "shadow_total", 80, "shadow_counts"),
                       ("hunt_01", "fragment_01", 20, "fragment_totals"),
                       ("cage_1", "cage_total", 60, "cage_counts"),
                       ("social_ex", "social_ex", 10, "social_tickets"))
    for challenge, key, maximum, inventory in challenge_cases:
        command = {"kind": "challenge", "id": "offline-session-0001:challenge_kind:" + challenge,
                   "challenge_id": challenge, "kill_sequence": 1, "difficulty_id": "n10", "day_key": day}
        saved = profile({key: maximum})
        result = run("capped_" + key + "_challenge", saved, command)
        assert result.get("ok") is True, (challenge, result)
        assert not any(result["archive"].get(inventory, {}).values()), (challenge, result.get("archive"))
        assert result["archive"]["daily"][day][key] == maximum
    saved = profile({"boss_total": 300})
    saved["save"]["archive"]["boss_kills"] = 1000
    result = run("capped_boss", saved, {"kind": "boss_kill", "id": "offline-session-0001:boss:1", "day_key": day})
    assert result["archive"]["boss_kills"] == 1000
    result = run("capped_endless", profile({"endless_total": 50000}),
                 {"kind": "endless", "id": "offline-session-0001:endless:1", "wave": 1, "difficulty": 1, "day_key": day})
    assert result.get("ok") is True and result["archive"].get("endless_score", 0) == 0
    result = run("capped_online_coins", profile({"coins_total": 8000}),
                 {"kind": "online_checkpoint", "id": "offline-session-0001:online:1", "session": "offline-session-0001",
                  "actual_seconds": 60, "map_seconds": 60, "day_key": day})
    assert result.get("ok") is True and result["archive"]["online"]["coins"] == 0
    # An old accepted intent retains its operation identity, recorded config,
    # fingerprint and day while the current reducer applies acquisition caps.
    for kind in ("clear", "challenge"):
        command = ({"kind": "clear", "id": "offline-session-0001:clear", "difficulty_id": "n1", "count": 1, "day_key": day}
                   if kind == "clear" else {"kind": "challenge", "id": "offline-session-0001:challenge_kind:shadow_1",
                       "challenge_id": "shadow_1", "kill_sequence": 1, "difficulty_id": "n1", "day_key": day})
        daily = {"clear_total": 20} if kind == "clear" else {"shadow_total": 80}
        prepared = {"ok": True, "done": False, "profile": profile(daily), "command": command,
                    "config_hash": parent, "has_pass": False, "fingerprint": "existing-receipt-fingerprint"}
        before = copy.deepcopy(prepared)
        operation = command["id"]
        result = service.finish_prepared("a" * 64, operation, prepared, clear_mode="standard" if kind == "clear" else None)
        assert result.get("ok") is True and prepared == before
        name, payload = rpc.calls[-1]
        assert name == "archive_commit" and payload["p_id"] == operation and payload["p_error"] is None
        assert payload["p_archive"]["daily"][day] == daily
        cases.append({"case": "old_hash_" + kind + "_pending_current_cap_original_receipt", "ok": True})
    done = {"ok": True, "done": True, "original": "immutable completed response"}
    calls = len(rpc.calls)
    assert service.finish_prepared("a" * 64, "offline-existing", done) is done and len(rpc.calls) == calls
    cases.append({"case": "completed_receipt_unchanged", "ok": True})
    for recorded in (parent, plan["proof"]["lottery"]["old_pairs"][0][1]):
        for kind in ("lottery_draw", "lottery_exchange"):
            assert legacy_lottery_error(digest, recorded, kind) is None
    for current, recorded in ((parent, digest), (digest, "f" * 64)):
        assert legacy_lottery_error(current, recorded, "lottery_draw") == "lottery_config_refresh_required"
    for recorded, rule in bundle.compatible_config_hashes.items():
        for kind in {"clear", "boss_kill", "endless", "endless_reconcile", "challenge"} & set(rule["commands"]):
            assert accepts(bundle, recorded, kind) and upgrades(bundle, recorded, kind)
    cases.append({"case": "all_ancestor_caps_and_exact_lottery_pairs", "ok": True})
    # Use the actual release operator's local payload checks, substituting only
    # its remote pointer/service baseline probe with this pinned code snapshot.
    operator_spec = importlib.util.spec_from_file_location("local_caps_operator", ROOT / "tools/archive_caps_20261020/deploy_remote.py")
    operator_module = importlib.util.module_from_spec(operator_spec)
    operator_spec.loader.exec_module(operator_module)
    operator = operator_module.Operator(stage, sha((stage / "plan.json").read_bytes()))
    operator.old = baseline
    operator.baseline = lambda: json.loads((baseline / "release_manifest.json").read_bytes())
    assert operator.payload()["configs"] == bundle.configs
    cases.append({"case": "actual_release_operator_local_payload_manifest_configuration_lottery_checks", "ok": True})
    report = {"status": "PASS", "bundle_hash": digest, "parent_bundle": parent, "runtime": str(runtime),
              "lua": str(lua), "cases": cases, "overlay_hashes": plan["candidate"]["overlay"],
              "actual_subprocess_worker": True, "database_connections": 0, "remote_operations": 0}
    (stage / "validation_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, default=PACKAGE / "release_candidate/stage")
    parser.add_argument("--lua", type=Path, default=Path("C:/Program Files/lua/bin/lua5.1.exe"))
    args = parser.parse_args()
    result = validate(args.stage, args.lua)
    print(json.dumps({"status": result["status"], "bundle": result["bundle_hash"], "cases": len(result["cases"]),
                      "actual_lua_worker": True, "database_connections": 0}))


if __name__ == "__main__":
    main()
