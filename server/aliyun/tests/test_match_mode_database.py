"""Opt-in match-mode integration against a NEW disposable local PostgreSQL 17 DB.

The caller provisions/migrates a database named goufayu_restore_match_* first.
Only generated fixture accounts are written. Existing accounts are never read,
and neither this script nor its backend may connect to a remote database. Rows
are retained so a fresh backend instance can prove the baseline is durable.
No account values, tokens, connection strings, or driver errors are printed.
"""
from __future__ import annotations

import argparse
import configparser
from copy import deepcopy
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import sys
import threading
import uuid


class CheckFailed(RuntimeError):
    pass

TEST_STAGE = "preflight"

def check(condition, code):
    if not condition:
        raise CheckFailed(code)


def local_service(app_service):
    check(app_service == "goufayu_app", "fixed_application_service_required")
    filename = os.environ.get("PGSERVICEFILE")
    check(bool(filename), "explicit_local_service_file_required")
    services = configparser.ConfigParser(interpolation=None)
    check(bool(services.read(filename, encoding="utf-8")), "local_service_file_unreadable")
    check(app_service in services, "local_service_missing")
    value = services[app_service]
    check(value.get("host") in ("127.0.0.1", "::1")
          and value.get("hostaddr", value.get("host")) in ("127.0.0.1", "::1"), "remote_database_refused")
    check(re.fullmatch(r"goufayu_restore_match_[a-z0-9_]{1,40}", value.get("dbname", "")),
          "non_disposable_database_refused")
    check(value.get("user") == "goufayu_app", "application_role_required")
    return "service=" + app_service


def run(app_service, addon_root, backend_root, lua):
    global TEST_STAGE
    import psycopg
    check(re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", app_service), "service_name_invalid")
    # Resolve libpq services, then check the actual socket and database before
    # importing/building an application (which synchronizes configuration).
    dsn = local_service(app_service)
    with psycopg.connect(dsn, connect_timeout=3) as conn:
        identity = conn.execute("SELECT inet_server_addr()::text,current_database(),current_user,session_user").fetchone()
        check(identity[0].split("/")[0] in ("127.0.0.1", "::1"), "remote_database_refused")
        check(re.fullmatch(r"goufayu_restore_match_[a-z0-9_]{1,40}", identity[1]), "non_disposable_database_refused")
        check(identity[2:] == ("goufayu_app", "goufayu_app"), "application_role_required")
        check(conn.info.server_version // 10000 == 17, "postgresql_17_required")

    root = Path(addon_root).resolve()
    sys.path[:0] = [str(Path(backend_root).resolve()), str(root / "server")]
    from fishing_api.config import Settings
    from fishing_api.server import build_application, BoundedThreadingHTTPServer, make_handler
    from fishing_api import match_profiles
    from fishing_api.application import ApiError

    folder = root / "data/csv/玩家档案系统"
    settings = Settings(host="127.0.0.1", port=8765, api_token=secrets.token_hex(24),
        supabase_url="", supabase_key="", account_id_pepper=secrets.token_hex(32),
        reward_csv=folder / "star_blessing_reward_definitions.csv",
        rule_csv=folder / "fishing_system_rules.csv", gameplay_stats_csv=folder / "player_gameplay_stats.csv",
        request_timeout_seconds=20, database_backend="postgres", postgres_dsn=dsn,
        archive_http=True, addon_root=root, archive_lua_path=str(lua))
    TEST_STAGE = "build_application"
    app = build_application(settings)
    account = str(9_000_000_000_000_000 + secrets.randbelow(999_999_999_999))
    other = str(int(account) + 1)
    database_id = app._database_account_id(account)
    results = {}

    def real_profile(current=app, who=account):
        return current.archive.profile({"account_id": who})

    def context(current=app, session=None, who=account):
        return match_profiles.context(current, {"account_id": who, "match_session_id": session or match_id})

    # Seed only this run's synthetic account via the existing app RPCs. The
    # fixture contains permanent inventory, clears and bonuses from an old game.
    TEST_STAGE = "seed_isolated_account"
    before = real_profile()
    other_before = real_profile(who=other)
    old_archive = {"clear_counts": {"n5": 2}, "fixture_legacy": {"owned": 1}}
    old_inventory = {"acceptance_permanent_item": 2}
    operation = "mode_seed:" + uuid.uuid4().hex
    prepared = app.rpc_client.rpc("archive_prepare", {"p_account": database_id, "p_id": operation,
        "p_hash": app.archive.bundle.hash, "p_fingerprint": hashlib.sha256(operation.encode()).hexdigest(),
        "p_command": {"id": operation, "kind": "lottery_read"}})
    seeded = app.rpc_client.rpc("archive_commit_lottery", {"p_account": database_id, "p_id": operation,
        "p_revision": prepared["profile"]["revision"], "p_archive": old_archive,
        "p_deltas": {"initial_wood": 20}, "p_error": None, "p_inventory": old_inventory, "p_response": {}})
    check(seeded.get("done") is True, "legacy_fixture_failed")
    legacy = real_profile()
    check(legacy["revision"] > before["revision"], "fixture_revision_missing")

    match_id = "mode_match:" + uuid.uuid4().hex
    payload = {"account_id": account, "match_session_id": match_id, "mode": "pure"}
    TEST_STAGE = "pure_login"
    pure = match_profiles.login(app, payload)
    baseline = context()
    check(pure["save"]["gameplay_stats"] == app.gameplay_stats, "pure_defaults_not_restored")
    check(pure["save"]["archive"] == {} and pure["save"]["content_inventory"] == {}, "pure_old_bonus_leaked")
    check("account_profile" not in pure and "baseline" not in pure, "pure_login_private_baseline_leaked")
    check(pure["progression"]["clear_counts"].get("n5") == 2, "pure_unlock_history_missing")
    check(real_profile() == legacy, "login_changed_permanent_account")
    results["pure_default_view_preserves_permanent_save"] = True

    # The same session remains immutable, even when defaults or a retry change.
    TEST_STAGE = "immutable_baseline_and_mode"
    same = app.rpc_client.rpc("match_profile_login", {"p_account": database_id, "p_session": match_id,
        "p_mode": "pure", "p_defaults": {"initial_wood": 999}})
    check(same["baseline"] == baseline["baseline"] and same["defaults"] == baseline["defaults"],
          "login_retry_reset_baseline")
    try:
        match_profiles.login(app, dict(payload, mode="standard"))
    except ApiError as exc:
        check(exc.code == "match_mode_locked", "mode_switch_wrong_rejection")
    else:
        raise CheckFailed("mode_switch_not_rejected")
    try:
        context(who=other)
    except ApiError as exc:
        check(exc.code == "match_session_missing", "cross_account_wrong_rejection")
    else:
        raise CheckFailed("cross_account_context_visible")
    results["login_idempotency_mode_lock_and_account_isolation"] = True

    # A real authenticated HTTP handler must reject a missing/mismatched match
    # before an otherwise valid archive command reaches its mutation RPC.
    TEST_STAGE = "http_invalid_session"
    server = BoundedThreadingHTTPServer(("127.0.0.1", 0), make_handler(app))
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    command = {"id": "mode_clear" + uuid.uuid4().hex + ":clear", "kind": "clear", "difficulty_id": "n6", "count": 1}
    request = {"account_id": account, "config_hash": app.archive.bundle.hash,
               "match_session_id": "not_registered:" + uuid.uuid4().hex, "command": command}
    connection = http.client.HTTPConnection(*server.server_address, timeout=10)
    try:
        connection.request("POST", "/v1/archive/command", json.dumps(request),
            {"Authorization": "Bearer " + settings.api_token, "Content-Type": "application/json"})
        response = connection.getresponse()
        body = json.loads(response.read())
        check(response.status == 409 and body.get("error") == "match_session_missing", "missing_session_http_not_rejected")
    finally:
        connection.close(); server.shutdown(); server.server_close(); worker.join(timeout=5)
    check(real_profile() == legacy, "invalid_session_mutated_account")
    results["invalid_session_rejected_before_http_mutation"] = True

    # Shared production reducer + real PostgreSQL receipt, replayed twice.
    TEST_STAGE = "clear_commit_and_projection"
    request["match_session_id"] = match_id
    first = app.archive.command(request)
    second = app.archive.command(request)
    check(first.get("ok") and second.get("ok"), "clear_commit_failed")
    current = real_profile()
    check(current["save"]["archive"]["clear_counts"] == {"n5": 2, "n6": 1}, "clear_not_exactly_once")
    check(current["save"]["archive"]["fixture_legacy"] == {"owned": 1}, "old_archive_overwritten")
    check(current["save"]["content_inventory"] == old_inventory, "old_permanent_item_overwritten")
    check(real_profile(who=other) == other_before, "other_account_changed")
    view = match_profiles.project(app, payload, current, context())
    for field, default in app.gameplay_stats.items():
        expected = default + current["save"]["gameplay_stats"][field] - legacy["save"]["gameplay_stats"][field]
        spec = app.archive.bundle.tables["player_gameplay_stats"][field]
        if isinstance(spec.get("min_value"), (int, float)): expected = max(spec["min_value"], expected)
        if isinstance(spec.get("max_value"), (int, float)): expected = min(spec["max_value"], expected)
        check(view["save"]["gameplay_stats"][field] == expected, "pure_delta_projection_wrong")
    check(view["progression"]["clear_counts"].get("n6") == 1, "new_unlock_missing")
    check(view["save"]["content_inventory"] == {} and view["account_profile"]["save"]["content_inventory"] == old_inventory,
          "battle_account_views_not_separated")
    check(context()["baseline"] == baseline["baseline"], "reward_reset_baseline")
    results["real_clear_dedup_delta_unlock_and_old_inventory_preserved"] = True

    TEST_STAGE = "fresh_backend"
    fresh = build_application(settings)
    check(context(fresh) == baseline, "fresh_backend_lost_baseline")
    resumed = match_profiles.login(fresh, payload)
    check(resumed["save"] == view["save"] and resumed["progression"] == view["progression"],
          "fresh_backend_changed_projection")
    check(real_profile(fresh) == current, "fresh_backend_changed_permanent_save")
    standard = match_profiles.login(fresh, dict(payload, match_session_id="standard:" + uuid.uuid4().hex, mode="standard"))
    check(standard["save"] == current["save"], "standard_missing_permanent_save")
    results["fresh_backend_instance_resumes_durable_baseline"] = True

    # Projection arithmetic must respect configured bounds for negative changes.
    TEST_STAGE = "negative_delta"
    lowered = deepcopy(current)
    lowered["save"]["gameplay_stats"]["initial_wood"] = 0
    bounded = match_profiles.project(fresh, payload, lowered, context(fresh))
    check(bounded["save"]["gameplay_stats"]["initial_wood"] == 0, "negative_delta_not_clamped")
    check(real_profile(fresh) == current, "projection_wrote_permanent_values")
    results["negative_delta_is_bounded_and_read_only"] = True

    # A previous accepted-but-unfinished win must settle BEFORE a new baseline.
    # Otherwise a pure new match would inherit the old match's delayed bonuses.
    TEST_STAGE = "pending_clear_before_new_baseline"
    pending_account = fresh._database_account_id(other)
    pending_id = "pending_clear" + uuid.uuid4().hex + ":clear"
    pending_command = {"id": pending_id, "kind": "clear", "difficulty_id": "n5", "count": 1}
    fresh.rpc_client.rpc("archive_prepare", {"p_account": pending_account, "p_id": pending_id,
        "p_hash": fresh.archive.bundle.hash,
        "p_fingerprint": hashlib.sha256(json.dumps(pending_command, sort_keys=True).encode()).hexdigest(),
        "p_command": pending_command})
    new_payload = {"account_id": other, "match_session_id": "new_pending:" + uuid.uuid4().hex, "mode": "pure"}
    pending_login = match_profiles.login(fresh, new_payload)
    check(pending_login["progression"]["clear_counts"].get("n5") == 1, "pending_clear_not_drained")
    check(pending_login["save"]["gameplay_stats"] == fresh.gameplay_stats, "old_pending_reward_entered_new_match")
    check(pending_login["save"]["archive"] == {}, "old_pending_archive_entered_new_match")
    check(not fresh.rpc_client.rpc("archive_pending", {"p_account": pending_account}), "old_pending_clear_remains")
    results["previous_pending_clear_drained_before_baseline"] = True
    return {"status": "PASS", "checks": results, "real_postgresql": True,
            "database": identity[1], "remote_connections": False, "real_game_tested": False,
            "backend_recreated": True, "database_process_restarted": False,
            "account_values_printed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-service", required=True)
    parser.add_argument("--addon-root", required=True)
    parser.add_argument("--backend-root", required=True)
    parser.add_argument("--lua", required=True)
    parser.add_argument("--confirm-local-test-writes", action="store_true", required=True)
    args = parser.parse_args()
    try:
        report = run(args.app_service, args.addon_root, args.backend_root, args.lua)
    except Exception as exc:
        safe_code = getattr(exc, "code", "")
        safe_code = safe_code if isinstance(safe_code, str) and re.fullmatch(r"[a-z][a-z0-9_]{1,79}", safe_code) else type(exc).__name__
        report = {"status": "FAIL", "stage": TEST_STAGE, "code": str(exc) if isinstance(exc, CheckFailed) else safe_code,
                  "sqlstate": getattr(exc, "sqlstate", None), "account_values_printed": False}
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
