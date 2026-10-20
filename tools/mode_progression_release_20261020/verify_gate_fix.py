"""Verify the incremental mode-chain fix on the already-live caps baseline.

Creates a private PostgreSQL 17 cluster and a new synthetic database. Never
reads credentials or connects to an existing database. No running game pointers
are changed. All subprocess logs stay in the ignored test output directory.
"""
from __future__ import annotations

import argparse
import configparser
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import traceback
import urllib.error
import urllib.request
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
PG_BIN = ROOT / "output/video_shop_20261015/postgres_test/portable/pgsql/bin"
DEPS = ROOT / "output/video_shop_20261015/deps"
FISHING = ROOT / "output/endless_batch_20261010/baseline/backend/fishing_api"


def need(value, code):
    if not value:
        raise RuntimeError(code)


def main(candidate, selected_source):
    candidate = candidate.resolve()
    need(candidate.is_relative_to(ROOT / "output/mgate20"), "candidate_path_refused")
    selected_source = selected_source.resolve()
    need(selected_source == ROOT, "current_mode_source_required")
    review = json.loads((candidate / "review.json").read_bytes())
    for name, digest in review["files"].items():
        need(hashlib.sha256((candidate / name).read_bytes()).hexdigest() == digest, "candidate_changed")
    run = ROOT / "output/mode_progression_release_20261020/gate_fix" / ("isolated_" + uuid.uuid4().hex[:12])
    run.mkdir(parents=True)
    cluster, log = run / "cluster", []
    stage = "prepare"

    def command(name, args, timeout=45):
        path = run / ("process_" + str(len(log)) + ".log")
        with path.open("wb") as stream:
            process = subprocess.run([str(PG_BIN / (name + ".exe")), *map(str, args)],
                cwd=run, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        log.append({"program": name, "returncode": process.returncode})
        need(process.returncode == 0, name + "_failed")
        return path.read_text("utf-8", errors="replace")

    # The candidate contains the exact full live backend, with only two
    # reviewed changed modules. No older API or worktree service is substituted.
    harness = run / "backend"
    shutil.copytree(candidate / "backend", harness)
    # Freeze the applied daily-cap ledger plus only the new mode-chain004.
    # Do not let an unrelated target migration enter through the live worktree.
    dbtool_input = run / "dbtool_input"
    shutil.copytree(selected_source / "server/aliyun/database", dbtool_input,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    mode_sql = candidate / "database/202610200004_mode_unlock_chain.sql"
    need(mode_sql.is_file(), "candidate_mode_migration_missing")
    shutil.copy2(mode_sql, dbtool_input / "target" / mode_sql.name)
    need(hashlib.sha256((dbtool_input / "target/202610200002_archive_match_modes.sql").read_bytes()).hexdigest()
         == "70a8ddb268ea419431630961653d61e4d2404bc7d1772fb7012e9495d25cf817", "applied002_changed")
    need(hashlib.sha256((dbtool_input / "target/202610200003_archive_daily_limits.sql").read_bytes()).hexdigest()
         == "522891724d0d1df7e105f5da4f508a87e4cdd53c4ea21768a1022f26895ce9b2", "applied003_changed")
    sys.path[:0] = [str(harness), str(DEPS), str(dbtool_input)]
    import dbtool
    need(dbtool.HERE == dbtool_input.resolve(), "selected_dbtool_not_loaded")
    # Use the reviewed parent defaults, not concurrent gameplay-stat changes.
    bundle_json = json.loads((candidate / "addon/server/bundles" / review["bundle"] / "bundle.json").read_bytes())
    parent_json = json.loads((candidate / "addon/server/bundles" / review["parent"] / "bundle.json").read_bytes())
    need(bundle_json["configs"] == parent_json["configs"], "parent_configuration_changed")
    need(bundle_json["csv_hashes"] == parent_json["csv_hashes"], "parent_csv_manifest_changed")
    need(bundle_json["sources"].keys() == parent_json["sources"].keys(), "parent_source_manifest_changed")
    changed_sources = {name for name, value in bundle_json["sources"].items()
                       if value != parent_json["sources"][name]}
    need(changed_sources <= {"config/recorded_mode_balance.lua", "systems/archive_welfare_rewards.lua"},
         "unrelated_parent_lua_changed")
    need(all(bundle_json.get("compatible_config_hashes", {}).get(key) == value
             for key, value in parent_json.get("compatible_config_hashes", {}).items()),
         "historical_compatibility_changed")
    need(bundle_json["sources"]["worker.lua"] == parent_json["sources"]["worker.lua"],
         "parent_worker_changed")
    need((candidate / "backend/archive_backend/daily_limits.py").is_file()
         and (candidate / "backend/archive_backend/clear_receipts.py").is_file(), "live_quota_modules_missing")
    config = bundle_json["configs"]["player_gameplay_stats"]
    stats_csv = run / "player_gameplay_stats.csv"
    headers = list(dict.fromkeys(key for row in config["rows"] for key in row))
    with stats_csv.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=headers)
        writer.writeheader()
        for row in config["rows"]:
            writer.writerow({key: int(value) if type(value) is bool else value for key, value in row.items()})
    database = "goufayu_restore_mode_" + uuid.uuid4().hex[:12]
    with socket.socket() as reserve:
        reserve.bind(("127.0.0.1", 0))
        port = reserve.getsockname()[1]
    command("initdb", ["-D", cluster, "-U", "postgres", "-A", "trust", "--no-locale", "--encoding=UTF8"])
    started, http, thread = False, None, None
    report = {"status": "FAIL", "stage": stage, "remote_connections": 0, "real_accounts": False,
              "bundle": review["bundle"], "candidate": str(candidate.relative_to(ROOT)), "checks": {
                  "parent_configs_csv_daily_rules_and_unrelated_lua_preserved": "PASS"}}
    try:
        stage = "start_isolated_cluster"
        command("pg_ctl", ["-D", cluster, "-l", run / "postgres.log", "-o", "-h 127.0.0.1 -p " + str(port) + " -F", "-w", "-t", "15", "start"])
        started = True
        command("createdb", ["-h", "127.0.0.1", "-p", port, "-U", "postgres", database])
        psql = ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", port, "-U", "postgres", "-d", database]
        stage = "bootstrap_roles"
        command("psql", [*psql, "-f", dbtool_input / "init_roles.sql"])
        services = configparser.ConfigParser(interpolation=None)
        for role in ("goufayu_app", "goufayu_migrator"):
            services[role] = {"host": "127.0.0.1", "port": str(port), "dbname": database,
                              "user": role, "sslmode": "disable"}
        service_file = run / "pg_service.conf"
        with service_file.open("w", encoding="utf-8", newline="\n") as stream:
            services.write(stream, space_around_delimiters=False)
        os.environ["PGSERVICEFILE"] = str(service_file)
        import psycopg
        stage = "collect_complete_migrations"
        # The repository also retains independently deployed payment/VIP/rank
        # migrations outside this collector's historical ledger. Do not bypass
        # its allowlist or quietly republish those unrelated SQL files.
        migration_input = run / "migration_input"
        for name in (*dbtool.ARCHIVE_FILES, *(name for name, _ in dbtool.UPGRADE_FILES)):
            target = migration_input / "server/migrations" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(selected_source / "server/migrations" / name, target)
        target = migration_input / "tools/sql/202609060001_archive_fishing_inventory.sql"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "tools/sql/202609060001_archive_fishing_inventory.sql", target)
        collection = dbtool.collect(Path("D:/survival_database"), migration_input, run / "database")
        need(collection["migrations"] == 27, "mode_only_migration_count_changed")
        collected = json.loads((run / "database/migration_manifest.json").read_bytes())
        need(collected["entries"][-1]["id"] == "target/202610200004_mode_unlock_chain.sql",
             "mode_only_migration_tail_changed")
        need(any(item["id"].endswith("202610200003_archive_daily_limits.sql") for item in collected["entries"]), "live_daily_migration_missing")
        stage = "migrate_complete_schema"
        migration = dbtool.migrate(run / "database", "goufayu_migrator")
        need(migration["permissions"]["rpc_count"] == len(dbtool.RPC_SIGNATURES), "runtime_acl_count")
        replay = dbtool.migrate(run / "database", "goufayu_migrator")
        need(replay["new_migrations"] == 0, "migration_replay_not_idempotent")
        report["checks"]["full_sql_chain_hardening_replay"] = {"status": "PASS", "migrations": collection["migrations"], "rpc_count": len(dbtool.RPC_SIGNATURES)}
        stage = "restore_reviewed_baseline_stat_contract"
        # This is a NEW local test DB. Restore the previously reviewed additive
        # 103-stat baseline; payment migrations remain outside this test.
        command("psql", [*psql, "-c", "SET ROLE goufayu_owner", "-f", selected_source / "server/migrations/202610090001_archive_sync_compatibility.sql"])
        stage = "restore_existing_leaderboard_rpc_contract"
        # The live transport already admits these two read/binding RPCs.
        # Restore their existing isolated baseline without adding them to the
        # candidate migration list or deploying them anywhere. The later VIP
        # badge projection depends on payments and is outside this mode test.
        leaderboard_sql = selected_source / "server/migrations/202610160001_endless_leaderboard.sql"
        command("psql", [*psql, "-c", "SET ROLE goufayu_owner", "-f", leaderboard_sql])
        report["baseline_prerequisites"] = {
            "existing_leaderboard_rpc_sql": str(leaderboard_sql.relative_to(ROOT)),
            "existing_leaderboard_rpc_sha256": hashlib.sha256(leaderboard_sql.read_bytes()).hexdigest(),
            "candidate_migration": False, "payment_schema_created": False,
            "vip_badge_leaderboard_projection_tested": False,
            "scope": "Mode-only HTTP verification; existing 16-RPC transport contract restored locally"}
        stage = "register_exact_candidate_configuration"
        configuration = {"configs": bundle_json["configs"], "compatible_config_hashes": bundle_json["compatible_config_hashes"]}
        with psycopg.connect(host="127.0.0.1", port=port, user="postgres", dbname=database, autocommit=True) as connection:
            from psycopg.types.json import Jsonb
            for old in review["retained_old_bundles"]:
                old_data = json.loads((candidate / "addon/server/bundles" / old / "bundle.json").read_bytes())
                old_configuration = {"configs": old_data["configs"]}
                if old_data.get("compatible_config_hashes"):
                    old_configuration["compatible_config_hashes"] = old_data["compatible_config_hashes"]
                connection.execute("INSERT INTO public.archive_config_sets(config_hash,config) VALUES(%s,%s)", (old, Jsonb(old_configuration)))
            jsonb_digest = connection.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(configuration),)).fetchone()[0]
        guard_path = ROOT / "output/mode_progression_release_20261020/operator_caps_review/archive_sync_before.sql"
        if not guard_path.exists():
            # Reconstruct the already-deployed caps guard using its reviewed
            # original function and exact branch generator. Its SHA must match
            # the freshly read live definition; this cannot accept an older
            # guard or silently discard a branch added by another release.
            import ast
            original = json.loads((ROOT / "tmp/archive_caps_20261020/release_candidate/stage/schema_before.json").read_bytes())["functions"]["public.archive_sync_config(text,jsonb)"]["definition"]
            source = (ROOT / "tools/archive_caps_20261020/deploy_remote.py").read_text("utf-8-sig")
            tree = ast.parse(source)
            node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "exact_sync_branch")
            namespace = {"need": need, "HASH": __import__("re").compile(r"[0-9a-f]{64}\Z")}
            exec(compile(ast.Module(body=[node], type_ignores=[]), "reviewed_caps_guard_generator", "exec"), namespace)
            parent_config = {"configs": parent_json["configs"], "compatible_config_hashes": parent_json["compatible_config_hashes"]}
            with psycopg.connect(host="127.0.0.1", port=port, user="postgres", dbname=database, autocommit=True) as proof:
                parent_digest = proof.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(parent_config),)).fetchone()[0]
            reconstructed = namespace["exact_sync_branch"](original, review["parent"], parent_digest)
            need(hashlib.sha256(reconstructed.encode()).hexdigest() == "4b7f47f62b983770f9d02f81a772bda66e8e4433ba305b4fec6b89a8ed834b5d", "reconstructed_live_caps_guard_mismatch")
            guard_path.parent.mkdir(parents=True, exist_ok=True)
            guard_path.write_text(reconstructed, "utf-8", newline="\n")
        frozen_guard = guard_path.read_text("utf-8-sig")
        need(hashlib.sha256(frozen_guard.encode()).hexdigest() == "4b7f47f62b983770f9d02f81a772bda66e8e4433ba305b4fec6b89a8ed834b5d", "live_guard_baseline_changed")
        anchor = " -- Reviewed daily unique points: exact configuration with backed-up inventory repair.\n"
        need(frozen_guard.count(anchor) == 1, "guard_baseline_anchor_changed")
        addition = " -- Reviewed mode-chain004 candidate: exact immutable configuration; no account backfill.\n" + \
            " if p_hash='" + review["bundle"] + "' then\n" + \
            "  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'" + jsonb_digest + "' then\n" + \
            "   raise exception 'archive_mode_configuration_mismatch';\n  end if;\n" + \
            "  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;\n" + \
            "  select config into v from archive_config_sets where config_hash=p_hash;\n" + \
            "  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;\n" + \
            "  return jsonb_build_object('ok',true);\n end if;\n"
        registration = run / "archive_sync_registration.sql"
        registration.write_text(frozen_guard.replace(anchor, addition + anchor, 1), encoding="utf-8", newline="\n")
        command("psql", [*psql, "-c", "SET ROLE goufayu_owner", "-f", registration])
        report["registration"] = {"sql": str(registration.relative_to(ROOT)), "configuration_jsonb_sha256": jsonb_digest,
                                  "baseline": "Exact live archive-caps guard SHA4b7f47, retained byte-for-byte with one added hash branch"}
        with psycopg.connect(host="127.0.0.1", port=port, user="postgres", dbname=database, autocommit=True) as proof:
            definitions = {}
            for signature in ("public.match_profile_login(text,text,text,jsonb)", "public.archive_sync_config(text,jsonb)"):
                definition = proof.execute("SELECT pg_get_functiondef(to_regprocedure(%s))", (signature,)).fetchone()[0]
                definitions[signature] = {"definition": definition, "sha256": hashlib.sha256(definition.encode()).hexdigest()}
            report["registration"]["post_functions"] = definitions
            need(definitions["public.archive_sync_config(text,jsonb)"]["sha256"] == hashlib.sha256(registration.read_bytes()).hexdigest(),
                 "sync_function_newline_or_normalization_changed")
        stage = "build_real_api"
        from fishing_api.config import Settings
        from fishing_api.server import build_application, BoundedThreadingHTTPServer, make_handler
        from fishing_api import match_profiles
        token = secrets.token_hex(24)
        settings = Settings(host="127.0.0.1", port=8766, api_token=token, supabase_url="", supabase_key="",
            account_id_pepper=secrets.token_hex(32), reward_csv=ROOT / "data/csv/玩家档案系统/star_blessing_reward_definitions.csv",
            rule_csv=ROOT / "data/csv/玩家档案系统/fishing_system_rules.csv", gameplay_stats_csv=stats_csv,
            request_timeout_seconds=20, database_backend="postgres", postgres_dsn="service=goufayu_app",
            archive_http=True, addon_root=candidate / "addon", archive_lua_path="C:/Program Files/lua/bin/lua5.1.exe")
        app = build_application(settings)
        # Observe failures without changing business behavior or responses.
        original_command = app.archive.command
        def observed_command(value):
            try:
                return original_command(value)
            except Exception:
                (run / "command_failure_internal.log").write_text(traceback.format_exc(), encoding="utf-8")
                raise
        app.archive.command = observed_command
        original_project = match_profiles.project
        def observed_project(*args, **kwargs):
            try:
                return original_project(*args, **kwargs)
            except Exception:
                (run / "projection_failure_internal.log").write_text(traceback.format_exc(), encoding="utf-8")
                raise
        match_profiles.project = observed_project
        http = BoundedThreadingHTTPServer(("127.0.0.1", 0), make_handler(app))
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def post(route, payload, expected=200):
            request = urllib.request.Request("http://127.0.0.1:" + str(http.server_port) + route,
                data=json.dumps(payload).encode(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
            try:
                with opener.open(request, timeout=25) as response:
                    status, body = response.status, json.load(response)
            except urllib.error.HTTPError as error:
                status, body = error.code, json.load(error)
            need(status == expected, "http_status_" + route.replace("/", "_") + "_" + str(status))
            return body

        serial = 0
        def identity(account):
            nonlocal serial
            serial += 1
            return {"account_id": account, "match_session_id": "mode_only_" + str(serial) + "_" + uuid.uuid4().hex[:12]}

        def enter(account, mode):
            payload = identity(account)
            receipt = post("/v1/session/authenticate", payload)
            need(receipt.get("authenticated") is True, "admission_metadata_missing")
            need(isinstance(receipt.get("daily_limits", {}).get("by_key"), dict), "live_daily_metadata_missing")
            need(all(isinstance(receipt.get("progression", {}).get(name + "_clear_counts"), dict)
                     for name in ("rich", "cold", "scourge")), "advanced_progression_metadata_missing")
            view = post("/v1/session/login", dict(payload, mode=mode))
            need(view["mode"] == (mode if mode == "pure" else "standard"), "combat_projection_changed")
            if mode in ("rich", "cold", "scourge"):
                need(view.get("game_mode") == mode, "durable_game_mode_missing")
            return payload, view

        def clear(payload, mode, number, config_hash=None, request_id="mode-only-clear-intent"):
            kind = "clear" if mode == "pure" else mode + "_clear"
            body = post("/v1/archive/command", dict(payload, config_hash=config_hash or review["bundle"],
                command={"id": request_id, "kind": kind, "difficulty_id": "n" + str(number), "count": 1}))
            need(body.get("ok") is True, "clear_not_committed:" + str(body.get("error", "")))
            return body

        def saved(account):
            return app.archive.profile({"account_id": account})

        def seed(account, archive_value):
            # Fixtures belong only to this new local database and synthetic
            # accounts. Use the actual prepare/commit RPCs, as normal writes do.
            current = saved(account)
            account_hash = app._database_account_id(account)
            operation = "mode_only_seed:" + uuid.uuid4().hex
            prepared = app.rpc_client.rpc("archive_prepare", {"p_account": account_hash, "p_id": operation,
                "p_hash": review["bundle"], "p_fingerprint": hashlib.sha256(operation.encode()).hexdigest(),
                "p_command": {"id": operation, "kind": "lottery_read"}})
            merged = dict(current["save"]["archive"], **archive_value)
            done = app.rpc_client.rpc("archive_commit_lottery", {"p_account": account_hash, "p_id": operation,
                "p_revision": prepared["profile"]["revision"], "p_archive": merged, "p_deltas": {}, "p_error": None,
                "p_inventory": current["save"]["content_inventory"], "p_response": {}})
            need(done.get("done") is True, "synthetic_fixture_seed_failed")

        if hasattr(app.archive, "lottery_catalog"):
            stage = "preserve_existing_lottery_catalog"
            document = post("/v1/lottery/catalog", {})
            need(document.get("ok") is True and document.get("unchanged") is False,
                 "existing_catalog_unavailable")
            encoded = document.get("catalog_json")
            need(isinstance(encoded, str) and
                 hashlib.md5(encoded.encode("ascii"), usedforsecurity=False).hexdigest()
                 == document.get("catalog_md5"), "existing_catalog_digest_invalid")
            cached = post("/v1/lottery/catalog", {"md5": document["catalog_md5"]})
            need(cached.get("ok") is True and cached.get("unchanged") is True
                 and "catalog_json" not in cached, "existing_catalog_cached_read_changed")
            from archive_backend.bundle import Bundle
            from archive_backend.lottery_catalog import catalog_document
            parent_catalog = catalog_document(Bundle(candidate / "addon/server/bundles" / review["parent"]),
                                              settings.archive_lua_path)
            need(parent_catalog["catalog_md5"] == document["catalog_md5"],
                 "existing_catalog_contents_changed")
            report["checks"]["existing_catalog_http_cached_read_and_parent_contents"] = "PASS"

        stage = "database_direct_predecessor_validation"
        direct_checks = 0
        for mode, parent_mode in (("rich", "standard"), ("cold", "rich"), ("scourge", "cold")):
            for value in (False, True, "1", 1.5, -1, 0, 1):
                fixture = str(8_000_000_000_000_000 + secrets.randbelow(999_999_999))
                seed(fixture, {parent_mode + "_clear_counts": {"n10": value}})
                account_hash = app._database_account_id(fixture)
                fixture_session = "mode_only_direct_" + uuid.uuid4().hex
                result = app.rpc_client.rpc("match_profile_login", {
                    "p_account": account_hash, "p_session": fixture_session,
                    "p_mode": mode, "p_defaults": app.gameplay_stats})
                if type(value) is int and value == 1:
                    need(result.get("ok") is True and result.get("mode") == mode,
                         "database_positive_parent_did_not_unlock_" + mode)
                else:
                    need(result.get("error") == mode + "_mode_locked",
                         "database_invalid_parent_unlocked_" + mode)
                direct_checks += 1
        report["checks"]["database_direct_strict_predecessor_counts"] = {
            "status": "PASS", "cases": direct_checks,
            "invalid_counts": [False, True, "1", 1.5, -1, 0]}

        stage = "actual_http_mode_chain"
        account = str(9_000_000_000_000_000 + secrets.randbelow(999_999_999))
        payload, initial = enter(account, "standard")
        denied = post("/v1/session/login", dict(identity(account), mode="cold"), 409)
        need(denied.get("error") == "cold_mode_locked", "predecessor_admission_not_enforced")
        denied = post("/v1/session/login", dict(identity(account), mode="rich", unlocked=True), 409)
        need(denied.get("error") == "rich_mode_locked", "client_cannot_self_unlock")
        clear(payload, "standard", 10)
        sessions = {}
        for mode in ("rich", "cold", "scourge"):
            payload, before = enter(account, mode)
            sessions[mode] = payload
            result = clear(payload, mode, 5)
            need(result["profile"]["progression"][mode + "_clear_counts"].get("n5") == 1, "independent_n5_missing")
            again = clear(payload, mode, 5, request_id="different-client-intent")
            need(again["profile"]["progression"][mode + "_clear_counts"].get("n5") == 1, "duplicate_clear_added_count")
            for wrong in ("clear", "standard_clear", "rich_clear", "cold_clear", "scourge_clear"):
                if wrong != mode + "_clear":
                    post("/v1/archive/command", dict(payload, config_hash=review["bundle"],
                         command={"id": "cross-mode-claim", "kind": wrong,
                                  "difficulty_id": "n1", "count": 1}), 400)
            next_mode = {"rich": "cold", "cold": "scourge"}.get(mode)
            if next_mode:
                denied = post("/v1/session/login", dict(identity(account), mode=next_mode), 409)
                need(denied.get("error") == next_mode + "_mode_locked", "n5_cannot_unlock_next_mode")
            payload, _ = enter(account, mode)
            clear(payload, mode, 10)
        archive = saved(account)["save"]["archive"]
        need(all(archive[key].get("n10") == 1 for key in ("standard_clear_counts", "rich_clear_counts", "cold_clear_counts", "scourge_clear_counts")), "predecessor_chain_not_persisted")
        report["checks"]["actual_http_mode_chain_and_n10_temporary_targets"] = "PASS"
        report["checks"]["cross_mode_rejected_and_duplicate_receipt"] = "PASS"
        stage = "durable_session_identity"
        denied = post("/v1/session/login", dict(sessions["rich"], mode="cold"), 409)
        need(denied.get("error") == "match_mode_locked", "durable_session_rebound")
        report["checks"]["durable_session_cannot_change_game_mode"] = "PASS"
        stage = "old_parent_compatibility"
        legacy = str(int(account) + 2)
        legacy_payload, _ = enter(legacy, "standard")
        clear(legacy_payload, "standard", 5, review["parent"])
        need(saved(legacy)["save"]["archive"]["standard_clear_counts"].get("n5") == 1, "parent_hash_clear_did_not_upgrade")
        report["checks"]["parent_hash_real_rpc_clear_compatibility"] = "PASS"
        stage = "backend_recreation"
        app2 = build_application(settings)
        retry = match_profiles.login(app2, dict(payload, mode="scourge"))
        need(retry.get("game_mode") == "scourge" and retry["progression"]["scourge_clear_counts"].get("n10") == 1, "recreated_backend_lost_mode")
        report["checks"]["backend_recreation_keeps_durable_mode_and_progress"] = "PASS"
        # Its live exact allowlist includes the two pre-existing leaderboard
        # RPCs. Keep the transport's full role/table/DDL/function checks intact.
        need(app2.rpc_client.ready() is True, "live_transport_privileges_changed")
        with dbtool.connect("goufayu_app") as connection:
            need(not connection.execute("SELECT has_database_privilege(current_database(),'CREATE') OR "
                                        "has_database_privilege(current_database(),'TEMP')").fetchone()[0],
                 "application_database_ddl")
            need(not connection.execute("SELECT 1 FROM pg_namespace WHERE nspname !~ '^pg_' "
                                        "AND has_schema_privilege(oid,'CREATE') LIMIT 1").fetchone(),
                 "application_schema_ddl")
        from fishing_api.postgres import ALLOWED_FUNCTIONS
        report["checks"]["application_remains_minimum_privilege"] = {
            "status": "PASS", "exact_live_rpc_count": len(ALLOWED_FUNCTIONS), "ddl": False,
            "table_access": False, "role_membership": False}
        report["status"], report["stage"] = "PASS", "complete"
    except Exception as error:
        (run / "failure_internal.log").write_text(traceback.format_exc(), encoding="utf-8")
        report["stage"] = stage
        report["error_type"] = type(error).__name__
        report["code"] = str(error) if isinstance(error, RuntimeError) else getattr(error, "code", type(error).__name__)
        report["sqlstate"] = getattr(error, "sqlstate", None)
    finally:
        if http:
            http.shutdown()
            http.server_close()
        if thread:
            thread.join(timeout=3)
        if started or (cluster / "postmaster.pid").exists():
            command("pg_ctl", ["-D", cluster, "-m", "fast", "-w", "-t", "15", "stop"])
        report["cluster_stopped"] = True
        report["processes"] = log
        report["recorded_at"] = datetime.now(timezone.utc).isoformat()
        path = run / "report.json"
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"status": report["status"], "stage": report.get("stage"), "code": report.get("code"),
                          "report": str(path.relative_to(ROOT)), "cluster_stopped": True}))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--selected-source", type=Path,
                        default=ROOT)
    args = parser.parse_args()
    need(args.candidate is not None, "explicit_gate_fix_candidate_required")
    raise SystemExit(main(args.candidate, args.selected_source))
