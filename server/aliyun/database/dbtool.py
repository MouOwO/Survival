"""PostgreSQL 17 migration / read-only backup / isolated restore tools.

Credentials are supplied exclusively by libpq service/pass files. This module
never loads .env, prints connection strings, or initializes/deletes a cluster.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

HERE = Path(__file__).resolve().parent
OWNER = "goufayu_owner"
APP = "goufayu_app"
SCHEMAS = ("public", "extensions")
LEDGER = "_goufayu_migrations"
TABLES = {
    "survival_players", "player_gameplay_stats", "reward_grants",
    "player_effect_totals", "out_of_match_reward_idempotency",
    "online_time_sessions", "online_time_idempotency",
    "star_blessing_reward_definition_sets", "star_blessing_reward_definitions",
    "archive_config_sets", "player_archive_state", "archive_entitlements",
    "archive_operations", "archive_online_outbox", "survival_data_migrations", "match_profile_sessions", LEDGER,
}
FUNCTIONS = {
    "reject_fishing_immutable_mutation", "fishing_profile_json", "get_fishing_profile",
    "ensure_player_gameplay_stats", "sync_star_blessing_reward_definitions",
    "grant_out_of_match_reward", "checkpoint_online_time", "archive_sync_config",
    "archive_resume", "archive_prepare", "archive_commit", "archive_capture_online",
    "archive_online_pending", "archive_pending", "archive_commit_lottery", "match_profile_login", "match_profile_context",
}
RPC_SIGNATURES = (
    "get_fishing_profile(text)", "ensure_player_gameplay_stats(text,jsonb)",
    "sync_star_blessing_reward_definitions(integer,text,jsonb)",
    "grant_out_of_match_reward(text,uuid,text,integer,numeric)",
    "checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean)",
    "archive_sync_config(text,jsonb)", "archive_resume(text,text)",
    "archive_prepare(text,text,text,text,jsonb)",
    "archive_commit(text,text,bigint,jsonb,jsonb,text)",
    "archive_online_pending(text,text)", "archive_pending(text)",
    "archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)",
    "match_profile_login(text,text,text,jsonb)", "match_profile_context(text,text)",
)
LEGACY_FILES = (
    "202608170001_fishing_rewards.sql", "202608200001_player_gameplay_stats.sql",
    "202608210001_out_of_match_reward_grants.sql", "202608210002_online_time_checkpoints.sql",
    "202608220003_fix_reward_grant_pgcrypto_search_path.sql", "202608230001_star_blessing_reward_definitions.sql",
    "202608230002_sync_star_blessing_v3.sql", "202608230003_remove_legacy_fishing_persistence.sql",
    "202608230004_add_star_blessing_gameplay_stats.sql", "202608230005_fix_gameplay_stats_attack_interval.sql",
    "202608230006_include_definition_version_in_online_grant_id.sql", "202608230007_finalize_online_time_session.sql",
)
ARCHIVE_FILES = ("202609060001_archive_stat_columns.sql", "202609060002_all_archive.sql",
                 "202609060003_archive_buildings.sql")
UPGRADE_FILES = (
    ("202609140001_http_lottery.sql", "202609200001_http_lottery.sql"),
    ("202609140002_gameplay_stats_csv_bounds.sql", "202609200002_gameplay_stats_csv_bounds.sql"),
    ("202609140003_remove_default_wood_income.sql", "202609200003_remove_default_wood_income.sql"),
    ("202609140004_remove_default_attack_growth.sql", "202609200004_remove_default_attack_growth.sql"),
)
HARDEN_PATCHES = ("harden_lottery.sql", "harden_match_sessions.sql")
# These two files were created with LF for test03. Git autocrlf can change the
# checkout bytes; only restore the exact reviewed release hash, never accept
# arbitrary normalization or mutate a deployed ledger to fit edited SQL.
TEST03_LF_HASHES = {
    "202609190001_attack_interval_semantics.sql": "7408538108d179f876c2be1dd773ea3c5e7fb93153cd878f2aa1548cd705c378",
    "harden.sql": "f0b7f186873de70d745fe1ccec306afa416d2c73a6f8b8c49be558c001d6426f",
}
WOOD_MARKER = "20260914_remove_default_wood_income"
SERVICE_RE = re.compile(r"[A-Za-z0-9_.-]{1,100}\Z")
TRIAL_RE = re.compile(r"(?:goufayu_test|goufayu_restore_[a-z0-9_]{1,48})\Z")
FORBIDDEN_DEPENDENCY = re.compile(r"\b(?:auth|storage|realtime|vault|graphql|net)\s*\.", re.I)


class Refused(RuntimeError):
    """Non-sensitive operational refusal safe to print."""


def require(condition, code):
    if not condition:
        raise Refused(code)


def sha256(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def release_bytes(source):
    source = Path(source)
    raw = source.read_bytes()
    if source.name in TEST03_LF_HASHES:
        raw = raw.replace(b"\r\n", b"\n")
        require(hashlib.sha256(raw).hexdigest() == TEST03_LF_HASHES[source.name],
                "historical_test03_sql_modified")
    return raw


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2,
                                    default=str) + "\n", encoding="utf-8")


def quote_ident(value):
    return '"' + value.replace('"', '""') + '"'


def connect(service, *, readonly=False, role=None):
    require(SERVICE_RE.fullmatch(service), "invalid_service_name")
    require(role in (None, OWNER), "invalid_source_role")
    import psycopg
    conn = psycopg.connect(service=service, connect_timeout=15,
                           application_name="goufayu_database_tool", autocommit=True)
    if role:
        conn.execute("SET ROLE " + quote_ident(role))
    conn.execute("SET timezone='UTC'")
    conn.execute("SET datestyle='ISO, YMD'")
    conn.execute("SET extra_float_digits=3")
    if readonly:
        conn.execute("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY")
    return conn


def server_version(conn, *, target=False):
    version = int(conn.execute("SHOW server_version_num").fetchone()[0])
    require(version // 10000 == 17 if target else 130000 <= version < 180000,
            "postgresql_17_target_required" if target else "unsupported_source_version")
    return version


def binary(name, pg_bin=None):
    path = str(Path(pg_bin) / (name + (".exe" if os.name == "nt" else ""))) if pg_bin else shutil.which(name)
    require(path and Path(path).is_file(), "postgresql_client_missing_" + name)
    result = subprocess.run([path, "--version"], capture_output=True, text=True, check=False)
    require(result.returncode == 0 and re.search(r"\(PostgreSQL\) 17(?:\.|\s)", result.stdout),
            "postgresql_client_17_required_" + name)
    return path


def run_client(argv, *, readonly=False):
    env = os.environ.copy()
    env["PGAPPNAME"] = "goufayu_database_tool"
    if readonly:
        env["PGOPTIONS"] = "-c default_transaction_read_only=on -c timezone=UTC -c datestyle=ISO,YMD"
    result = subprocess.run(argv, capture_output=True, env=env, check=False)
    # Client diagnostics can include connection details or row values; do not
    # emit raw stdout/stderr. The administrator can inspect separately if needed.
    require(result.returncode == 0, "postgresql_client_failed_" + Path(argv[0]).stem)
    return result.stdout


def collect(legacy_root, addon_root, destination):
    legacy_root, addon_root, destination = map(Path, (legacy_root, addon_root, destination))
    # Freeze the deployed 17-entry sequence. Sorting all newly pulled legacy
    # SQL would insert files before the recorded addon/manual/target entries.
    legacy_dir, addon_dir = legacy_root / "supabase/migrations", addon_root / "server/migrations"
    known = set(LEGACY_FILES) | set(ARCHIVE_FILES) | {name for name, _ in UPGRADE_FILES}
    require({p.name for p in legacy_dir.glob("*.sql")} <= known, "unreviewed_legacy_migration")
    require({p.name for p in addon_dir.glob("*.sql")} <= set(ARCHIVE_FILES) | {name for name, _ in UPGRADE_FILES},
            "unreviewed_addon_migration")
    sources = [("legacy", legacy_dir / name, name) for name in LEGACY_FILES]
    sources += [("addon", addon_dir / name, name) for name in ARCHIVE_FILES]
    # The manual inventory patch is already incorporated in all_archive, and
    # remains a no-op if replayed last. Preserve it rather than lose provenance.
    sources.append(("manual", addon_root / "tools/sql/202609060001_archive_fishing_inventory.sql",
                    "202609060001_archive_fishing_inventory.sql"))
    # Freeze the already deployed target prefix; append later target migrations
    # only after the 20260920 upgrades, never insert ahead of their ledger entries.
    sources += [("target", HERE / "target/202609190001_attack_interval_semantics.sql",
                 "202609190001_attack_interval_semantics.sql")]
    sources += [("target", addon_dir / name, target_name) for name, target_name in UPGRADE_FILES]
    sources += [("target", p, p.name) for p in sorted((HERE / "target").glob("*.sql"))
                if p.name != "202609190001_attack_interval_semantics.sql"]
    entries = []
    for group, source, filename in sources:
        require(source.is_file(), "migration_source_missing")
        relative = Path("migrations") / group / filename
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        raw = release_bytes(source)
        source_hash = hashlib.sha256(raw).hexdigest()
        if target.exists():
            require(sha256(target) == source_hash, "existing_bundle_migration_differs")
        else:
            target.write_bytes(raw)
        entries.append({"id": group + "/" + filename, "path": relative.as_posix(), "group": group,
                        "sha256": source_hash, "bytes": len(raw)})
    for name in ("dbtool.py", "init_roles.sql", "harden.sql", "requirements.txt", "README.md",
                 "test_dbtool.py", "integration_test.py", "verify_upgrade.py", "test_verify_upgrade.py",
                 "rollback_match_session_privileges.sql", *HARDEN_PATCHES):
        source, target = HERE / name, destination / name
        if source.exists() and source.resolve() != target.resolve():
            target.write_bytes(release_bytes(source))
    manifest = {"format": 1, "postgres_major": 17, "entries": entries,
                "harden_sha256": sha256(destination / "harden.sql"),
                "hardening_patches": [{"id": "security/" + name, "path": name,
                                       "sha256": sha256(HERE / name)} for name in HARDEN_PATCHES]}
    write_json(destination / "migration_manifest.json", manifest)
    return {"status": "collected", "migrations": len(entries)}


def load_bundle(bundle):
    bundle = Path(bundle).resolve()
    manifest = json.loads((bundle / "migration_manifest.json").read_text(encoding="utf-8"))
    require(manifest.get("format") == 1 and manifest.get("postgres_major") == 17, "bundle_format_invalid")
    seen = set()
    for entry in manifest["entries"]:
        path = (bundle / entry["path"]).resolve()
        require(path.is_relative_to(bundle) and path.suffix == ".sql", "bundle_path_invalid")
        require(entry["id"] not in seen, "duplicate_migration_id")
        seen.add(entry["id"])
        require(path.is_file() and sha256(path) == entry["sha256"], "migration_checksum_mismatch")
    require(sha256(bundle / "harden.sql") == manifest["harden_sha256"], "hardening_checksum_mismatch")
    for patch in manifest.get("hardening_patches", []):
        path = (bundle / patch["path"]).resolve()
        require(path.is_relative_to(bundle) and path.suffix == ".sql" and
                patch["id"] == "security/" + path.name and patch["id"] not in seen and
                patch["id"] != "security/harden.sql", "hardening_patch_invalid")
        seen.add(patch["id"])
        require(path.is_file() and sha256(path) == patch["sha256"], "hardening_patch_checksum_mismatch")
    return manifest


def security_entries(manifest):
    return [{"id": "security/harden.sql", "path": "harden.sql", "sha256": manifest["harden_sha256"]},
            *manifest.get("hardening_patches", [])]


def apply_hardening(conn, bundle, manifest):
    for entry in security_entries(manifest):
        conn.execute((Path(bundle) / entry["path"]).read_text(encoding="utf-8"))
        conn.execute("INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s) ON CONFLICT DO NOTHING",
                     (entry["id"], entry["sha256"]))


def transaction_body(raw):
    """Remove only each original file's outer BEGIN/COMMIT; retain its SQL."""
    text = raw.lstrip("\ufeff")
    start = re.match(r"\A(?:\s|--[^\n]*(?:\n|$))*begin\s*;", text, re.I)
    end = re.search(r"\bcommit\s*;\s*\Z", text, re.I)
    require(start and end and start.end() < end.start(), "migration_transaction_wrapper_missing")
    return text[start.end():end.start()]


def target_identity(conn, *, trial=False):
    server_version(conn, target=True)
    database, user = conn.execute("SELECT current_database(),session_user").fetchone()
    require(database not in {"postgres", "template0", "template1"}, "system_database_refused")
    # Every write path is restricted, including fresh migrations. A service
    # name alone does not establish which database it actually selects.
    require(TRIAL_RE.fullmatch(database), "trial_database_name_refused" if trial else "target_database_name_refused")
    require(user == "goufayu_migrator", "migration_login_role_required")
    conn.execute("SET ROLE goufayu_owner")
    return database


def relation_names(conn):
    return [r[0] for r in conn.execute("""SELECT n.nspname||'.'||c.relname
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
      AND c.relkind IN ('r','p','S','v','m','f')
      ORDER BY 1""")]


def require_target_namespaces(conn):
    """Only our two schemas and the two reviewed extensions are acceptable."""
    for name, schema in conn.execute("""SELECT e.extname,n.nspname FROM pg_extension e
      JOIN pg_namespace n ON n.oid=e.extnamespace"""):
        require((name == "plpgsql" and schema == "pg_catalog") or
                (name == "pgcrypto" and schema in SCHEMAS), "target_unknown_extension")
    unknown = conn.execute("""SELECT 1 FROM pg_namespace WHERE nspname !~ '^pg_'
      AND nspname NOT IN ('information_schema','public','extensions') LIMIT 1""").fetchone()
    require(not unknown, "target_unknown_schema")


def business_function_names(conn):
    return {r[0] for r in conn.execute("""SELECT n.nspname||'.'||p.proname
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d JOIN pg_extension e ON e.oid=d.refobjid
        WHERE d.classid='pg_proc'::regclass AND d.refclassid='pg_extension'::regclass
        AND d.objid=p.oid AND d.deptype='e' AND e.extname IN ('pgcrypto','plpgsql'))""")}


def require_empty(conn):
    require_target_namespaces(conn)
    require(not relation_names(conn), "target_not_empty")
    require(not business_function_names(conn), "target_functions_not_empty")


def applied_prefix(manifest, applied):
    """A valid hash does not authorize skipping earlier migrations."""
    require("restore/source" not in applied, "restored_target_use_reconcile_not_fresh_migrate")
    require(bool(applied), "empty_migration_ledger_requires_review")
    entries = manifest["entries"]
    expected = {e["id"]: e["sha256"] for e in entries}
    security = {e["id"]: e["sha256"] for e in security_entries(manifest)}
    expected.update(security)
    require(all(key in expected and expected[key] == value for key, value in applied.items()),
            "applied_migration_checksum_mismatch")
    count = sum(e["id"] in applied for e in entries)
    require(count > 0 and {e["id"] for e in entries[:count]} ==
            set(applied) - set(security), "migration_ledger_not_contiguous_prefix")
    # Hardening can precede an appended target-only upgrade; it cannot precede
    # any of the historical legacy/addon/manual schema.
    if set(security) & set(applied):
        require("security/harden.sql" in applied, "hardening_patch_without_base")
        require(all(e.get("group") == "target" for e in entries[count:]),
                "hardening_before_business_schema")
    return entries[:count]


def upgrade_plan(bundle, target_service):
    """Inspect an existing ledger and aggregate impact; never emit player rows."""
    bundle = Path(bundle)
    manifest = load_bundle(bundle)
    with connect(target_service, readonly=True) as conn:
        database = target_identity(conn)
        verify_ledger_structure(conn)
        applied = dict(conn.execute("SELECT migration_id,sha256 FROM public._goufayu_migrations"))
        prefix = applied_prefix(manifest, applied)
        verify_ledger_schema(conn, bundle, prefix)
        pending = [e["id"] for e in manifest["entries"] if e["id"] not in applied]
        marker_table = conn.execute("SELECT to_regclass('public.survival_data_migrations') IS NOT NULL").fetchone()[0]
        marker = marker_table and bool(conn.execute(
            "SELECT 1 FROM public.survival_data_migrations WHERE migration_id=%s", (WOOD_MARKER,)).fetchone())
        count = conn.execute("SELECT count(*) FROM public.player_gameplay_stats WHERE wood_per_second>0").fetchone()[0]
        wood_pending = "target/202609200003_remove_default_wood_income.sql" in pending and not marker
        result = {"status": "planned", "database": database, "writes": False,
                  "pending_migrations": pending,
                  "wood_default_removal_already_recorded": bool(marker),
                  "wood_rows_to_reduce_once": count if wood_pending else 0,
                  "wood_change": "greatest(0, wood_per_second-1); affected profile_revision +1",
                  "attack_growth_existing_values_changed": False,
                  "reward_grants_changed": False,
                  "expected_runtime_rpc_count": len(RPC_SIGNATURES)}
        conn.execute("ROLLBACK")
        return result


def expected_prefix_objects(bundle, entries):
    """Presence contract for the reviewed, hash-preserved SQL history.

    This is deliberately an inventory check, not a general SQL parser. Our
    history uses public CREATE/DROP TABLE and named CREATE/DROP FUNCTION;
    it includes the retired heartbeat's literal EXECUTE 'drop function'.
    Full backup restoration separately compares columns, constraints and SQL.
    """
    tables, functions = set(), set()
    pattern = re.compile(r"\b(create(?:\s+or\s+replace)?|drop)\s+(table|function)\s+"
                         r"(?:if\s+(?:not\s+)?exists\s+)?public\.([a-z_][a-z0-9_]*)", re.I)
    for entry in entries:
        raw = (Path(bundle) / entry["path"]).read_text(encoding="utf-8")
        # SQL comments cannot create an expected object.
        raw = re.sub(r"--[^\n]*|/\*.*?\*/", "", raw, flags=re.S)
        for action, kind, name in pattern.findall(raw):
            objects = tables if kind.lower() == "table" else functions
            if action.lower().startswith("create"):
                objects.add("public." + name.lower())
            else:
                objects.discard("public." + name.lower())
    return tables | {"public." + LEDGER}, functions


def verify_ledger_structure(conn):
    actual = conn.execute("""SELECT c.relkind,r.rolname FROM pg_class c
      JOIN pg_roles r ON r.oid=c.relowner WHERE c.oid='public._goufayu_migrations'::regclass""").fetchone()
    require(actual == ('r', OWNER), "migration_ledger_relation_invalid")
    columns = conn.execute("""SELECT attname,format_type(atttypid,atttypmod),attnotnull
      FROM pg_attribute WHERE attrelid='public._goufayu_migrations'::regclass
      AND attnum>0 AND NOT attisdropped ORDER BY attnum""").fetchall()
    require(columns == [("migration_id", "text", True), ("sha256", "text", True),
                        ("applied_at", "timestamp with time zone", True)], "migration_ledger_columns_invalid")
    keys = conn.execute("""SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid='public._goufayu_migrations'::regclass AND contype='p'""").fetchall()
    require(keys == [("PRIMARY KEY (migration_id)",)], "migration_ledger_primary_key_invalid")


def verify_ledger_schema(conn, bundle, entries):
    require_target_namespaces(conn)
    tables, functions = expected_prefix_objects(bundle, entries)
    require(set(relation_names(conn)) == tables, "migration_ledger_schema_relations_mismatch")
    require(business_function_names(conn) == functions, "migration_ledger_schema_functions_mismatch")
    # Matching a name is insufficient if a user replaced a table with a view.
    invalid = conn.execute("""SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','extensions') AND c.relkind IN ('r','p','S','v','m','f')
      AND (c.relkind<>'r' OR c.relowner<>(SELECT oid FROM pg_roles WHERE rolname=%s)) LIMIT 1""", (OWNER,)).fetchone()
    require(not invalid, "migration_ledger_schema_relation_owner_or_kind")


def migrate(bundle, target_service):
    bundle = Path(bundle)
    manifest = load_bundle(bundle)
    with connect(target_service) as conn:
        database = target_identity(conn)
        conn.execute("SELECT pg_advisory_lock(719232014003)")
        require_target_namespaces(conn)
        ledger_exists = conn.execute("SELECT to_regclass('public._goufayu_migrations') IS NOT NULL").fetchone()[0]
        count = 0
        if not ledger_exists:
            require_empty(conn)
            require(bool(manifest["entries"]), "migration_bundle_empty")
            # Never leave a newly created, empty ledger after a failed first
            # migration. A pre-existing empty ledger is ambiguous and refused.
            first = manifest["entries"][0]
            with conn.transaction():
                conn.execute("CREATE SCHEMA IF NOT EXISTS extensions AUTHORIZATION goufayu_owner")
                conn.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions")
                conn.execute("""CREATE TABLE public._goufayu_migrations (
                  migration_id text PRIMARY KEY, sha256 text NOT NULL,
                  applied_at timestamptz NOT NULL DEFAULT now())""")
                conn.execute("REVOKE ALL ON public._goufayu_migrations FROM PUBLIC")
                conn.execute(transaction_body((bundle / first["path"]).read_text(encoding="utf-8")))
                conn.execute("INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)",
                             (first["id"], first["sha256"]))
            count = 1
        verify_ledger_structure(conn)
        applied = dict(conn.execute("SELECT migration_id,sha256 FROM public._goufayu_migrations"))
        prefix = applied_prefix(manifest, applied)
        verify_ledger_schema(conn, bundle, prefix)
        expected = {e["id"]: e["sha256"] for e in manifest["entries"]}
        expected.update({e["id"]: e["sha256"] for e in security_entries(manifest)})
        for entry in manifest["entries"]:
            if entry["id"] in applied:
                continue
            raw = (bundle / entry["path"]).read_text(encoding="utf-8")
            with conn.transaction():
                conn.execute(transaction_body(raw))
                conn.execute("INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)",
                             (entry["id"], entry["sha256"]))
            count += 1
        with conn.transaction():
            apply_hardening(conn, bundle, manifest)
        permissions = verify_permissions(conn)
        return {"status": "migrated", "database": database, "new_migrations": count,
                "recorded_migrations": len(expected), "permissions": permissions}


def verify_permissions(conn):
    flags = conn.execute("SELECT rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls FROM pg_roles WHERE rolname=%s", (APP,)).fetchone()
    require(flags is not None and not any(flags), "application_role_privileged")
    require(not conn.execute("SELECT 1 FROM pg_auth_members WHERE member=(SELECT oid FROM pg_roles WHERE rolname=%s)", (APP,)).fetchone(),
            "application_role_membership")
    require(not conn.execute("SELECT has_database_privilege(%s,current_database(),'CREATE') OR has_database_privilege(%s,current_database(),'TEMP')", (APP, APP)).fetchone()[0], "application_database_ddl")
    for schema, create in conn.execute("SELECT nspname,has_schema_privilege(%s,oid,'CREATE') FROM pg_namespace WHERE nspname !~ '^pg_'", (APP,)):
        require(not create, "application_schema_create")
    for name, privileges, rls in conn.execute("""SELECT c.relname,
      has_table_privilege(%s,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),c.relrowsecurity
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relkind IN ('r','p')""", (APP,)):
        require(not privileges and rls, "application_table_privilege_or_rls")
    for signature in RPC_SIGNATURES:
        require(conn.execute("SELECT has_function_privilege(%s,%s,'EXECUTE')", (APP, "public." + signature)).fetchone()[0], "application_rpc_missing")
    rows = conn.execute("""SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND has_function_privilege(%s,p.oid,'EXECUTE')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')""", (APP,)).fetchone()[0]
    require(rows == len(RPC_SIGNATURES), "application_extra_function_privilege")
    return {"rpc_count": rows, "table_access": False, "ddl": False, "role_membership": False}


def inventory(conn):
    version = server_version(conn)
    tables = []
    for schema, name, kind, rls in conn.execute("""SELECT n.nspname,c.relname,c.relkind,c.relrowsecurity
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','extensions') AND c.relkind IN ('r','p','S','v','m','f')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e')
      ORDER BY 1,2"""):
        require(schema == "public" and name in TABLES and kind in ("r", "p"), "unknown_source_relation")
        columns = conn.execute("""SELECT a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,
          pg_get_expr(d.adbin,d.adrelid) FROM pg_attribute a
          LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
          WHERE a.attrelid=%s::regclass AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum""",
          (schema + "." + name,)).fetchall()
        tables.append({"schema": schema, "name": name, "rls": rls, "columns": [list(c) for c in columns]})
    require({"survival_players", "player_gameplay_stats", "reward_grants", "player_effect_totals"}.issubset({t["name"] for t in tables}), "source_core_tables_missing")
    functions = []
    for schema, name, args, result, security, config, body in conn.execute("""SELECT n.nspname,p.proname,
      pg_get_function_identity_arguments(p.oid),pg_get_function_result(p.oid),p.prosecdef,p.proconfig,pg_get_functiondef(p.oid)
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','extensions')
      AND p.prokind IN ('f','p') AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
       AND d.objid=p.oid AND d.deptype='e') ORDER BY 1,2,3"""):
        require(schema == "public" and name in FUNCTIONS, "unknown_source_function")
        require(not FORBIDDEN_DEPENDENCY.search(body), "unsupported_function_schema_dependency")
        functions.append({"schema": schema, "name": name, "arguments": args, "returns": result,
                          "security_definer": security, "config": config, "definition": body})
    extensions = [dict(zip(("name", "version", "schema"), row)) for row in conn.execute(
        "SELECT e.extname,e.extversion,n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace ORDER BY 1")]
    for extension in extensions:
        require(extension["schema"] not in SCHEMAS or extension["name"] in {"pgcrypto", "plpgsql"}, "unsupported_exported_extension")
    deps = conn.execute("""SELECT DISTINCT target.type,target.schema,target.name
      FROM pg_depend d
      CROSS JOIN LATERAL pg_identify_object(d.classid,d.objid,d.objsubid) source
      CROSS JOIN LATERAL pg_identify_object(d.refclassid,d.refobjid,d.refobjsubid) target
      WHERE source.schema IN ('public','extensions') AND target.schema IS NOT NULL
       AND target.schema NOT IN ('public','extensions','pg_catalog','information_schema') ORDER BY 1,2,3""").fetchall()
    require(not deps, "unsupported_cross_schema_dependency")
    triggers = [dict(zip(("table", "name", "enabled", "definition"), row)) for row in conn.execute("""SELECT c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid)
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND NOT t.tgisinternal ORDER BY 1,2""")]
    for trigger in triggers:
        require(not FORBIDDEN_DEPENDENCY.search(trigger["definition"]), "unsupported_trigger_dependency")
    policies = conn.execute("SELECT schemaname,tablename,policyname,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname IN ('public','extensions')").fetchall()
    require(not policies, "unexpected_rls_policy_requires_review")
    constraints = [list(row) for row in conn.execute("""SELECT c.relname,k.conname,k.contype,pg_get_constraintdef(k.oid)
      FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' ORDER BY 1,2""")]
    indexes = [list(row) for row in conn.execute("SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY 1,2")]
    roles = [dict(zip(("name", "login", "superuser", "createdb", "createrole", "replication", "bypassrls"), row))
             for row in conn.execute("SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls FROM pg_roles ORDER BY 1")]
    # Current approved schema has no sequences. Fail closed if one appears so
    # non-MVCC sequence values cannot silently escape snapshot verification.
    sequences = conn.execute("SELECT schemaname,sequencename FROM pg_sequences WHERE schemaname IN ('public','extensions')").fetchall()
    require(not sequences, "new_sequence_requires_snapshot_strategy_review")
    return {"server_version": version, "tables": tables, "functions": functions,
            "triggers": triggers, "extensions": extensions, "roles": roles,
            "sequences": [], "policies": [], "cross_schema_dependencies": [],
            "constraints": constraints, "indexes": indexes}


def fingerprint_tables(conn, tables, *, original_columns=False):
    result = {}
    for item in tables:
        table = quote_ident(item["schema"]) + "." + quote_ident(item["name"])
        digest, count = hashlib.sha256(), 0
        # Stream rows in canonical textual order without retaining player data.
        relation = table
        if original_columns:
            columns = ",".join(quote_ident(column[0]) for column in item["columns"])
            relation = "(SELECT " + columns + " FROM " + table + ")"
        with conn.cursor(name="goufayu_fingerprint") as cursor:
            cursor.execute('SELECT row_to_json(t)::text FROM ' + relation +
                           ' t ORDER BY row_to_json(t)::text COLLATE "C"')
            for row in cursor:
                encoded = row[0].encode("utf-8")
                digest.update(len(encoded).to_bytes(8, "big"))
                digest.update(encoded)
                count += 1
        result[item["schema"] + "." + item["name"]] = {"rows": count, "sha256": digest.hexdigest()}
    return result


def private_directory(path):
    path = Path(path)
    require(not path.exists(), "output_directory_already_exists")
    path.mkdir(parents=True, mode=0o700)
    return path


def audit(source_service, output, source_role=None):
    output = private_directory(output)
    with connect(source_service, readonly=True, role=source_role) as conn:
        value = inventory(conn)
        write_json(output / "inventory.json", value)
        conn.execute("ROLLBACK")
    return {"status": "audited", "tables": len(value["tables"]), "functions": len(value["functions"])}


def export(source_service, output, pg_bin=None, source_role=None):
    dump_bin, restore_bin = binary("pg_dump", pg_bin), binary("pg_restore", pg_bin)
    output = private_directory(output)
    with connect(source_service, readonly=True, role=source_role) as conn:
        value = inventory(conn)
        snapshot = conn.execute("SELECT pg_export_snapshot()").fetchone()[0]
        require(re.fullmatch(r"[A-Fa-f0-9-]+", snapshot), "snapshot_format_invalid")
        argv = [dump_bin, "--dbname=service=" + source_service, "--no-password", "--format=custom",
                "--schema=public", "--schema=extensions", "--extension=pgcrypto",
                "--no-owner", "--no-acl", "--no-publications", "--no-subscriptions",
                "--snapshot=" + snapshot, "--file=" + str(output / "database.dump")]
        if source_role:
            argv.append("--role=" + source_role)
        run_client(argv, readonly=True)
        fingerprints = fingerprint_tables(conn, value["tables"])
        write_json(output / "inventory.json", value)
        # DDL is exported for review; it contains function definitions, not row data.
        run_client([restore_bin, "--schema-only", "--no-owner", "--no-acl",
                    "--file=" + str(output / "schema.sql"), str(output / "database.dump")])
        dump_hash = sha256(output / "database.dump")
        manifest = {"format": 1, "created_at": datetime.now(timezone.utc).isoformat(),
                    "postgres_client_major": 17, "snapshot": snapshot,
                    "database_dump_sha256": dump_hash, "inventory_sha256": sha256(output / "inventory.json"),
                    "schema_sha256": sha256(output / "schema.sql"), "tables": fingerprints,
                    "sequences": {}, "source_writes": False, "same_exported_snapshot": True,
                    "row_hash_format": "sha256(length8be+utf8(row_to_json),ORDER BY C)"}
        write_json(output / "backup_manifest.json", manifest)
        conn.execute("ROLLBACK")
    return {"status": "exported", "tables": len(fingerprints), "dump_sha256": dump_hash,
            "same_exported_snapshot": True}


def trial_restore(target_service, backup, pg_bin=None):
    restore_bin = binary("pg_restore", pg_bin)
    backup = Path(backup)
    manifest = json.loads((backup / "backup_manifest.json").read_text(encoding="utf-8"))
    require(manifest.get("format") == 1 and manifest.get("same_exported_snapshot") is True, "backup_manifest_invalid")
    require(sha256(backup / "database.dump") == manifest["database_dump_sha256"], "backup_checksum_mismatch")
    require(sha256(backup / "inventory.json") == manifest["inventory_sha256"], "inventory_checksum_mismatch")
    require(sha256(backup / "schema.sql") == manifest["schema_sha256"], "schema_checksum_mismatch")
    with connect(target_service) as conn:
        database = target_identity(conn, trial=True)
        # Advisory lock prevents our own tooling from racing a restore/migration.
        conn.execute("SELECT pg_advisory_lock(719232014003)")
        require_empty(conn)
        # --no-acl restores functions with PostgreSQL's default PUBLIC EXECUTE.
        # Deny access to their schema until explicit reconcile/hardening grants
        # only the runtime RPCs. Never expose that intermediate restore state.
        conn.execute("REVOKE USAGE ON SCHEMA public FROM PUBLIC,goufayu_app")
        # initdb/bootstrap creates an empty public schema; a non-default source
        # schema owner makes pg_dump explicitly CREATE it again. Remove ONLY
        # that empty schema in the separately named, verified-empty trial DB.
        # No CASCADE/--clean is used. Any extension dependency rejects the drop.
        creates_public = re.search(r'^CREATE SCHEMA (?:public|"public");\s*$',
                                   (backup / "schema.sql").read_text(encoding="utf-8"), re.M)
        if creates_public:
            conn.execute("DROP SCHEMA public")
        try:
            run_client([restore_bin, "--dbname=service=" + target_service, "--no-password",
                        "--no-owner", "--no-acl", "--role=" + OWNER,
                        "--single-transaction", "--exit-on-error", str(backup / "database.dump")])
        except Exception:
            if creates_public:
                conn.execute("CREATE SCHEMA IF NOT EXISTS public AUTHORIZATION goufayu_owner")
                conn.execute("REVOKE ALL ON SCHEMA public FROM PUBLIC,goufayu_app")
            raise
        conn.execute("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY")
        value = inventory(conn)
        actual = fingerprint_tables(conn, value["tables"])
        require(actual == manifest["tables"], "restored_table_fingerprint_mismatch")
        original = json.loads((backup / "inventory.json").read_text(encoding="utf-8"))
        require(value["functions"] == original["functions"], "restored_function_mismatch")
        require(value["triggers"] == original["triggers"], "restored_trigger_mismatch")
        require(value["tables"] == original["tables"], "restored_table_schema_mismatch")
        require(value["constraints"] == original["constraints"] and value["indexes"] == original["indexes"],
                "restored_constraint_or_index_mismatch")
        conn.execute("ROLLBACK")
        report = {"status": "PASS", "database": database, "tables": len(actual),
                  "data_fingerprints_match": True, "function_definitions_match": True,
                  "triggers_match": True, "sequences": {}, "source_writes": False,
                  "constraints_and_indexes_match": True,
                  "runtime_acl_applied": False,
                  "note": "Full-schema restore preserves source business logic. Apply reviewed target hardening separately before runtime use."}
        write_json(backup / (database + "_restore_verification.json"), report)
        return report


def reconcile(target_service, backup, bundle):
    """Explicitly adopt a verified restored source; never replay legacy drops."""
    backup, bundle = Path(backup), Path(bundle)
    migrations = load_bundle(bundle)
    exported = json.loads((backup / "backup_manifest.json").read_text(encoding="utf-8"))
    original = json.loads((backup / "inventory.json").read_text(encoding="utf-8"))
    require(sha256(backup / "database.dump") == exported["database_dump_sha256"] and
            sha256(backup / "inventory.json") == exported["inventory_sha256"], "reconcile_backup_checksum_mismatch")
    with connect(target_service) as conn:
        database = target_identity(conn, trial=True)
        conn.execute("SELECT pg_advisory_lock(719232014003)")
        report_path = backup / (database + "_restore_verification.json")
        require(report_path.is_file(), "successful_trial_restore_report_required")
        report = json.loads(report_path.read_text(encoding="utf-8"))
        require(report.get("status") == "PASS" and report.get("database") == database,
                "trial_restore_report_invalid")
        # Keep old content read and all target changes atomic. Applications must
        # remain stopped; SHARE ROW EXCLUSIVE locks prevent concurrent writes.
        with conn.transaction():
            conn.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
            for table in original["tables"]:
                conn.execute("LOCK TABLE " + quote_ident(table["schema"]) + "." + quote_ident(table["name"]) + " IN SHARE ROW EXCLUSIVE MODE")
            before = fingerprint_tables(conn, original["tables"], original_columns=True)
            require(before == exported["tables"], "restored_data_changed_before_reconcile")
            actual = inventory(conn)
            require({"online_time_sessions", "online_time_idempotency", "star_blessing_reward_definition_sets",
                     "star_blessing_reward_definitions", "out_of_match_reward_idempotency"}.issubset(
                         {t["name"] for t in actual["tables"]}), "source_legacy_baseline_incomplete")
            conn.execute("""CREATE TABLE IF NOT EXISTS public._goufayu_migrations (
              migration_id text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())""")
            previous = dict(conn.execute("SELECT migration_id,sha256 FROM public._goufayu_migrations"))
            # A nightly backup of an already-adopted database legitimately
            # contains an older restore marker. Only the marker of THIS exact
            # archive identifies a repeated reconcile on this destination.
            require(previous.get("restore/source") != exported["database_dump_sha256"], "reconcile_already_completed")
            applied = []
            # These additive/idempotent migrations do not seed, drop legacy
            # tables, or rewrite immutable reward definitions on restored data.
            for entry in migrations["entries"]:
                if entry.get("group") not in {"addon", "manual", "target"}:
                    continue
                if entry["id"] in previous:
                    require(previous[entry["id"]] == entry["sha256"], "restored_ledger_checksum_mismatch")
                    continue
                conn.execute(transaction_body((bundle / entry["path"]).read_text(encoding="utf-8")))
                conn.execute("INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)",
                             (entry["id"], entry["sha256"]))
                applied.append(entry["id"])
            for entry in security_entries(migrations):
                require(entry["id"] not in previous or previous[entry["id"]] == entry["sha256"],
                        "restored_hardening_checksum_mismatch")
            apply_hardening(conn, bundle, migrations)
            if previous.get("restore/source"):
                conn.execute("INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s) ON CONFLICT DO NOTHING",
                             ("restore/history/" + previous["restore/source"], previous["restore/source"]))
            conn.execute("INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s) "
                         "ON CONFLICT(migration_id) DO UPDATE SET sha256=excluded.sha256,applied_at=now()",
                         ("restore/source", exported["database_dump_sha256"]))
            retained = [t for t in original["tables"] if t["name"] != LEDGER]
            after = fingerprint_tables(conn, retained, original_columns=True)
            require(after == {k: v for k, v in before.items() if k != "public." + LEDGER},
                    "existing_data_modified_during_reconcile")
            permission = verify_permissions(conn)
        report = {"status": "PASS", "database": database, "new_target_migrations": applied,
                  "old_columns_and_rows_preserved": True, "original_source_writes": False,
                  "permissions": permission, "source_dump_sha256": exported["database_dump_sha256"]}
        write_json(backup / (database + "_reconcile_verification.json"), report)
        return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", help="Directory containing PostgreSQL 17 clients")
    commands = parser.add_subparsers(dest="command", required=True)
    p = commands.add_parser("collect")
    p.add_argument("--legacy-root", required=True)
    p.add_argument("--addon-root", required=True)
    p.add_argument("--destination", required=True)
    p = commands.add_parser("migrate")
    p.add_argument("--bundle", required=True)
    p.add_argument("--target-service", required=True)
    p = commands.add_parser("plan-upgrade")
    p.add_argument("--bundle", required=True)
    p.add_argument("--target-service", required=True)
    for command in ("audit", "export"):
        p = commands.add_parser(command)
        p.add_argument("--source-service", required=True)
        p.add_argument("--output", required=True)
        p.add_argument("--source-role", choices=[OWNER])
    p = commands.add_parser("trial-restore")
    p.add_argument("--target-service", required=True)
    p.add_argument("--backup", required=True)
    p = commands.add_parser("reconcile")
    p.add_argument("--target-service", required=True)
    p.add_argument("--backup", required=True)
    p.add_argument("--bundle", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "collect":
            result = collect(args.legacy_root, args.addon_root, args.destination)
        elif args.command == "migrate":
            result = migrate(args.bundle, args.target_service)
        elif args.command == "plan-upgrade":
            result = upgrade_plan(args.bundle, args.target_service)
        elif args.command == "audit":
            result = audit(args.source_service, args.output, args.source_role)
        elif args.command == "export":
            result = export(args.source_service, args.output, args.pg_bin, args.source_role)
        elif args.command == "trial-restore":
            result = trial_restore(args.target_service, args.backup, args.pg_bin)
        else:
            result = reconcile(args.target_service, args.backup, args.bundle)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Refused as exc:
        print(json.dumps({"status": "REFUSED", "reason": str(exc)}), file=sys.stderr)
    except Exception as exc:
        # Never print exception/SQL/DSN contents that may hold secrets or data.
        print(json.dumps({"status": "ERROR", "type": type(exc).__name__,
                          "sqlstate": getattr(exc, "sqlstate", None)}), file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
