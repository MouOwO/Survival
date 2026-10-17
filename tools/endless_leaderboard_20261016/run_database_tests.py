"""Run ranking SQL on a loopback-only synthetic portable PostgreSQL instance."""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'output/endless_leaderboard_20261016/postgres'
BIN = ROOT / 'output/video_shop_20261015/postgres_test/portable/pgsql/bin'
sys.path.insert(0, str(ROOT / 'output/video_shop_20261015/deps'))
import psycopg


def run(command):
    result = subprocess.run([str(x) for x in command], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace',
        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), timeout=60)
    if result.returncode:
        raise RuntimeError(result.stdout)
    return result.stdout


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    data = WORK / 'data'
    if not (data / 'PG_VERSION').exists():
        run([BIN / 'initdb.exe', '-D', data, '-U', 'postgres', '-A', 'trust',
             '--no-locale', '-E', 'UTF8'])
    started = False
    try:
        if not (data / 'postmaster.pid').exists():
            # pg_ctl starts a hidden helper; no OS service or public listener.
            with (WORK / 'startup.log').open('w', encoding='utf-8') as log:
                process = subprocess.run([str(BIN / 'pg_ctl.exe'), '-D', str(data), '-l',
                    str(WORK / 'postgres.log'), '-o', '-h 127.0.0.1 -p 54628 -F', '-w', 'start'],
                    stdout=log, stderr=subprocess.STDOUT, timeout=45,
                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
                if process.returncode:
                    raise RuntimeError('local_postgres_start_failed')
            started = True
        with psycopg.connect('host=127.0.0.1 port=54628 user=postgres dbname=postgres') as conn:
            for role in ('anon', 'authenticated', 'service_role', 'goufayu_app'):
                conn.execute('DO $$ BEGIN CREATE ROLE ' + role + '; EXCEPTION WHEN duplicate_object THEN NULL; END $$;')
            conn.execute('CREATE TABLE IF NOT EXISTS public.survival_players(account_id text PRIMARY KEY,profile_revision bigint NOT NULL DEFAULT 1)')
            conn.execute("CREATE TABLE IF NOT EXISTS public.player_archive_state(account_id text PRIMARY KEY REFERENCES public.survival_players,archive jsonb NOT NULL DEFAULT '{}'::jsonb)")
            historical = hashlib.sha256(b'endless-ranking-local-pre-migration').hexdigest()
            conn.execute('INSERT INTO public.survival_players(account_id) VALUES(%s) ON CONFLICT DO NOTHING', (historical,))
            conn.execute("INSERT INTO public.player_archive_state(account_id,archive) VALUES(%s,'{\"endless_best_wave\":123,\"endless_score\":456}') ON CONFLICT DO NOTHING", (historical,))
            conn.commit()
            migration = (ROOT / 'server/migrations/202610160001_endless_leaderboard.sql').read_text(encoding='utf-8')
            conn.execute(migration)
            conn.commit()
            # Idempotency of this exact migration, including stable public IDs.
            old_id = conn.execute('SELECT entry_id FROM public.archive_leaderboard_identities WHERE account_id=%s', (historical,)).fetchone()[0]
            conn.commit()
            conn.execute(migration)
            conn.commit()
            assert conn.execute('SELECT entry_id FROM public.archive_leaderboard_identities WHERE account_id=%s', (historical,)).fetchone()[0] == old_id
            spec = importlib.util.spec_from_file_location('ranking_database_checks', ROOT / 'server/tests/test_endless_leaderboard_database.py')
            checks = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(checks)
            result = checks.run_checks(conn)
            result.update(postgresql=conn.execute('SELECT version()').fetchone()[0],
                          historical_save_seeded=True, migration_idempotent=True,
                          scope='isolated_loopback_postgresql_only')
            conn.rollback()
            report = ROOT / 'design_refs/endless_leaderboard_20261016/validation/server_database.json'
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
            print(json.dumps(result, ensure_ascii=False))
    finally:
        if started:
            run([BIN / 'pg_ctl.exe', '-D', data, '-m', 'fast', '-w', 'stop'])


if __name__ == '__main__':
    main()
