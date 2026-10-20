"""Run the real mode migration in a NEW localhost-only PostgreSQL 17 cluster.

Uses synthetic profiles and a minimal SQL fixture for the existing profile RPC.
Never connects to an existing database or reads a service file. The private
cluster is stopped in finally; its test-only files remain under output for audit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import socket
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ("202609230001_match_profile_sessions.sql", "202610170001_rich_match_mode.sql",
              "202610200002_archive_match_modes.sql", "202610200004_mode_unlock_chain.sql")


def run(pg_bin: Path):
    base = (ROOT / "output/mode_progression_20261020/database").resolve()
    base.mkdir(parents=True, exist_ok=True)
    # Inherit the project output ACL. Python 3.14's private mkdtemp ACL prevents
    # PostgreSQL's deliberately restricted Windows child token from opening it.
    work = (base / ("isolated_" + uuid.uuid4().hex[:12])).resolve()
    work.mkdir()
    assert work.is_relative_to(base), "test_cluster_path_outside_output"
    cluster = work / "cluster"
    log = []

    def command(name, args, *, timeout=30):
        # PostgreSQL's detached Windows process can retain a pipe handle. A
        # private file prevents communicate() waiting for the running server.
        capture = work / ("command_" + str(len(log)) + ".log")
        with capture.open("wb") as stream:
            process = subprocess.run([str(pg_bin / (name + ".exe")), *map(str, args)],
                cwd=work, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        output = capture.read_bytes()
        log.append({"program": name, "returncode": process.returncode})
        if process.returncode:
            # This cluster contains synthetic data only. Keep engine diagnostics
            # in its own output folder instead of printing process arguments.
            (work / (name + "_failure.log")).write_bytes(output)
            raise RuntimeError(name + "_failed")
        return output.decode("utf-8", errors="replace")

    version = command("postgres", ["--version"])
    assert " 17." in version, "postgresql_17_required"
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    command("initdb", ["-D", cluster, "-U", "mode_test_admin", "-A", "trust", "--no-locale", "--encoding=UTF8"])
    started = False
    try:
        command("pg_ctl", ["-D", cluster, "-l", work / "postgres.log", "-o",
                            "-h 127.0.0.1 -p " + str(port) + " -F", "-w", "-t", "15", "start"])
        started = True
        connection = ["-X", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", str(port),
                      "-U", "mode_test_admin", "-d", "postgres", "-q"]

        def sql(name, source):
            path = work / (name + ".sql")
            path.write_text(source, encoding="utf-8", newline="\n")
            command("psql", [*connection, "-f", path])

        sql("fixture", """
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE goufayu_app;
CREATE SCHEMA extensions;
CREATE TABLE public.survival_players(account_id text PRIMARY KEY, profile jsonb NOT NULL);
CREATE TABLE public.player_gameplay_stats(player_id text PRIMARY KEY);
CREATE FUNCTION public.fishing_profile_json(p_account text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER
 SET search_path=pg_catalog,public,pg_temp AS 'SELECT profile FROM public.survival_players WHERE account_id=p_account';
INSERT INTO public.survival_players VALUES(repeat('a',64), '{"save":{"archive":{"clear_counts":{"n10":1}}}}');
INSERT INTO public.player_gameplay_stats VALUES(repeat('a',64));
""")
        for name in MIGRATIONS[:2]:
            command("psql", [*connection, "-f", ROOT / "server/aliyun/database/target" / name])
        sql("historical", """
SET ROLE goufayu_app;
SELECT public.match_profile_login(repeat('a',64),'historical-rich-session','rich','{"initial_wood":777}');
RESET ROLE;
CREATE TABLE public.fixture_old_sessions AS SELECT * FROM public.match_profile_sessions;
""")
        for name in MIGRATIONS[2:]:
            migration = ROOT / "server/aliyun/database/target" / name
            command("psql", [*connection, "-f", migration])
        sql("preserve_history", """
DO $$ BEGIN
 IF EXISTS((SELECT * FROM public.fixture_old_sessions) EXCEPT (SELECT * FROM public.match_profile_sessions))
 OR EXISTS((SELECT * FROM public.match_profile_sessions) EXCEPT (SELECT * FROM public.fixture_old_sessions))
 THEN RAISE EXCEPTION 'historical_session_changed'; END IF;
END $$;
UPDATE public.survival_players SET profile='{"save":{"archive":{"clear_counts":{"n10":99},"standard_clear_counts":{}}}}';
SET ROLE goufayu_app;
DO $$ BEGIN
 IF (public.match_profile_login(repeat('a',64),'explicit-empty-standard','rich','{}')->>'error') IS DISTINCT FROM 'rich_mode_locked'
 THEN RAISE EXCEPTION 'explicit_empty_provenance_fell_back'; END IF;
 IF has_table_privilege(current_user,'public.match_profile_sessions','SELECT')
 THEN RAISE EXCEPTION 'private_session_table_exposed'; END IF;
END $$;
RESET ROLE;
UPDATE public.survival_players SET profile='{"save":{"archive":{"standard_clear_counts":{"n10":1},"rich_clear_counts":{},"cold_clear_counts":{}}}}';
""")
        for mode, parent in (("rich", "standard"), ("cold", "rich"), ("scourge", "cold")):
            if mode != "rich":
                for index, invalid in enumerate((True, "1", 0, -1, 1.5)):
                    archive = {parent + "_clear_counts": {"n10": invalid}}
                    profile = json.dumps({"save": {"archive": archive}}, separators=(",", ":"))
                    sql(mode + "_invalid_" + str(index), "UPDATE public.survival_players SET profile='" + profile + "';\n" + f"""
SET ROLE goufayu_app;
DO $$ BEGIN
 IF (public.match_profile_login(repeat('a',64),'{mode}-invalid-{index}','{mode}','{{}}')->>'error') IS DISTINCT FROM '{mode}_mode_locked'
 THEN RAISE EXCEPTION 'invalid_predecessor_admitted'; END IF;
END $$;
RESET ROLE;
""")
            archive = {parent + "_clear_counts": {"n10": 1}}
            profile = json.dumps({"save": {"archive": archive}}, separators=(",", ":"))
            sql(mode + "_admission", "UPDATE public.survival_players SET profile='" + profile + "';\n" + f"""
SET ROLE goufayu_app;
DO $$ DECLARE initial jsonb; replay jsonb; BEGIN
 initial:=public.match_profile_login(repeat('a',64),'{mode}-durable-session','{mode}','{{"initial_wood":777}}');
 IF (initial->>'mode') IS DISTINCT FROM '{mode}' OR (initial->>'ok') IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'real_mode_not_durable'; END IF;
 replay:=public.match_profile_login(repeat('a',64),'{mode}-durable-session','{mode}','{{"initial_wood":999}}');
 IF (replay->'baseline') IS DISTINCT FROM (initial->'baseline') OR (replay->'defaults') IS DISTINCT FROM (initial->'defaults')
 THEN RAISE EXCEPTION 'retry_replaced_baseline'; END IF;
 IF (public.match_profile_login(repeat('a',64),'{mode}-durable-session','standard','{{}}')->>'error') IS DISTINCT FROM 'match_mode_locked'
 THEN RAISE EXCEPTION 'existing_mode_rebound'; END IF;
END $$;
RESET ROLE;
""")
        report = {"status": "PASS", "kind": "real_postgresql_17_isolated_cluster",
            "postgres_version": version.strip(), "external_connections": 0, "existing_accounts_read": 0,
            "checks": ["historical rows unchanged", "explicit empty provenance never falls back",
                       "strict predecessor N10 validation", "real mode durable", "baseline retry immutable",
                       "session mode cannot rebind", "application role cannot read private session table"],
            "migration_sha256": hashlib.sha256(migration.read_bytes()).hexdigest(), "processes": log,
            "cluster_stopped": False}
    finally:
        if started or (cluster / "postmaster.pid").exists():
            command("pg_ctl", ["-D", cluster, "-m", "fast", "-w", "-t", "15", "stop"])
    report["cluster_stopped"] = True
    report_path = work / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "report": str(report_path.relative_to(ROOT)),
                      "cluster_stopped": True, "checks": len(report["checks"])}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", type=Path, required=True)
    run(parser.parse_args().pg_bin.resolve())
