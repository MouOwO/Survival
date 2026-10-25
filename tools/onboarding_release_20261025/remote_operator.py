"""Pinned, additive onboarding release operator; invoked by deploy.py only.

No credentials or account rows are printed. SQL trials and account probes are
rolled back. Activation preserves all existing reward configuration and rows.
"""
from pathlib import Path, PurePosixPath
import base64
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.request

sha = lambda raw: hashlib.sha256(raw).hexdigest()
canonical = lambda value: json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def need(condition, code):
    if not condition:
        raise RuntimeError(code)


STAGE = Path(STAGE)
need(STAGE.parent == Path('/root/goufayu_upload') and not STAGE.is_symlink(), 'invalid_stage')
P = json.loads((STAGE / 'plan.json').read_bytes())
OLD = Path('/opt/goufayu/releases') / P['archive_release']
NEW = OLD.parent / P['new_release']
SAFE = OLD.parent / P['rollback_release']
CURRENT = OLD.parent / 'current'
PAY = Path('/opt/goufayu/payments') / P['payment_release']
sys.path.insert(0, str(PAY))
from deploy import connection, backup


def safe(root, name):
    rel = PurePosixPath(name)
    need(bool(name) and not rel.is_absolute() and '..' not in rel.parts and ':' not in name
         and '\\' not in name and rel.as_posix() == name, 'unsafe_release_path')
    need(all(not root.joinpath(*rel.parts[:i]).is_symlink() for i in range(1, len(rel.parts)+1)), 'release_symlink')
    return root / name


def save(name, data):
    dest = safe(STAGE, name + '.json')
    need(not dest.exists(), 'report_already_exists')
    dest.write_bytes(canonical(data)); dest.chmod(0o600)
    return data


def payment_pin():
    need(Path('/opt/goufayu/payments/current').resolve() == PAY, 'payment_pointer_drift')
    need(sha((PAY / 'manifest.json').read_bytes()) == P['payment_manifest_sha256'], 'payment_manifest_drift')
    pid = subprocess.check_output(['systemctl', 'show', '--property=MainPID', '--value', 'goufayu-payment.service'], text=True).strip()
    need(pid == P['payment_pid'], 'payment_process_changed')


def manifest(root):
    value = json.loads((root / 'release_manifest.json').read_bytes())
    need(value['release'] == root.name, 'manifest_release_mismatch')
    for name, digest in value['files'].items():
        need(sha(safe(root, name).read_bytes()) == digest, 'release_file_drift')
    return value


def db_state(conn):
    need(conn.info.dbname == 'goufayu_test', 'database_scope_changed')
    functions = {name: sha(body.encode()) for name, body in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY 1")}
    ledger = dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations ORDER BY 1'))
    tables = [r[0]+'.'+r[1] for r in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2")]
    return dict(functions=functions, ledger=ledger, tables=tables)


def baseline(conn):
    need(CURRENT.resolve() == OLD, 'archive_pointer_drift'); payment_pin()
    need(sha((OLD / 'release_manifest.json').read_bytes()) == P['archive_manifest_sha256'], 'parent_manifest_drift')
    manifest(OLD)
    for name, digest in P['all_backend_hashes'].items():
        need(sha(safe(OLD, name).read_bytes()) == digest, 'parent_backend_drift')
    state = db_state(conn)
    for key in ('ledger', 'functions', 'tables'):
        need(state[key] == P['baseline'][key], 'pinned_database_' + key + '_drift')
    return state


def rows_state(conn):
    from psycopg import sql
    result = {}
    for schema, table in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2"):
        result[schema+'.'+table] = conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(schema), sql.Identifier(table))).fetchone()
    return result


def sql_body(raw, wrapped):
    source = raw.decode('utf-8-sig')
    if not wrapped:
        need(not re.search(r'(?im)^\s*(BEGIN|COMMIT)\s*;', source), 'unexpected_transaction_wrapper')
        return source
    start = re.match(r'\A(?:\s|--[^\n]*(?:\n|$))*begin\s*;', source, re.I)
    end = re.search(r'\bcommit\s*;\s*\Z', source, re.I)
    need(start and end and start.end() < end.start(), 'migration_wrapper_invalid')
    return source[start.end():end.start()]


def apply(conn):
    conn.execute('SET LOCAL ROLE goufayu_owner')
    conn.execute('SELECT pg_advisory_xact_lock(719232014021)')
    conn.execute('LOCK TABLE public._goufayu_migrations IN SHARE ROW EXCLUSIVE MODE')
    before = db_state(conn)
    old_ledger_rows = dict(conn.execute('SELECT migration_id,to_jsonb(t) FROM public._goufayu_migrations t'))
    need(before['ledger'] == P['ledger'], 'historical_ledger_changed')
    for migration in P['migrations']:
        raw = safe(STAGE / 'overlay', migration['path']).read_bytes()
        need(sha(raw) == migration['sha256'], 'migration_digest_changed')
        need(migration['id'] not in before['ledger'], 'migration_already_applied')
        conn.execute(sql_body(raw, migration['transaction_wrapper']))
        conn.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)', (migration['id'], migration['sha256']))
    after = db_state(conn)
    current_ledger_rows = dict(conn.execute('SELECT migration_id,to_jsonb(t) FROM public._goufayu_migrations t'))
    need(all(current_ledger_rows.get(k) == v for k, v in old_ledger_rows.items()), 'old_ledger_row_modified')
    need(after['ledger'] == {**before['ledger'], **{m['id']: m['sha256'] for m in P['migrations']}}, 'historical_ledger_modified')
    need(all(after['functions'].get(k) == v for k, v in before['functions'].items()), 'old_sql_function_modified')
    need(set(after['functions']) - set(before['functions']) == {'initialize_player_onboarding()', 'onboarding_state(text,text)', 'onboarding_finish(text,text,text)'}, 'unexpected_sql_functions')
    need(set(after['tables']) - set(before['tables']) == {'public.player_onboarding_state'}, 'unexpected_sql_tables')
    need(conn.execute('SELECT count(*) FROM public.player_onboarding_state').fetchone()[0] == 0, 'legacy_accounts_backfilled')
    return dict(new_migrations=len(P['migrations']), new_functions=3, new_tables=1, legacy_accounts_modified=0)


def check_rows(before, after):
    need(set(after) == set(before) | {'public.player_onboarding_state'}, 'table_inventory_changed')
    need(all(after[key] == value for key, value in before.items() if key != 'public._goufayu_migrations'), 'existing_business_rows_modified')
    need(after['public.player_onboarding_state'][0] == 0, 'probe_rows_leaked')


def runtime_probe(conn):
    legacy = conn.execute("SELECT account_id FROM public.survival_players p WHERE NOT EXISTS(SELECT 1 FROM public.player_onboarding_state s WHERE s.account_id=p.account_id) LIMIT 1").fetchone()
    need(legacy is not None, 'legacy_account_probe_unavailable')
    spec = importlib.util.spec_from_file_location('onboarding_release_runtime_probe', STAGE / 'runtime_probe.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module.run(conn, NEW, legacy[0])


def prepare():
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    parent = manifest(OLD)
    for target, overlay, folder in ((NEW, P['overlay'], 'overlay'), (SAFE, P['safe_overlay'], 'safe_overlay')):
        # Include backend sources added by earlier audited deployments even if
        # the historical manifest did not enumerate them at that time.
        originals = {**parent['files'], **P['all_backend_hashes']}
        value = copy.deepcopy(parent); value['files'] = {**originals, **overlay}
        value.update(release=target.name, onboarding_parent=OLD.name, onboarding_allowlist_only_rollback=target == SAFE)
        if target.exists():
            need(not target.is_symlink() and manifest(target) == value, 'candidate_already_exists_or_changed')
            continue
        target.mkdir(mode=0o755)
        for name, digest in originals.items():
            source = safe(OLD, name); need(sha(source.read_bytes()) == digest, 'copy_source_drift')
            dest = safe(target, name); dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, dest); dest.chmod(source.stat().st_mode & 0o777)
        (target / '.venv').symlink_to(OLD / '.venv', target_is_directory=True)
        for name, digest in overlay.items():
            source = safe(STAGE / folder, name); need(sha(source.read_bytes()) == digest, 'overlay_digest_changed')
            dest = safe(target, name); dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, dest); dest.chmod(0o644)
        (target / 'release_manifest.json').write_bytes(canonical(value)); manifest(target)
        need((target / 'addon/server/bundles/current.json').read_bytes() == (OLD / 'addon/server/bundles/current.json').read_bytes(), 'reward_pointer_changed')
    return save('prepared', dict(ok=True, phase='PREPARED_NOT_ACTIVATED', release=NEW.name, safe_release=SAFE.name, database_committed=False))


def validate():
    need((STAGE / 'prepared.json').is_file(), 'prepare_required'); manifest(NEW); manifest(SAFE)
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET LOCAL lock_timeout='5s'"); conn.execute("SET LOCAL statement_timeout='60s'")
            baseline(conn); before = rows_state(conn); result = apply(conn); conn.execute('RESET ROLE')
            checks = runtime_probe(conn); check_rows(before, rows_state(conn))
        finally:
            conn.rollback()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    return save('validated', dict(ok=True, phase='VALIDATED_ROLLED_BACK', rolled_back=True, probes=checks, **result))


def control(action):
    need(action in ('stop', 'start'), 'invalid_service_action')
    result = subprocess.run(['systemctl', action, 'goufayu-api.service'], capture_output=True, timeout=40)
    need(result.returncode == 0, 'archive_service_action_failed')


def switch(target):
    need(target in (OLD, NEW, SAFE) and CURRENT.resolve() in (OLD, NEW, SAFE), 'pointer_ownership_changed')
    temporary = CURRENT.with_name('current.onboarding.' + secrets.token_hex(8))
    temporary.symlink_to(target, target_is_directory=True); os.replace(temporary, CURRENT)


def health():
    for attempt in range(25):
        try:
            for port in (8765, 8766):
                with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health', timeout=2) as response:
                    need(json.load(response).get('ok') is True, 'health_unready')
            return
        except Exception:
            if attempt == 24:
                raise
            time.sleep(0.5)


def quiesce_backup():
    need(json.loads((STAGE / 'validated.json').read_bytes())['rolled_back'], 'validation_required')
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    control('stop')
    try:
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            backup()
        record = json.loads(captured.getvalue().splitlines()[-1])
        path = Path(record['local_backup'])
        need(path.parent == Path('/var/backups/goufayu-payment') and path.is_file() and not path.is_symlink(), 'backup_path_invalid')
        digest = sha(path.read_bytes())
        need(path.with_suffix('.sha256').read_text().strip() == digest, 'backup_digest_mismatch')
        return save('private_backup', dict(ok=True, phase='QUIESCED_BACKUP_READY', path=str(path), sha256=digest, size=path.stat().st_size, at=time.time(), includes_game_and_payments=True))
    except Exception:
        control('start'); health()
        raise


def resume():
    need(CURRENT.resolve() == OLD, 'resume_pointer_changed')
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    control('start'); health()
    return dict(ok=True, phase='OLD_SERVICE_RESUMED_NO_SQL_CHANGE')


def activate():
    need((STAGE / 'private_backup.json').is_file(), 'backup_required')
    committed = False
    try:
        ack = json.loads((STAGE / 'offsite_ack.json').read_bytes())
        saved = json.loads((STAGE / 'private_backup.json').read_bytes())
        need(ack['sha256'] == saved['sha256'] and ack['encrypted_verified'], 'offsite_backup_not_verified')
        need(sha(Path(saved['path']).read_bytes()) == saved['sha256'], 'private_backup_changed')
        need(time.time() - saved['at'] < 600, 'quiesced_backup_expired')
        need(subprocess.check_output(['systemctl', 'show', '--property=ActiveState', '--value', 'goufayu-api.service'], text=True).strip() == 'inactive', 'archive_not_quiesced')
        with connection() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            baseline(conn); before = rows_state(conn); result = apply(conn); conn.execute('RESET ROLE'); check_rows(before, rows_state(conn)); conn.commit()
        committed = True; switch(NEW); control('start'); health(); payment_pin()
    except Exception:
        control('stop')
        with connection() as conn:
            conn.execute('SET TRANSACTION READ ONLY')
            present = conn.execute('SELECT EXISTS(SELECT 1 FROM public._goufayu_migrations WHERE migration_id=%s)', (P['migrations'][0]['id'],)).fetchone()[0]; conn.rollback()
        target = SAFE if present else OLD
        switch(target); control('start'); health()
        save('activation_recovery', dict(commit_acknowledged=committed, target=target.name, database_restored=False))
        raise
    return save('activated', dict(ok=True, phase='ACTIVATED', release=NEW.name, bundle=P['archive_bundle'], payment_untouched=True, old_rows_fingerprints_unchanged=True, **result))


def verify():
    need(CURRENT.resolve() == NEW, 'candidate_not_active'); manifest(NEW); payment_pin(); health()
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            current = db_state(conn)
            need(current['ledger'] == {**P['ledger'], **{m['id']:m['sha256'] for m in P['migrations']}}, 'post_deploy_ledger_changed')
            need(all(current['functions'].get(k) == v for k, v in P['functions'].items()), 'post_deploy_old_function_changed')
            before = rows_state(conn); checks = runtime_probe(conn)
            need(rows_state(conn) == before, 'post_deploy_probe_rows_leaked')
        finally:
            conn.rollback()
    config = json.loads(Path('/etc/goufayu-payment/config.json').read_bytes())
    request = urllib.request.Request('http://127.0.0.1:8765/v1/lottery/catalog', data=b'{"md5":""}', method='POST', headers={'Content-Type':'application/json', 'Authorization':'Bearer '+config['game_token']})
    with urllib.request.urlopen(request, timeout=10) as response:
        catalog = json.load(response)
    need(catalog.get('ok') is True and catalog['config_hash'] == P['archive_bundle'], 'existing_live_catalog_changed')
    return save('verified', dict(ok=True, phase='LIVE_VERIFIED', release=NEW.name, bundle=P['archive_bundle'], manifest_sha256=sha((NEW/'release_manifest.json').read_bytes()), ledger_entries=len(current['ledger']), probes=checks, payment_untouched=True, probe_accounts_retained=0, native_game_interaction_verified=False))


def rollback_safe():
    need(CURRENT.resolve() == NEW, 'rollback_pointer_not_ours'); manifest(SAFE); payment_pin()
    control('stop'); switch(SAFE); control('start'); health(); payment_pin()
    return save('rollback_safe', dict(ok=True, phase='ONBOARDING_DISPATCH_DISABLED_ALLOWLIST_PRESERVED', release=SAFE.name, account_rows_and_metadata_preserved=True, database_restored=False))


try:
    actions = {'prepare':prepare, 'validate':validate, 'backup':quiesce_backup, 'resume':resume, 'activate':activate, 'verify':verify, 'rollback-safe':rollback_safe}
    print(json.dumps(actions[MODE](), ensure_ascii=False))
except Exception as error:
    message = str(error).splitlines()[0] if str(error) else ''
    code = message if re.fullmatch(r'[a-z0-9_]{1,100}', message) else 'private_operator_error'
    print(json.dumps(dict(ok=False, error=code, error_type=type(error).__name__, sqlstate=getattr(error, 'sqlstate', None))))
    raise SystemExit(1)
