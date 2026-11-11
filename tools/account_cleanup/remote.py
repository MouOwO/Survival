"""Root-SSH maintenance operator. No network, services or deletes at import."""
from pathlib import Path
import contextlib
import fcntl
import hashlib
import hmac
import json
import os
import re
import signal
import sqlite3
import subprocess
import time

from account_cleanup_engine import need, canonical, sha, snapshot, lock_tables, apply_locked

DATABASE = 'goufayu_ws4'
DB_CONTAINER = 'goufayu-ws4-db'
PASSWORD = Path('/etc/goufayu-ws4/admin-password')
AUTH_DATABASE = Path('/var/lib/goufayu-ws4-web/auth.sqlite3')
STAGES = Path('/root/goufayu_upload/account_cleanup')
UNITS = ('goufayu-ws4-web.service', 'goufayu-ws4-payment.service', 'goufayu-ws4.service')
PREFIXES = ('/opt/goufayu-ws4-web/releases/', '/opt/goufayu-ws4-payment/releases/', '/opt/goufayu-ws4/releases/')
AUTH_TABLES = {'challenges': ['device_hash','user_code','account','match_id','created','expires',
    'approved_steam','approved_at','token_hash','token_expires','revoked','last_poll'],
    'browsers': ['sid_hash','csrf_hash','steam','expires'],
    'flows': ['state_hash','sid_hash','user_code','return_to_hash','expires','used'],
    'nonces': ['nonce_hash','expires'], 'limits': ['key','bucket','count'],
    'flow_results': ['state_hash','outcome'], 'browser_preferences': ['sid_hash','remembered'],
    'payment_order_bindings': ['order_id','account','match_id','created']}


def normalize_account(value):
    need(isinstance(value, str) and bool(re.fullmatch('[0-9]{1,17}', value)), 'numeric_steam_identity_required')
    number = int(value)
    if number > 0xFFFFFFFF:
        number -= 76561197960265728
    need(0 < number <= 0xFFFFFFFF, 'steam_identity_out_of_range')
    return str(number), str(number + 76561197960265728)


def command(args, **options):
    result = subprocess.run(args, capture_output=True, timeout=30, **options)
    need(result.returncode == 0, 'maintenance_subprocess_failed')
    return result.stdout


def context():
    pins, environments = {}, {}
    for name, prefix in zip(UNITS, PREFIXES):
        raw = command(['systemctl','show',name,'--property=MainPID,WorkingDirectory','--no-pager']).decode()
        fields = dict(line.split('=',1) for line in raw.splitlines() if '=' in line)
        need(int(fields.get('MainPID','0')) > 0, 'required_ws4_service_not_running')
        cwd = Path(fields['WorkingDirectory']).resolve()
        need(str(cwd).startswith(prefix), 'ws4_service_scope_changed')
        pid = fields['MainPID']
        need(Path(os.readlink('/proc/' + pid + '/cwd')).resolve() == cwd, 'ws4_process_scope_changed')
        environments[name] = dict(value.split(b'=',1) for value in
            Path('/proc/' + pid + '/environ').read_bytes().split(b'\0') if b'=' in value)
        release = cwd.parent if cwd.name == 'backend' else cwd
        manifest = release / ('cloud-bundle.json' if name == UNITS[1] else 'release_manifest.json')
        need(manifest.is_file() and not manifest.is_symlink(), 'ws4_manifest_missing')
        pins[name] = {'pid': int(pid), 'working_directory': str(cwd), 'manifest_sha256': sha(manifest.read_bytes())}
    web = environments[UNITS[0]]
    need(web.get(b'PLAYER_WEB_AUTH_DATABASE',b'').decode() == str(AUTH_DATABASE), 'auth_database_scope_changed')
    need(web.get(b'PLAYER_WEB_AUTH_LOBBY_ENABLED',b'0') == b'0', 'active_lobby_requires_separate_review')
    pepper = environments[UNITS[2]].get(b'FISHING_ACCOUNT_ID_PEPPER')
    need(pepper and len(pepper) >= 16, 'deployed_identity_mapping_unavailable')
    return pins, pepper, web[b'PLAYER_WEB_AUTH_SECRET'].decode()


def connect():
    import psycopg
    return psycopg.connect(host='127.0.0.1', port=15432, dbname=DATABASE, user='postgres',
                          password=PASSWORD.read_text().strip())


def auth_schema(conn):
    names = sorted(row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"))
    need(set(names) == set(AUTH_TABLES), 'auth_schema_changed_review_required')
    found = {name: [row[1] for row in conn.execute('PRAGMA table_info("' + name + '")')] for name in names}
    need(found == AUTH_TABLES, 'auth_schema_changed_review_required')


def auth_cleanup(conn, account, steam, secret, *, apply=False):
    auth_schema(conn)
    # Expire only this account's sessions and consent flows. Shared IP throttles
    # and Steam replay nonces are not player progress and remain intact.
    scopes = ('start-account','proxy','payment-catalog','payment-create','payment-status','payment-cancel')
    keys = [hmac.new(bytes.fromhex(secret), ('rate:' + scope + ':' + account).encode(), hashlib.sha256).hexdigest()
            for scope in scopes]
    flow = "sid_hash IN (SELECT sid_hash FROM browsers WHERE steam=?) OR user_code IN (SELECT user_code FROM challenges WHERE account=? OR approved_steam=?)"
    queries = [
        ('flow_results', 'state_hash IN (SELECT state_hash FROM flows WHERE ' + flow + ')', (steam,account,steam)),
        ('flows', flow, (steam,account,steam)),
        ('browser_preferences', 'sid_hash IN (SELECT sid_hash FROM browsers WHERE steam=?)', (steam,)),
        ('browsers', 'steam=?', (steam,)),
        ('challenges', 'account=? OR approved_steam=?', (account,steam)),
        ('payment_order_bindings', 'account=?', (account,)),
        ('limits', 'key IN (' + ','.join('?' for _ in keys) + ')', keys)]
    counts = {}
    for name, where, parameters in queries:
        count = conn.execute('SELECT count(*) FROM ' + name + ' WHERE ' + where, parameters).fetchone()[0]
        counts[name] = count
        if apply:
            need(conn.execute('DELETE FROM ' + name + ' WHERE ' + where, parameters).rowcount == count,
                 'auth_delete_count_mismatch')
    return counts


def new_json(path, value):
    with path.open('xb') as stream:
        stream.write(canonical(value) + b'\n'); stream.flush(); os.fsync(stream.fileno())
    path.chmod(0o600)


def file_hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            digest.update(block)
    return digest.hexdigest()


def new_stage(request_id):
    need(bool(re.fullmatch('[a-f0-9]{32}', request_id)), 'request_identity_invalid')
    for node in (STAGES, *STAGES.parents):
        need(not node.is_symlink(), 'maintenance_stage_symlink_refused')
    STAGES.mkdir(parents=True, exist_ok=True, mode=0o700)
    stage = STAGES / ('run_' + request_id)
    stage.mkdir(mode=0o700)  # Existing intent is never overwritten or retried.
    return stage


@contextlib.contextmanager
def locks():
    paths = sorted(['/var/lock/goufayu_ws4_account_cleanup.lock',
        '/var/lock/goufayu_ws4_redemption.lock', '/var/lock/goufayu_admission_five.lock'])
    with contextlib.ExitStack() as stack:
        for path in paths:
            stream = stack.enter_context(open(path, 'a+b'))
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def backup(stage):
    dump = stage / 'database.dump'
    env = dict(os.environ, PGPASSWORD=PASSWORD.read_text().strip())
    with dump.open('xb') as stream:
        result = subprocess.run(['podman','exec','--env','PGPASSWORD',DB_CONTAINER,'pg_dump',
            '-h','127.0.0.1','-U','postgres','-d',DATABASE,'--format=custom'],
            stdout=stream, stderr=subprocess.PIPE, env=env, timeout=180)
        stream.flush(); os.fsync(stream.fileno())
    dump.chmod(0o600)
    need(result.returncode == 0 and dump.stat().st_size > 1000, 'full_database_backup_failed')
    with dump.open('rb') as stream:
        listing = command(['podman','exec','-i',DB_CONTAINER,'pg_restore','--list'], stdin=stream)
    need(all(item in listing for item in (b'TABLE DATA public survival_players',
         b'TABLE DATA public redemption_claims', b'TABLE DATA payments orders')), 'backup_table_list_incomplete')
    auth = stage / 'auth.sqlite3'
    with sqlite3.connect(AUTH_DATABASE.as_uri() + '?mode=ro', uri=True) as source:
        with sqlite3.connect(auth) as target:
            source.backup(target)
            need(target.execute('PRAGMA integrity_check').fetchone() == ('ok',), 'auth_backup_invalid')
    auth.chmod(0o600)
    receipt = {name: {'bytes': path.stat().st_size, 'sha256': file_hash(path)}
               for name, path in [('database.dump',dump),('auth.sqlite3',auth)]}
    new_json(stage / 'backup.json', receipt)
    return receipt


def execute(payload, contract):
    if payload.get('action') == 'status':
        need(set(payload) == {'action','request_id','operator_sha256'}, 'request_fields_invalid')
        need(bool(re.fullmatch('[a-f0-9]{32}', payload['request_id'])), 'request_identity_invalid')
        stage = STAGES / ('run_' + payload['request_id'])
        need(stage.is_dir() and not stage.is_symlink(), 'maintenance_request_not_found')
        names = ('backup.json','auth_revoked.json','commit_intent.json','applied.json','failed.json','result.json')
        records = {}
        for name in names:
            path = stage / name
            if path.exists():
                need(not path.is_symlink() and path.stat().st_size <= 2*1024*1024, 'invalid_maintenance_receipt')
                records[name] = json.loads(path.read_bytes())
        return {'ok': True, 'status': 'READ_ONLY_MAINTENANCE_RECEIPTS', 'request_id': payload['request_id'],
                'stage': str(stage), 'records': records, 'automatic_retry': False}
    need(set(payload) in ({'action','account','operator_sha256'},
         {'action','account','operator_sha256','expected','confirm','request_id'}), 'request_fields_invalid')
    need(payload['action'] in ('preview','apply'), 'unsupported_account_cleanup_action')
    account, steam = normalize_account(payload['account'])
    pins, pepper, secret = context()
    database_id = hmac.new(pepper, account.encode('ascii'), hashlib.sha256).hexdigest()
    with connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        conn.execute("SET LOCAL statement_timeout='30s'")
        state, _ = snapshot(conn, database_id, contract)
    with sqlite3.connect(AUTH_DATABASE.as_uri() + '?mode=ro', uri=True) as auth:
        auth_counts = auth_cleanup(auth, account, steam, secret)
    plan = {'schema': 1, 'database': DATABASE, 'account_id': account, 'steam_id64': steam,
            'database_account': database_id, 'services': pins, 'state': state,
            'auth_rows': auth_counts, 'operator_sha256': payload['operator_sha256'],
            'maintenance_units': list(UNITS), 'payments_must_be_settled': True}
    if payload['action'] == 'preview':
        return {'ok': True, 'status': 'PREVIEW_ONLY_NO_WRITES', 'plan': plan, 'plan_sha256': sha(canonical(plan))}
    need(payload['confirm'] == 'DELETE ' + account, 'exact_account_confirmation_required')
    expected = payload['expected']
    need(expected['database'] == DATABASE and expected['account_id'] == account
         and expected['database_account'] == database_id and expected['operator_sha256'] == payload['operator_sha256'],
         'account_or_operator_plan_mismatch')
    need(expected['services'] == pins and expected['state']['fingerprint'] == state['fingerprint'],
         'account_or_services_changed_preview_again')
    need(state['open_payment_orders'] == 0, 'pending_payment_orders_must_be_resolved')
    with locks():
        latest_pins, _, _ = context()
        need(latest_pins == pins, 'services_changed_before_maintenance')
        stage = new_stage(payload['request_id'])
        new_json(stage / 'plan.json', expected)
        stopped, commit_attempted, known, auth_revoked, committed = [], False, False, False, False
        def timed_out(_number, _frame):
            raise TimeoutError('maintenance_deadline')
        previous_alarm = signal.signal(signal.SIGALRM, timed_out)
        previous_hup = signal.signal(signal.SIGHUP, timed_out)
        previous_term = signal.signal(signal.SIGTERM, timed_out)
        previous_int = signal.signal(signal.SIGINT, timed_out)
        signal.alarm(300)
        result = None
        try:
            for unit in UNITS:
                stopped.append(unit); command(['systemctl','stop',unit])
            for unit in UNITS:
                raw = command(['systemctl','show',unit,'--property=MainPID','--value']).decode().strip()
                need(raw == '0', 'ws4_writer_still_running')
            saved = backup(stage)
            conn = connect()
            try:
                lock_tables(conn, contract)
                locked, rows = snapshot(conn, database_id, contract, keep_rows=True)
                need(locked['fingerprint'] == state['fingerprint'], 'account_changed_before_maintenance')
                new_json(stage / 'account_rows.json', rows)
                with sqlite3.connect(AUTH_DATABASE) as auth:
                    auth.execute('PRAGMA foreign_keys=ON')
                    auth.execute('BEGIN EXCLUSIVE')
                    revoked = auth_cleanup(auth, account, steam, secret, apply=True)
                auth_revoked = True
                new_json(stage / 'auth_revoked.json', revoked)
                cleared = apply_locked(conn, database_id, contract, state['fingerprint'])
                new_json(stage / 'commit_intent.json', {'before': state['fingerprint'],
                    'after': cleared['after_fingerprint'], 'automatic_retry': False})
                commit_attempted = True
                conn.commit(); known = True; committed = True
                result = {'ok': True, 'status': 'ACCOUNT_RESET_COMPLETE', 'account_id': account,
                    'stage': str(stage), 'backups': saved, 'auth_revoked': revoked, **cleared}
            except Exception:
                if commit_attempted and not known:
                    # Reconcile a lost COMMIT acknowledgement by reading only.
                    conn.close()
                    with connect() as verify:
                        verify.execute('SET TRANSACTION READ ONLY')
                        actual, _ = snapshot(verify, database_id, contract)
                    intent = json.loads((stage / 'commit_intent.json').read_bytes())
                    known = actual['fingerprint'] in (intent['before'], intent['after'])
                    if actual['fingerprint'] == intent['after']:
                        committed = True
                        result = {'ok': True, 'status': 'ACCOUNT_RESET_COMMIT_RECONCILED',
                            'account_id': account, 'stage': str(stage), 'backups': saved, **cleared}
                    else:
                        raise
                else:
                    conn.rollback(); known = True
                    raise
            finally:
                conn.close()
            new_json(stage / 'applied.json', result)
        except Exception as error:
            signal.alarm(0)
            reason = str(error) if isinstance(error, ValueError) and re.fullmatch('[a-z0-9_]{1,120}', str(error)) else 'maintenance_failed'
            result = {'ok': False, 'status': 'ACCOUNT_RESET_NOT_CONFIRMED', 'error': reason,
                'stage': str(stage), 'auth_revoked': auth_revoked,
                'database_committed': committed,
                'database_commit_unknown': commit_attempted and not known, 'automatic_retry': False}
            new_json(stage / 'failed.json', result)
        finally:
            signal.alarm(0)
            # A closed SSH terminal must not interrupt bounded service recovery.
            for number in (signal.SIGHUP, signal.SIGTERM, signal.SIGINT):
                signal.signal(number, signal.SIG_IGN)
            # An uncertain commit never automatically restarts writers.
            if not commit_attempted or known:
                restart_failures = []
                for unit in reversed(stopped):
                    try:
                        command(['systemctl','start',unit])
                    except Exception:
                        restart_failures.append(unit)
                result['services_restored'] = [unit for unit in stopped if unit not in restart_failures]
                if restart_failures:
                    result.update(ok=False, service_restart_failures=restart_failures,
                                  manual_service_recovery_required=True)
            else:
                result['manual_reconciliation_required'] = True
            try:
                new_json(stage / 'result.json', result)
            finally:
                signal.signal(signal.SIGALRM, previous_alarm)
                signal.signal(signal.SIGHUP, previous_hup)
                signal.signal(signal.SIGTERM, previous_term)
                signal.signal(signal.SIGINT, previous_int)
        return result
