"""WS4-only additive ticket-code operations. Importing performs no I/O.

Only the explicit inventory function is read-only. Mutations use an immutable
stage/plan, full backup and synthetic-clone receipts; no API/payment restarts.
"""
from pathlib import Path
import contextlib
import hashlib
import json
import os
import re
import subprocess
import time

DB = 'goufayu_ws4'
PORT = 15432
API_UNIT = 'goufayu-ws4.service'
API_RELEASES = Path('/opt/goufayu-ws4/releases')
PASSWORD = Path('/etc/goufayu-ws4/admin-password')
STAGE_ROOT = Path('/root/goufayu_upload/ticket_codes_20261102')
LOCK = Path('/var/lock/goufayu_ws4_redemption.lock')
LOCKS = tuple(sorted((LOCK, Path('/var/lock/goufayu_admission_five.lock')), key=str))
PAYMENT_UNITS = ('goufayu-payment.service', 'goufayu-ws4-payment.service')
TABLES = ('redemption_codes', 'redemption_claims', 'redemption_attempts')
DEFINITION_COLUMNS = ('code_id', 'code_hash', 'label', 'rewards', 'enabled',
                      'starts_at', 'expires_at', 'max_redemptions')


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True,
                      allow_nan=False).encode('ascii')


def sha(value):
    return hashlib.sha256(value).hexdigest()


def command(args, *, data=None, env=None, timeout=120):
    result = subprocess.run(args, input=data, capture_output=True, env=env, timeout=timeout)
    need(result.returncode == 0, 'ws4_subprocess_failed')
    return result.stdout


def connect(database=DB, *, autocommit=False):
    need(database == DB or re.fullmatch(r'goufayu_ws4_ticket_[a-f0-9]{12}', database),
         'database_scope_invalid')
    import psycopg
    return psycopg.connect(host='127.0.0.1', port=PORT, dbname=database, user='postgres',
                          password=PASSWORD.read_text().strip(), autocommit=autocommit)


def service(unit):
    raw = command(['systemctl', 'show', unit, '--property=MainPID,WorkingDirectory', '--no-pager']).decode()
    fields = dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)
    pid = int(fields.get('MainPID', '0'))
    need(pid > 0, 'required_service_not_running')
    return {'pid': pid, 'working_directory': fields.get('WorkingDirectory', '')}


def payment_services():
    return {name: service(name)['pid'] for name in PAYMENT_UNITS}


def active_release():
    state = service(API_UNIT)
    cwd = Path(state['working_directory']).resolve()
    need(cwd.name == 'backend' and cwd.parent.parent == API_RELEASES,
         'ws4_active_release_scope_invalid')
    need(Path(os.readlink('/proc/%d/cwd' % state['pid'])).resolve() == cwd,
         'service_process_working_directory_mismatch')
    manifest = cwd.parent / 'release_manifest.json'
    need(manifest.is_file() and not manifest.is_symlink() and manifest.stat().st_size < 8*1024*1024,
         'ws4_manifest_invalid')
    return cwd.parent, {**state, 'manifest_sha256': sha(manifest.read_bytes())}


def definitions_state(conn, *, exclude=()):
    # Frozen definitions exclude ordinary mutable counters/updated_at. Hashes,
    # reward content and dates stay entirely on the server; only the digest exits.
    names = ','.join("'%s',c.%s" % (name, name) for name in DEFINITION_COLUMNS)
    row = conn.execute("SELECT count(*),encode(sha256(convert_to(coalesce("
        "jsonb_agg(jsonb_build_object(" + names + ") ORDER BY code_id)::text,'[]'),'UTF8')),'hex') "
        "FROM public.redemption_codes c WHERE NOT (code_id=ANY(%s::text[]))", (list(exclude),)).fetchone()
    return {'count': row[0], 'sha256': row[1]}


def claims_state(conn):
    row = conn.execute("SELECT count(*),encode(sha256(convert_to(coalesce("
        "jsonb_agg(to_jsonb(c) ORDER BY account_id,code_id)::text,'[]'),'UTF8')),'hex') "
        "FROM public.redemption_claims c").fetchone()
    return {'count': row[0], 'sha256': row[1]}


def inventory():
    release, api = active_release()
    bundle = json.loads((release/'addon/server/bundles/current.json').read_bytes())['hash']
    need(bundle == 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488',
         'published_archive_bundle_changed')
    with connect() as conn:
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
        conn.execute("SET LOCAL statement_timeout='10s'")
        need(conn.info.dbname == DB and conn.info.port == PORT, 'database_identity_mismatch')
        columns = conn.execute("SELECT table_name,column_name,data_type FROM information_schema.columns "
            "WHERE table_schema='public' AND table_name=ANY(%s) ORDER BY table_name,ordinal_position",
            (list(TABLES),)).fetchall()
        need({r[0] for r in columns} == set(TABLES), 'redemption_schema_missing')
        functions = conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) "
            "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
            "WHERE n.nspname='public' AND p.proname IN ('redemption_prepare','redemption_commit') ORDER BY 1").fetchall()
        need(len(functions) == 2, 'redemption_rpc_contract_missing')
        result = {'schema': 1, 'status': 'READ_ONLY_WS4_TICKET_INVENTORY', 'database': DB,
            'connection_port': PORT, 'api': api, 'active_release': str(release), 'bundle_hash': bundle,
            'schema_columns': [list(row) for row in columns],
            'rpc_sha256': {name: sha(body.encode()) for name, body in functions},
            'definitions': definitions_state(conn),
            'claims_count': conn.execute('SELECT count(*) FROM public.redemption_claims').fetchone()[0],
            'attempts_count': conn.execute('SELECT count(*) FROM public.redemption_attempts').fetchone()[0],
            'payment_services': payment_services(), 'server_modified': False,
            'plaintext_codes_read': False, 'credentials_returned': False}
        conn.rollback()
    return result


def validate_registry(registry):
    need(isinstance(registry, dict) and set(registry) == {'version', 'codes'}
         and registry['version'] == 1 and len(registry['codes']) == 4, 'four_code_registry_required')
    ids, hashes = set(), set()
    for row, quantity in zip(registry['codes'], (10, 50, 100, 200)):
        need(set(row) == {'code_id', 'code_hash', 'label', 'enabled', 'max_redemptions',
                          'starts_at', 'expires_at', 'rewards'}, 'registry_fields_invalid')
        digest = row['code_hash']
        need(isinstance(digest, str) and re.fullmatch('[a-f0-9]{64}', digest)
             and row['code_id'] == 'r_' + digest[:32], 'registry_identity_invalid')
        need(row['code_id'] not in ids and digest not in hashes, 'registry_collision')
        ids.add(row['code_id']); hashes.add(digest)
        need(row['label'] == '普通抽奖券×%d' % quantity and row['enabled'] is True
             and type(row['max_redemptions']) is int and row['max_redemptions'] == 0
             and row['starts_at'] is None and row['expires_at'] is None, 'registry_policy_invalid')
        reward = row['rewards']
        need(set(reward) == {'products', 'markers', 'wallet', 'entitlements'}
             and reward['markers'] == [] and reward['wallet'] == {}
             and reward['entitlements'] == {} and len(reward['products']) == 1, 'registry_reward_invalid')
        product = reward['products'][0]; grants = product.get('grants', {})
        need(product.get('sku') == 'lottery_ticket_single' and product.get('item_id') == 'pay_lottery_ticket_single'
             and product.get('price') == 0 and product.get('currency') == 'u_coin'
             and product.get('purchase_method') == 'redemption' and product.get('purchase_limit') == 0
             and product.get('ownership_quantity') == 1 and not product.get('effects')
             and grants.get('items') == {'lottery_ticket': quantity}
             and grants.get('item_limits') == {'lottery_ticket': 2147483647}
             and not grants.get('entitlements') and not grants.get('vip_claims')
             and not grants.get('vip_claim_effects'), 'registry_reward_invalid')
    return registry['codes']


def stage_path(plan):
    stage = Path(plan['stage'])
    need(stage.parent == STAGE_ROOT and re.fullmatch('run_[a-f0-9]{12}', stage.name), 'stage_scope_invalid')
    for part in (stage, *stage.parents):
        need(not part.is_symlink(), 'stage_symlink_refused')
    return stage


def save(stage, name, value):
    need(re.fullmatch('[a-z0-9_]+', name), 'receipt_name_invalid')
    with (stage / (name + '.json')).open('x') as stream:
        json.dump(value, stream, sort_keys=True); stream.flush(); os.fsync(stream.fileno())
    (stage / (name + '.json')).chmod(0o600)
    return value


def load(stage, name):
    path = stage / (name + '.json')
    need(path.is_file() and not path.is_symlink() and path.stat().st_size < 1024*1024, 'stage_receipt_invalid')
    return json.loads(path.read_bytes())


def baseline(plan, *, exclude=(), check_definitions=True):
    root, api = active_release(); expected = plan['inventory']
    need(str(root) == expected['active_release'] and api == expected['api'], 'active_api_baseline_changed')
    need(payment_services() == expected['payment_services'], 'payment_service_changed')
    if check_definitions:
        with connect() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            need(definitions_state(conn, exclude=exclude) == expected['definitions'], 'existing_definitions_changed')
            conn.rollback()
    return root


@contextlib.contextmanager
def operator_lock():
    import fcntl
    streams = []
    try:
        for path in LOCKS:
            stream = path.open('a'); streams.append([stream, False])
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            streams[-1][1] = True
        yield
    finally:
        for stream, owned in reversed(streams):
            try:
                if owned: fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
            finally:
                stream.close()


def _prepare_locked(plan, files):
    stage = stage_path(plan); need(not stage.exists(), 'new_stage_required')
    need(plan['schema'] == 1 and plan['database'] == DB and plan['port'] == PORT
         and plan['inventory']['definitions']['count'] == 128, 'reviewed_ws4_baseline_required')
    baseline(plan)
    need(set(files) == {'operator.py', 'clone_checks.py', 'registry.json'}, 'exact_stage_files_required')
    need(set(plan['files']) == set(files) and all(sha(raw) == plan['files'][name] for name, raw in files.items()), 'stage_input_hash_changed')
    validate_registry(json.loads(files['registry.json']))
    stage.mkdir(parents=True, mode=0o700)
    for name, raw in files.items():
        with (stage / name).open('xb') as stream:
            stream.write(raw); stream.flush(); os.fsync(stream.fileno())
        (stage / name).chmod(0o600)
    save(stage, 'plan', plan)
    return save(stage, 'prepared', {'status': 'PREPARED_NO_PRODUCTION_WRITES', 'plan_sha256': sha(canonical(plan))})


def prepare(plan, files):
    with operator_lock():
        return _prepare_locked(plan, files)


def checked_stage(plan):
    stage = stage_path(plan)
    need(load(stage, 'plan') == plan, 'sealed_plan_changed')
    for name, digest in plan['files'].items():
        path = stage / name
        need(path.is_file() and not path.is_symlink() and sha(path.read_bytes()) == digest, 'sealed_file_changed')
    return stage


def dump(stage, name, *, schema_only=False):
    target = stage / (name + '.dump'); need(not target.exists(), 'new_dump_required')
    args = ['podman', 'exec', '-i', '--env', 'PGPASSWORD', 'goufayu-ws4-db',
            'pg_dump', '-h', '127.0.0.1', '-U', 'postgres', '-d', DB, '-Fc']
    if schema_only:
        args.append('--schema-only')
    raw = command(args, env=dict(os.environ, PGPASSWORD=PASSWORD.read_text().strip()))
    need(raw.startswith(b'PGDMP') and len(raw) < 128*1024*1024, 'dump_invalid')
    with target.open('xb') as stream:
        stream.write(raw); stream.flush(); os.fsync(stream.fileno())
    target.chmod(0o600)
    return {'path': str(target), 'bytes': len(raw), 'sha256': sha(raw), 'at': time.time(), 'schema_only': schema_only}


def clone(plan):
    stage = checked_stage(plan); release = baseline(plan)
    need(not (stage / 'clone.json').exists(), 'new_clone_required')
    schema = dump(stage, 'schema', schema_only=True)
    name = 'goufayu_ws4_ticket_' + stage.name[4:]
    with connect(autocommit=True) as conn:
        need(not conn.execute('SELECT 1 FROM pg_database WHERE datname=%s', (name,)).fetchone(), 'new_clone_database_required')
        from psycopg import sql
        conn.execute(sql.SQL('CREATE DATABASE {} OWNER goufayu_owner TEMPLATE template0').format(sql.Identifier(name)))
        conn.execute(sql.SQL('REVOKE ALL ON DATABASE {} FROM PUBLIC').format(sql.Identifier(name)))
        conn.execute(sql.SQL('GRANT CONNECT ON DATABASE {} TO goufayu_app,goufayu_owner').format(sql.Identifier(name)))
    # Stream restore directly to the named clone. No live data are dumped/copied.
    raw = Path(schema['path']).read_bytes()
    listing = command(['podman', 'exec', '-i', 'goufayu-ws4-db', 'pg_restore', '-l'], data=raw)
    need(b'TABLE DATA' not in listing and b'SEQUENCE SET' not in listing, 'schema_dump_contains_player_data')
    command(['podman', 'exec', '-i', '--env', 'PGPASSWORD', 'goufayu-ws4-db', 'pg_restore',
             '-h', '127.0.0.1', '-U', 'postgres', '-d', name, '--exit-on-error', '--single-transaction'], data=raw,
            env=dict(os.environ, PGPASSWORD=PASSWORD.read_text().strip()))
    from psycopg.types.json import Jsonb
    with connect() as live, connect(name) as copied:
        live.execute('SET TRANSACTION READ ONLY')
        for digest, config in live.execute('SELECT config_hash,config FROM public.archive_config_sets'):
            copied.execute('INSERT INTO public.archive_config_sets(config_hash,config) VALUES(%s,%s)', (digest, Jsonb(config)))
        live.rollback()
    import importlib.util
    spec = importlib.util.spec_from_file_location('ws4_ticket_clone_checks', stage / 'clone_checks.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    def register_synthetic(conn, rows):
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        # The clone is schema-only/empty; do not SELECT before insert_four's lock.
        return insert_four(conn, rows, {'count': 0, 'sha256': sha(b'[]')})
    result = module.run(lambda **kw: connect(name, **kw), release,
        json.loads((stage/'registry.json').read_bytes()), register_synthetic=register_synthetic)
    need(result['ok'] is True and result['real_lua_reducer'] is True and result['clone_only'] is True,
         'actual_clone_checks_required')
    return save(stage, 'clone', {**result, 'database': name, 'plan_sha256': sha(canonical(plan)),
        'production_player_data_copied': False, 'real_code_hashes_copied': False, 'schema_dump': schema})


def backup(plan):
    stage = checked_stage(plan); baseline(plan)
    need(load(stage, 'clone')['plan_sha256'] == sha(canonical(plan)), 'matching_clone_receipt_required')
    return save(stage, 'backup', dump(stage, 'full_backup'))


def acknowledge_backup(plan, ack):
    stage = checked_stage(plan); saved = load(stage, 'backup')
    need(ack.get('encrypted_roundtrip_verified') is True and ack.get('sha256') == saved['sha256']
         and re.fullmatch('[a-f0-9]{64}', ack.get('ciphertext_sha256', '')), 'verified_dpapi_backup_required')
    need(sha(Path(saved['path']).read_bytes()) == saved['sha256'], 'server_backup_changed')
    return save(stage, 'offsite_ack', ack)


INSERT = ('INSERT INTO public.redemption_codes(code_id,code_hash,label,rewards,enabled,starts_at,expires_at,max_redemptions) '
          'VALUES(%s,%s,%s,%s,%s,coalesce(%s::timestamptz,clock_timestamp()),%s::timestamptz,%s) RETURNING code_id')


def insert_four(conn, rows, expected):
    """Caller owns a short RR transaction; no INSERT conflict/update fallback."""
    from psycopg.types.json import Jsonb
    conn.execute("SET LOCAL statement_timeout='10s'")
    conn.execute("SET LOCAL lock_timeout='5s'")
    conn.execute('LOCK TABLE public.redemption_codes IN SHARE ROW EXCLUSIVE MODE')
    # A SELECT fixes the RR snapshot. Acquire the conflicting-writer table lock
    # first so the definition CAS cannot run against a pre-lock SELECT snapshot.
    need(conn.execute('SELECT pg_try_advisory_xact_lock(2026110204)').fetchone()[0], 'other_registry_operation_active')
    before = definitions_state(conn); need(before == expected, 'existing_definitions_changed')
    claims = claims_state(conn)
    ids = [r['code_id'] for r in rows]; hashes = [r['code_hash'] for r in rows]
    need(not conn.execute('SELECT 1 FROM public.redemption_codes WHERE code_id=ANY(%s::text[]) OR code_hash=ANY(%s::text[]) LIMIT 1',
                         (ids, hashes)).fetchone(), 'new_code_identity_collision')
    for row in rows:
        result = conn.execute(INSERT, (row['code_id'], row['code_hash'], row['label'], Jsonb(row['rewards']),
            row['enabled'], row['starts_at'], row['expires_at'], row['max_redemptions'])).fetchone()
        need(result[0] == row['code_id'], 'insert_receipt_mismatch')
    need(definitions_state(conn, exclude=ids) == before, 'old_definitions_modified')
    need(claims_state(conn) == claims, 'existing_claims_modified_by_transaction')
    return {'inserted': 4, 'old_definitions_preserved': before, 'existing_claims_preserved_in_same_rr_snapshot': True,
            'claims_at_transaction_snapshot': claims['count'], 'normal_concurrent_claims_allowed': True}


def apply(plan):
    stage = checked_stage(plan)
    with operator_lock():
        baseline(plan)
        need(not (stage/'apply_intent.json').exists(), 'existing_apply_intent_verify_do_not_retry')
        need(load(stage, 'clone')['plan_sha256'] == sha(canonical(plan)), 'matching_clone_receipt_required')
        saved, ack = load(stage, 'backup'), load(stage, 'offsite_ack')
        need(0 <= time.time()-saved['at'] < 900 and saved['schema_only'] is False
             and ack['encrypted_roundtrip_verified'] is True and ack['sha256'] == saved['sha256']
             and sha(Path(saved['path']).read_bytes()) == saved['sha256'], 'fresh_full_dpapi_verified_backup_required')
        rows = validate_registry(json.loads((stage/'registry.json').read_bytes()))
        save(stage, 'apply_intent', {'status': 'COMMIT_UNKNOWN_UNTIL_VERIFIED', 'at': time.time(),
                                   'plan_sha256': sha(canonical(plan)), 'automatic_retry': False})
        try:
            with connect() as conn:
                conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
                result = insert_four(conn, rows, plan['inventory']['definitions'])
            payments, api = payment_services(), service(API_UNIT)
            result.update(status='FOUR_WS4_TICKET_CODES_INSERTED', plan_sha256=sha(canonical(plan)),
                payment_services=payments, api_service=api,
                payment_services_unchanged=payments == plan['inventory']['payment_services'],
                api_service_unchanged=all(api[k] == plan['inventory']['api'][k] for k in ('pid','working_directory')),
                api_restarted_by_operator=False, payment_restarted_by_operator=False, player_redemption_performed=False)
            return save(stage, 'applied', result)
        except BaseException:
            save(stage, 'apply_unknown', {'status': 'PRESERVE_PENDING_VERIFY_ONLY', 'automatic_retry': False})
            raise


def verify(plan):
    stage = checked_stage(plan); rows = validate_registry(json.loads((stage/'registry.json').read_bytes()))
    ids = [row['code_id'] for row in rows]; baseline(plan, check_definitions=False)
    with connect() as conn:
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
        previous = definitions_state(conn, exclude=ids)
        found = conn.execute('SELECT code_id,code_hash,label,rewards,enabled,max_redemptions,expires_at,starts_at<=clock_timestamp() '
                             'FROM public.redemption_codes WHERE code_id=ANY(%s::text[]) ORDER BY code_id', (ids,)).fetchall()
        expected = sorted([(r['code_id'],r['code_hash'],r['label'],r['rewards'],True,0,None,True) for r in rows], key=lambda v:v[0])
        count = conn.execute('SELECT count(*) FROM public.redemption_codes').fetchone()[0]
        preserved = previous == plan['inventory']['definitions']
        matched = [list(r) for r in found] == [list(r) for r in expected] and count == 132 and preserved
        conn.rollback()
    return {'status': 'FOUR_ROWS_MATCH_VERIFIED' if matched else 'NOT_CONFIRMED_PRESERVE_PENDING',
        'matching_four': matched, 'definition_count': count, 'exact_total_132': count == 132,
        'old128_definition_digest_preserved': preserved, 'same_rr_verification_snapshot': True,
        'payment_services_unchanged': payment_services() == plan['inventory']['payment_services'],
        'api_restarted': False, 'player_redemption_performed': False, 'automatic_retry': False}


def dispatch(action, plan):
    need(action in {'clone', 'backup', 'apply', 'verify'}, 'unsupported_action')
    if action in {'clone', 'backup'}:
        with operator_lock():
            return globals()[action](plan)
    return globals()[action](plan)
