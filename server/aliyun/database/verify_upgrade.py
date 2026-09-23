"""Audit a stopped test backend's migration without printing account data.

Snapshots use read-only owner transactions. Migration uses the existing guarded
dbtool path. A failed post-check does not undo already committed migrations;
keep the backend stopped and retain the pre-upgrade backup for recovery.
"""
from __future__ import annotations

import argparse
from datetime import datetime
from decimal import Decimal
import json
from pathlib import Path

import dbtool

WOOD_MIGRATION = "target/202609200003_remove_default_wood_income.sql"
SESSION_MIGRATION = "target/202609230001_match_profile_sessions.sql"
SESSION_TABLE = "match_profile_sessions"
MARKER = "survival_data_migrations"
MUTABLE = {"player_gameplay_stats": "player_id", "survival_players": "account_id"}


def rows(conn, table, columns=None):
    selection = ",".join(dbtool.quote_ident(name) for name in columns) if columns else "*"
    query = "SELECT row_to_json(t)::text FROM (SELECT " + selection + " FROM public." + dbtool.quote_ident(table) + ") t"
    # Only the two small per-player tables and ledgers are retained in memory;
    # immutable reward/history tables are fingerprinted with streaming cursors.
    return [json.loads(row[0], parse_float=Decimal) for row in conn.execute(query)]


def index_records(records, key):
    result = {row[key]: row for row in records}
    dbtool.require(len(result) == len(records), "upgrade_duplicate_record_key")
    return result


def snapshot(service, original=None):
    with dbtool.connect(service, readonly=True, role=dbtool.OWNER) as conn:
        database = dbtool.target_identity(conn)
        dbtool.verify_ledger_structure(conn)
        current = dbtool.inventory(conn)
        tables = original["tables"] if original else current["tables"]
        available = {item["name"] for item in current["tables"]}
        dbtool.require({item["name"] for item in tables} <= available, "upgrade_original_table_missing")
        immutable = [item for item in tables if item["name"] not in {*MUTABLE, dbtool.LEDGER, MARKER}]
        hashes = dbtool.fingerprint_tables(conn, immutable, original_columns=bool(original))
        records = {}
        for item in tables:
            name = item["name"]
            if name in MUTABLE:
                records[name] = index_records(rows(conn, name, [column[0] for column in item["columns"]]), MUTABLE[name])
        ledger = index_records(rows(conn, dbtool.LEDGER), "migration_id")
        markers = index_records(rows(conn, MARKER), "migration_id") if MARKER in available else {}
        added_counts = {}
        if original and SESSION_TABLE in available and SESSION_TABLE not in {t["name"] for t in original["tables"]}:
            added_counts[SESSION_TABLE] = conn.execute("SELECT count(*) FROM public.match_profile_sessions").fetchone()[0]
        conn.execute("ROLLBACK")
        return {"database": database, "tables": current["tables"], "hashes": hashes,
                "records": records, "ledger": ledger, "markers": markers, "added_counts": added_counts}


def timestamp_advanced(before, after):
    try:
        return datetime.fromisoformat(after) >= datetime.fromisoformat(before)
    except (ValueError, TypeError):
        return False


def check_rows(before, after, expected_changes):
    dbtool.require(set(before) == set(after), "upgrade_player_rows_added_or_removed")
    stamps = set()
    for key, old in before.items():
        current = after[key]
        expected = dict(old)
        changes = expected_changes.get(key)
        if changes:
            expected.update(changes)
            dbtool.require(timestamp_advanced(old.get("updated_at"), current.get("updated_at")),
                           "upgrade_timestamp_unexpected")
            expected["updated_at"] = current["updated_at"]
            stamps.add(current["updated_at"])
        dbtool.require(expected == current, "upgrade_player_data_unexpected")
    return stamps


def audit_snapshots(before, after, manifest):
    dbtool.require(before["database"] == after["database"], "upgrade_database_changed")
    applied = {key: item["sha256"] for key, item in before["ledger"].items()}
    dbtool.applied_prefix(manifest, applied)
    pending = [item for item in manifest["entries"] if item["id"] not in applied]
    wood_pending = any(item["id"] == WOOD_MIGRATION for item in pending)
    subtract = wood_pending and dbtool.WOOD_MARKER not in before["markers"]
    old_tables = {item["name"] for item in before["tables"]}
    new_tables = {item["name"] for item in after["tables"]}
    session_pending = any(item["id"] == SESSION_MIGRATION for item in pending)
    allowed_new = ({MARKER} if wood_pending else set()) | ({SESSION_TABLE} if session_pending else set())
    dbtool.require(new_tables == old_tables | allowed_new,
                   "upgrade_table_inventory_unexpected")
    if SESSION_TABLE in new_tables - old_tables:
        dbtool.require(after.get("added_counts", {}).get(SESSION_TABLE) == 0,
                       "upgrade_new_session_table_not_empty")
    dbtool.require(before["hashes"] == after["hashes"], "upgrade_immutable_history_changed")
    old_stats, new_stats = before["records"]["player_gameplay_stats"], after["records"]["player_gameplay_stats"]
    old_players, new_players = before["records"]["survival_players"], after["records"]["survival_players"]
    affected = {key for key, item in old_stats.items() if subtract and item["wood_per_second"] > 0}
    stats_changes = {key: {"wood_per_second": max(0, old_stats[key]["wood_per_second"] - 1)} for key in affected}
    dbtool.require(affected <= set(old_players), "upgrade_affected_player_missing")
    player_changes = {key: {"profile_revision": old_players[key]["profile_revision"] + 1} for key in affected}
    stamps = check_rows(old_stats, new_stats, stats_changes) | check_rows(old_players, new_players, player_changes)
    dbtool.require(len(stamps) <= 1, "upgrade_migration_timestamps_disagree")

    expected_entries = {item["id"]: item["sha256"] for item in [*manifest["entries"], *dbtool.security_entries(manifest)]}
    dbtool.require(set(after["ledger"]) == set(expected_entries), "upgrade_ledger_inventory_unexpected")
    for key, row in before["ledger"].items():
        dbtool.require(after["ledger"].get(key) == row, "upgrade_old_ledger_row_changed")
    for key, row in after["ledger"].items():
        dbtool.require(row["sha256"] == expected_entries[key], "upgrade_ledger_checksum_unexpected")

    expected_markers = set(before["markers"]) | ({dbtool.WOOD_MARKER} if wood_pending else set())
    dbtool.require(set(after["markers"]) == expected_markers, "upgrade_data_marker_inventory_unexpected")
    for key, row in before["markers"].items():
        dbtool.require(after["markers"].get(key) == row, "upgrade_old_data_marker_changed")
    dbtool.require(not subtract or dbtool.WOOD_MARKER in after["markers"], "upgrade_data_marker_missing")
    return {"status": "PASS", "database": after["database"],
            "existing_history_tables_unchanged": len(before["hashes"]),
            "existing_player_rows": len(old_players), "wood_rows_adjusted_once": len(affected),
            "immutable_history_hashes_match": True, "archive_inventory_and_outbox_preserved": True,
            "only_reviewed_player_changes": True, "old_ledger_rows_preserved": True,
            "data_marker_preserved": True, "schema_migrations_applied": len(pending),
            "repeat_run_all_business_rows_unchanged": not pending,
            "account_data_printed": False}


def run(service, bundle, report):
    # Reserve the report before any connection or migration, never overwrite.
    with Path(report).open("x", encoding="utf-8") as stream:
        result = {"status": "FAIL", "migration_attempted": False, "rollback_performed": False}
        try:
            manifest = dbtool.load_bundle(bundle)
            before = snapshot(service)
            dbtool.applied_prefix(manifest, {key: row["sha256"] for key, row in before["ledger"].items()})
            result["migration_attempted"] = True
            migration = dbtool.migrate(bundle, service)
            after = snapshot(service, before)
            result.update(audit_snapshots(before, after, manifest))
            result["migration"] = migration
        except Exception as exc:
            result["error"] = str(exc) if isinstance(exc, dbtool.Refused) else type(exc).__name__
            result["sqlstate"] = getattr(exc, "sqlstate", None)
        stream.write(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-service", required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    try:
        result = run(args.target_service, args.bundle, args.report)
    except Exception as exc:
        result = {"status": "FAIL", "error": type(exc).__name__}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
