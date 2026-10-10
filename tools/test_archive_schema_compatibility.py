"""Verify the archive migration in PostgreSQL without committing any fixtures.

Remote deployment calls verify(connection, migration_sql, immutable_bundle_data).
The connection must have schema-migration rights; every change is rolled back.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
import uuid

LEGACY_HASHES = (
    "2f4ee5dc4b4ff35378ef8b33eecd3d2ae150555c093ddf55f0bc0777058f5b8d",
    "288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7",
)


class _RollbackFixtures(Exception):
    pass


def verify(connection, migration_sql, bundle_data, apply_migration=True):
    from psycopg.types.json import Jsonb

    checks = []
    nonce = uuid.uuid4().hex
    account = hashlib.sha256(("archive-schema-compatibility:" + nonce).encode()).hexdigest()
    payload = {"configs": bundle_data["configs"],
               "compatible_config_hashes": bundle_data["compatible_config_hashes"]}
    target_hash = hashlib.sha256(json.dumps(bundle_data, ensure_ascii=False, sort_keys=True,
                                           separators=(",", ":")).encode()).hexdigest()

    def check(condition, label):
        if not condition:
            raise AssertionError(label)
        checks.append(label)

    def rpc(name, types, values):
        encoded = [Jsonb(value) if kind == "jsonb" else value
                   for kind, value in zip(types, values)]
        signature = ",".join("%s::" + kind for kind in types)
        return connection.execute("SELECT public." + name + "(" + signature + ")", encoded).fetchone()[0]

    def denied(label, error, callback):
        try:
            with connection.transaction():
                callback()
        except Exception as exc:
            check(error in str(exc), label)
        else:
            raise AssertionError(label + ": accepted")

    def prepare(version, kind, suffix):
        operation = "compatibility:" + nonce + ":" + suffix
        command = {"id": operation, "kind": kind}
        if kind == "clear":
            command.update(difficulty_id="n1", count=1, cooperative_win=1)
        fingerprint = hashlib.sha256(json.dumps(command, sort_keys=True).encode()).hexdigest()
        prepared = rpc("archive_prepare", ["text", "text", "text", "text", "jsonb"],
                       [account, operation, version, fingerprint, command])
        check(prepared.get("ok") and not prepared.get("done"), suffix + "_prepared")
        return operation, fingerprint, prepared

    def commit(operation, prepared, deltas):
        return rpc("archive_commit", ["text", "text", "bigint", "jsonb", "jsonb", "text"],
                   [account, operation, prepared["profile"]["revision"],
                    {"clear_counts": {"n1": 1}, "cooperative_clear_count": 1}, deltas, None])

    try:
        with connection.transaction():
            if apply_migration:
                # Own the transaction so the migration's outer COMMIT cannot
                # accidentally persist schema changes or fixture accounts.
                inner = re.sub(r"(?im)^begin;\s*", "", migration_sql, count=1)
                inner = re.sub(r"(?im)^commit;\s*$", "", inner, count=1)
                check(not re.search(r"(?im)^commit;", inner), "migration_outer_commit_removed")
                connection.execute(inner)
                checks.append("migration_compiles")
            check(rpc("archive_sync_config", ["text", "jsonb"], [target_hash, payload])["ok"],
                  "candidate_schema_registered")
            check(rpc("archive_sync_config", ["text", "jsonb"], [target_hash, payload])["ok"],
                  "config_registration_idempotent")
            defaults = {row["field_id"]: row["default_value"]
                        for row in bundle_data["configs"]["player_gameplay_stats"]["rows"]}
            rpc("ensure_player_gameplay_stats", ["text", "jsonb"], [account, defaults])

            for index, legacy in enumerate(LEGACY_HASHES):
                operation, fingerprint, prepared = prepare(legacy, "clear", "legacy_clear_" + str(index))
                first = commit(operation, prepared, {"starjoy_points_earned": 100,
                                                      "starjoy_reward_level": 1,
                                                      "hero_execute_health_threshold_pct": 1,
                                                      "vip_level": 1,
                                                      "shop_paid_currency": 1,
                                                      "vip_recharge_total_fen": 100})
                check(first.get("ok") and first.get("done"), "legacy_clear_new_stats_commit_" + str(index))
                second = commit(operation, prepared, {"starjoy_points_earned": 100})
                check(second["profile"] == first["profile"], "legacy_clear_receipt_replay_" + str(index))
                row = connection.execute(
                    "SELECT config_hash,fingerprint FROM public.archive_operations WHERE account_id=%s AND operation_id=%s",
                    (account, operation)).fetchone()
                check(row == (legacy, fingerprint), "legacy_hash_and_fingerprint_preserved_" + str(index))

            for kind in ("lottery_draw", "commerce_purchase", "unapproved_fixture"):
                operation, _, prepared = prepare(LEGACY_HASHES[0], kind, kind)
                denied(kind + "_cannot_borrow_schema", "archive_stat_invalid",
                       lambda: commit(operation, prepared, {"starjoy_points_earned": 1}))

            fixture_hash = hashlib.sha256(("unapproved-hash:" + nonce).encode()).hexdigest()
            old_config = connection.execute("SELECT config FROM public.archive_config_sets WHERE config_hash=%s",
                                            (LEGACY_HASHES[0],)).fetchone()[0]
            rpc("archive_sync_config", ["text", "jsonb"], [fixture_hash, old_config])
            operation, _, prepared = prepare(fixture_hash, "clear", "unknown_hash")
            denied("unknown_hash_cannot_borrow_schema", "archive_stat_invalid",
                   lambda: commit(operation, prepared, {"starjoy_points_earned": 1}))

            operation, _, prepared = prepare(LEGACY_HASHES[0], "clear", "original_bounds")
            denied("original_stat_bounds_preserved", "archive_stat_bounds",
                   lambda: commit(operation, prepared, {"tower_critical_chance_pct": 101}))
            operation, _, prepared = prepare(LEGACY_HASHES[0], "clear", "invalid_new_stat")
            denied("new_stat_bounds_enforced", "archive_stat_bounds",
                   lambda: commit(operation, prepared, {"starjoy_reward_level": 25}))
            denied("online_counter_never_written_by_archive", "archive_stat_invalid",
                   lambda: commit(operation, prepared, {"online_seconds_total": 1}))

            for label, corrupt in (
                ("old_defaults_cannot_change", lambda value: value["configs"]["player_gameplay_stats"]["rows"][0].update(default_value=777)),
                ("unknown_alias_cannot_register", lambda value: value["compatible_config_hashes"].update({"a" * 64: value["compatible_config_hashes"][LEGACY_HASHES[0]]})),
                ("commerce_upgrade_cannot_register", lambda value: value["compatible_config_hashes"][LEGACY_HASHES[0]]["upgrade_commands"].append("commerce_purchase")),
            ):
                changed = copy.deepcopy(payload)
                corrupt(changed)
                changed_hash = hashlib.sha256(json.dumps(changed, sort_keys=True).encode()).hexdigest()
                denied(label, "archive_compatibility", lambda: rpc("archive_sync_config", ["text", "jsonb"],
                                                                   [changed_hash, changed]))
            raise _RollbackFixtures()
    except _RollbackFixtures:
        pass

    check(connection.execute("SELECT count(*) FROM public.survival_players WHERE account_id=%s", (account,)).fetchone()[0] == 0,
          "fixture_account_rolled_back")
    return {"ok": True, "checks": checks, "check_count": len(checks),
            "database_changes_committed": False, "player_archive_values_changed": False}
