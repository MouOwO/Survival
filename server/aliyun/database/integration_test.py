"""Rollback-only app-role integration checks in an explicitly isolated test DB.

Run only after the full migration chain. No original accounts, source service,
or production endpoint is used. Test records exist only in one rolled-back txn.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import time
import uuid

import dbtool


def run(service, addon_root):
    from psycopg.types.json import Jsonb
    defaults = {}
    source = Path(addon_root) / "data/csv/玩家档案系统/player_gameplay_stats.csv"
    with source.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            if row['field_id'].startswith('#') or row.get('enabled') != '1':
                continue
            defaults[row["field_id"]] = int(row["default_value"]) if row["storage_type"] == "integer" else float(row["default_value"])
    with dbtool.connect(service) as conn:
        dbtool.server_version(conn, target=True)
        database, current, session = conn.execute("SELECT current_database(),current_user,session_user").fetchone()
        dbtool.require(dbtool.TRIAL_RE.fullmatch(database) and current == session == dbtool.APP,
                       "integration_target_or_role_refused")
        conn.execute("BEGIN")
        try:
            def rpc(name, types, values):
                arguments = ",".join("%s::" + item for item in types)
                encoded = [Jsonb(v) if t == "jsonb" else v for t, v in zip(types, values)]
                return conn.execute("SELECT public." + name + "(" + arguments + ")", encoded).fetchone()[0]

            def denied(query):
                try:
                    with conn.transaction():
                        conn.execute(query)
                except Exception as exc:
                    dbtool.require(getattr(exc, "sqlstate", None) == "42501", "unexpected_denial_error")
                else:
                    raise dbtool.Refused("app_privilege_escalation")

            nonce = uuid.uuid4().hex
            account = hashlib.sha256(("isolated-migration-test:" + nonce).encode()).hexdigest()
            rpc("ensure_player_gameplay_stats", ["text", "jsonb"], [account, defaults])
            profile = rpc("get_fishing_profile", ["text"], [account])
            dbtool.require(profile["account_id"] == account, "profile_account_mismatch")
            dbtool.require(all(float(profile["save"]["gameplay_stats"][k]) == float(v) for k, v in defaults.items()),
                           "csv_defaults_mismatch")
            for sql in ("SELECT * FROM public.survival_players", "CREATE TABLE public.forbidden_audit(id integer)",
                        "CREATE TEMP TABLE forbidden_audit(id integer)", "SET ROLE goufayu_owner",
                        "SELECT public.fishing_profile_json('test')",
                        "SELECT * FROM public.survival_data_migrations"):
                denied(sql)

            version = 2147000000
            reward_id = "star_blessing_audit_" + nonce
            definitions = [{"reward_id": reward_id, "display_name": "isolated migration fixture",
                            "weight": 1, "effect_key": "wood_per_second", "effect_scope": "permanent",
                            "value_min": 2, "value_max": 2, "stacking_rule": "add", "cap_value": 0}]
            digest = hashlib.sha256(json.dumps(definitions, sort_keys=True).encode()).hexdigest()
            rpc("sync_star_blessing_reward_definitions", ["integer", "text", "jsonb"], [version, digest, definitions])
            grant = str(uuid.uuid4())
            values = [account, grant, reward_id, version, 2]
            first = rpc("grant_out_of_match_reward", ["text", "uuid", "text", "integer", "numeric"], values)
            second = rpc("grant_out_of_match_reward", ["text", "uuid", "text", "integer", "numeric"], values)
            dbtool.require(first == second, "grant_idempotency_failed")
            profile = rpc("get_fishing_profile", ["text"], [account])
            dbtool.require(float(profile["save"]["gameplay_stats"]["wood_per_second"]) == defaults["wood_per_second"] + 2,
                           "grant_delta_applied_more_than_once")

            config = {"configs": {"player_gameplay_stats": {"rows": [
                {"field_id": "wood_per_second", "storage_type": "decimal", "min_value": 0, "max_value": 1000000}]}}}
            config_hash = hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()
            rpc("archive_sync_config", ["text", "jsonb"], [config_hash, config])
            operation = "fixture:" + nonce
            prepared = rpc("archive_prepare", ["text", "text", "text", "text", "jsonb"],
                           [account, operation, config_hash, nonce, {"id": operation, "kind": "fixture"}])
            revision = prepared["profile"]["revision"]
            commit_args = [account, operation, revision, {"fixture": True}, {"wood_per_second": 1}, None]
            first = rpc("archive_commit", ["text", "text", "bigint", "jsonb", "jsonb", "text"], commit_args)
            second = rpc("archive_commit", ["text", "text", "bigint", "jsonb", "jsonb", "text"], commit_args)
            dbtool.require(first["profile"] == second["profile"] and first["done"], "archive_idempotency_failed")
            dbtool.require(not rpc("archive_pending", ["text"], [account]), "unexpected_pending_operation")

            # The lottery commits permanent inventory and response atomically.
            # A stale operation may not replace the latest inventory with {}.
            lottery_id, stale_id = "lottery:" + nonce, "stale:" + nonce
            lottery = rpc("archive_prepare", ["text", "text", "text", "text", "jsonb"],
                          [account, lottery_id, config_hash, nonce,
                           {"id": lottery_id, "kind": "lottery_draw"}])
            rpc("archive_prepare", ["text", "text", "text", "text", "jsonb"],
                [account, stale_id, config_hash, nonce, {"id": stale_id, "kind": "lottery_read"}])
            lottery_types = ["text", "text", "bigint", "jsonb", "jsonb", "text", "jsonb", "jsonb"]
            inventory = {"acceptance_permanent_item": 1}
            response = {"draws": [{"item_id": "acceptance_permanent_item", "quantity": 1}]}
            lottery_args = [account, lottery_id, lottery["profile"]["revision"], {"fixture": True}, {}, None,
                            inventory, response]
            first = rpc("archive_commit_lottery", lottery_types, lottery_args)
            second = rpc("archive_commit_lottery", lottery_types, lottery_args)
            dbtool.require(first["done"] and first["response"] == second["response"] == response and
                           first["profile"] == second["profile"], "lottery_idempotency_failed")
            dbtool.require(first["profile"]["save"]["content_inventory"] == inventory,
                           "lottery_inventory_commit_failed")
            stale = rpc("archive_commit_lottery", lottery_types,
                        [account, stale_id, lottery["profile"]["revision"], {}, {}, None, {}, {}])
            dbtool.require(stale.get("error") == "archive_revision_conflict", "stale_inventory_not_rejected")
            retained = rpc("get_fishing_profile", ["text"], [account])
            dbtool.require(retained["save"]["content_inventory"] == inventory and
                           retained["revision"] == first["profile"]["revision"], "stale_inventory_overwrote_latest")

            session_id = "session:" + nonce
            types = ["text", "text", "text", "integer", "integer", "integer", "integer", "boolean"]
            rpc("checkpoint_online_time", types, [account, session_id, "first:" + nonce, 30, version, 1, 1, False])
            time.sleep(1.1)
            checkpoint = [account, session_id, "final:" + nonce, 30, version, 1, 1, True]
            first = rpc("checkpoint_online_time", types, checkpoint)
            second = rpc("checkpoint_online_time", types, checkpoint)
            dbtool.require(first == second and first["elapsed_seconds"] >= 1, "checkpoint_idempotency_failed")
            outbox = rpc("archive_online_pending", ["text", "text"], [account, config_hash])
            dbtool.require(len(outbox) == 1, "checkpoint_outbox_not_exactly_once")
            dbtool.require("archive" in first.get("profile", profile)["save"] or "archive" in profile["save"], "profile_archive_missing")
            return {"status": "PASS", "database": database, "csv_defaults": len(defaults),
                    "app_privilege_denials": 6, "grant_idempotency": True,
                    "archive_idempotency": True, "checkpoint_final_and_idempotency": True,
                    "lottery_idempotency_and_response": True, "stale_inventory_rejected": True,
                    "outbox_exactly_once": True, "committed_test_rows": 0}
        finally:
            conn.execute("ROLLBACK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-service", required=True)
    parser.add_argument("--addon-root", required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.app_service, args.addon_root)))
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "reason": str(exc) if isinstance(exc, dbtool.Refused) else type(exc).__name__,
                          "sqlstate": getattr(exc, "sqlstate", None)}))
        raise SystemExit(1)
