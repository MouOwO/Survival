"""Synchronize only the isolated WS4 API with the already published d573 bundle.

Preparation and clone validation do not alter the live database or API. Active
changes require a verified clone, encrypted offsite backup and exact baselines.
No payment service, credential, account whitelist or original API is changed.
"""
from pathlib import Path
import base64, contextlib, hashlib, importlib.util, io, json, os, re, secrets, shlex, shutil, subprocess, time

HASH = 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
BASE = Path('/opt/goufayu-ws4/releases')
OLD = BASE / '20261023-auth-v1'
SOURCE = Path('/opt/goufayu/releases/20261029-archive-d573588b64d2')
NEW = BASE / '20261031-catalog-d573588b64d2'
SAFE = BASE / '20261031-catalog-d573588b64d2-safe'
UNIT = Path('/etc/systemd/system/goufayu-ws4.service')
ENV = Path('/etc/goufayu-ws4/api.env')
STAGE = Path(globals()['STAGE_PATH'])
PLAN = globals()['PLAN_DATA']
sha = lambda raw: hashlib.sha256(raw).hexdigest()


def need(value, code):
    if not value:
        raise RuntimeError(code)


def command(args, *, env=None, data=None):
    p = subprocess.run(args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       env=env, timeout=120)
    need(p.returncode == 0, 'ws4_operator_subprocess_failed')
    return p.stdout


def save(name, value):
    path = STAGE / (name + '.json')
    need(not path.exists(), 'new_stage_receipt_required')
    with path.open('x') as stream:
        json.dump(value, stream, sort_keys=True)
    path.chmod(0o600)
    return value


def connect(database='goufayu_ws4', *, autocommit=False, app=False):
    import psycopg
    need(database == 'goufayu_ws4' or re.fullmatch(r'goufayu_ws4_catalog_[a-f0-9]{12}', database), 'database_scope_invalid')
    password = Path('/etc/goufayu-ws4/' + ('app-password' if app else 'admin-password')).read_text().strip()
    conn = psycopg.connect(host='127.0.0.1', port=15432, dbname=database,
                          user='goufayu_app' if app else 'postgres', password=password,
                          autocommit=autocommit)
    need(conn.info.port == 15432 and conn.info.dbname == database, 'isolated_database_required')
    return conn


def services():
    return {name: command(['systemctl', 'show', name, '--property=MainPID', '--value']).decode().strip()
            for name in PLAN['retained_services']}


def state(conn):
    return dict(functions=dict((name, sha(body.encode())) for name, body in conn.execute(
        "SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')")),
        ledger=dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations')),
        configs=dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM public.archive_config_sets")))


def rows(conn):
    from psycopg import sql
    result = {}
    for schema, table in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall():
        result[schema + '.' + table] = list(conn.execute(sql.SQL(
            "SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t"
        ).format(sql.Identifier(schema), sql.Identifier(table))).fetchone())
    return result


def pending(conn):
    need(conn.execute('SELECT count(*) FROM public.archive_operations WHERE NOT done').fetchone()[0] == 0, 'pending_archive_operations')
    need(conn.execute("SELECT count(*) FROM payments.orders WHERE state IN ('created','pending','paid_review')").fetchone()[0] == 0, 'pending_cash_orders')


def verify_source(*, launch_root=None):
    if launch_root is None:
        need(sha(UNIT.read_bytes()) == PLAN['unit_sha256'] and sha(ENV.read_bytes()) == PLAN['env_sha256'], 'ws4_launch_baseline_changed')
    else:
        expected_unit, expected_env = launch_bytes(launch_root)
        need(UNIT.read_bytes() == expected_unit and ENV.read_bytes() == expected_env, 'ws4_launch_baseline_changed')
    manifest = json.loads((SOURCE / 'release_manifest.json').read_bytes())
    need(sha((SOURCE / 'release_manifest.json').read_bytes()) == PLAN['source_manifest_sha256'], 'frozen_source_manifest_changed')
    need(json.loads((SOURCE / 'addon/server/bundles/current.json').read_bytes())['hash'] == HASH, 'published_source_bundle_changed')
    for name, digest in manifest['files'].items():
        path = SOURCE / name
        need(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(SOURCE)
             and sha(path.read_bytes()) == digest, 'frozen_source_file_changed')
    for name, digest in PLAN['ws4_wrappers'].items():
        need(sha((OLD / name).read_bytes()) == digest, 'ws4_auth_wrapper_changed')
    need(services() == PLAN['retained_services'], 'retained_service_changed')


def prepare():
    verify_source()
    need(not NEW.exists() and not SAFE.exists(), 'new_immutable_release_required')
    with connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        need(state(conn) == PLAN['database_state'], 'database_baseline_changed')
    # One complete file pass per new release; never performed by a player request.
    shutil.copytree(SOURCE, NEW, ignore=shutil.ignore_patterns('.venv', '__pycache__', '*.pyc'))
    shutil.copytree(OLD / 'backend/workshop_test', NEW / 'backend/workshop_test', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copytree(OLD, SAFE, ignore=shutil.ignore_patterns('.venv', '__pycache__', '*.pyc'))
    shutil.copyfile(NEW / 'backend/fishing_api/postgres.py', SAFE / 'backend/fishing_api/postgres.py')
    for root in (NEW, SAFE):
        (root / '.venv').symlink_to('/opt/goufayu-ws4/.venv', target_is_directory=True)
    for origin, name in ((UNIT, 'unit.original'), (ENV, 'env.original')):
        with (STAGE / name).open('xb') as stream:
            stream.write(origin.read_bytes())
        (STAGE / name).chmod(0o600)
    return save('prepared', dict(ok=True, status='PREPARED_NOT_ACTIVE', bundle=HASH,
        source_files=len(json.loads((SOURCE / 'release_manifest.json').read_bytes())['files']), live_changed=False))


def sql_body(raw):
    text = raw.decode('utf8')
    opening = re.match(r'\A(?:\s|--[^\n]*(?:\n|$))*begin\s*;', text, re.I)
    ending = re.search(r'\bcommit\s*;\s*\Z', text, re.I)
    if opening or ending:
        need(opening and ending and opening.end() < ending.start(), 'sql_transaction_wrapper_invalid')
        text = text[opening.end():ending.start()]
    return text


def migrate(conn):
    from psycopg.types.json import Jsonb
    conn.execute('SET LOCAL ROLE goufayu_owner')
    conn.execute('SELECT pg_advisory_xact_lock(719232014031)')
    need(not conn.execute("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN ('anon','authenticated'))").fetchone()[0],
         'isolated_role_baseline_changed')
    need(state(conn) == PLAN['database_state'], 'database_baseline_changed')
    before = rows(conn)
    for migration in PLAN['migrations']:
        raw = (STAGE / migration['path']).read_bytes()
        need(sha(raw) == migration['sha256'], 'sealed_migration_changed')
        conn.execute(sql_body(raw))
        conn.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)',
                     (migration['id'], migration['sha256']))
    bundle = json.loads((NEW / 'addon/server/bundles' / HASH / 'bundle.json').read_bytes())
    config = dict(configs=bundle['configs'])
    if bundle.get('compatible_config_hashes'):
        config['compatible_config_hashes'] = bundle['compatible_config_hashes']
    digest = conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(config),)).fetchone()[0]
    definition = conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
    matches = list(re.finditer(r'(?m)^\s*BEGIN\b', definition, re.I))
    need(matches and HASH not in definition and re.search(r'\bDECLARE\s+v\s+jsonb\b', definition, re.I), 'new_config_branch_required')
    position = matches[0].end()
    branch = ("\n -- Exact published WS4 catalog contract, 20261031.\n IF p_hash='" + HASH + "' THEN\n"
              " IF encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'" + digest + "' THEN RAISE EXCEPTION 'archive_release_configuration_mismatch'; END IF;\n"
              " INSERT INTO public.archive_config_sets(config_hash,config) VALUES(p_hash,p_config) ON CONFLICT DO NOTHING;\n"
              " SELECT config INTO v FROM public.archive_config_sets WHERE config_hash=p_hash;\n"
              " IF v IS DISTINCT FROM p_config THEN RAISE EXCEPTION 'archive_config_immutable'; END IF;\n"
              " RETURN jsonb_build_object('ok',true);\n END IF;\n")
    updated = definition[:position] + branch + definition[position:]
    need(updated.replace(branch, '', 1) == definition, 'old_config_policy_changed')
    conn.execute(updated)
    need(conn.execute('SELECT public.archive_sync_config(%s,%s)', (HASH, Jsonb(config))).fetchone()[0]['ok'], 'new_config_registration_failed')
    after = rows(conn)
    unchanged = set(before) - {'public._goufayu_migrations', 'public.archive_config_sets'}
    need(all(after[name] == before[name] for name in unchanged), 'original_player_or_payment_rows_changed')
    need(set(after) - set(before) <= {'public.player_onboarding_state'}, 'unexpected_new_table')
    after_state = state(conn)
    old_state = PLAN['database_state']
    changed = {key for key, value in old_state['functions'].items() if after_state['functions'].get(key) != value}
    need(changed == {'match_profile_login(text,text,text,jsonb)', 'archive_sync_config(text,jsonb)'}, 'unexpected_existing_function_change')
    need(set(after_state['functions']) - set(old_state['functions']) == {
        'initialize_player_onboarding()', 'onboarding_state(text,text)', 'onboarding_finish(text,text,text)',
        'archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)'}, 'unexpected_new_function')
    need(all(after_state['configs'].get(key) == value for key, value in old_state['configs'].items())
         and set(after_state['configs']) == set(old_state['configs']) | {HASH}, 'old_configs_changed')
    need(after_state['ledger'] == {**old_state['ledger'], **{m['id']:m['sha256'] for m in PLAN['migrations']}}, 'old_ledger_changed')
    return dict(ok=True, bundle=HASH, config_digest=digest,
                existing_tables_unchanged=len(unchanged), new_migrations=len(PLAN['migrations']))


def dump(name, *, schema_only=False):
    target = STAGE / (name + '.dump')
    need(not target.exists(), 'new_backup_required')
    password = Path('/etc/goufayu-ws4/admin-password').read_text().strip()
    arguments = ['podman', 'exec', '-i', '--env', 'PGPASSWORD', 'goufayu-ws4-db',
                   'pg_dump', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'goufayu_ws4',
                   '-Fc']
    if schema_only:
        arguments.append('--schema-only')
    raw = command(arguments, env={**os.environ, 'PGPASSWORD': password})
    need(raw.startswith(b'PGDMP') and len(raw) < 128 * 1024 * 1024, 'backup_format_or_size_invalid')
    with target.open('xb') as stream:
        stream.write(raw)
    target.chmod(0o600)
    return dict(path=str(target), bytes=len(raw), sha256=sha(raw), at=time.time())


def clone():
    from psycopg import sql
    verify_source()
    need((STAGE / 'prepared.json').exists(), 'preparation_required')
    backup = dump('schema_clone_source_' + secrets.token_hex(6), schema_only=True)
    name = 'goufayu_ws4_catalog_' + secrets.token_hex(6)
    with connect(autocommit=True) as admin:
        admin.execute(sql.SQL('CREATE DATABASE {} OWNER goufayu_owner TEMPLATE template0').format(sql.Identifier(name)))
    with connect(name, autocommit=True) as empty:
        need(empty.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema'").fetchone()[0] == 0,
             'new_clone_not_empty')
        need(empty.execute("SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='public')").fetchone()[0],
             'default_public_schema_required')
    password = Path('/etc/goufayu-ws4/admin-password').read_text().strip()
    container_dump = '/tmp/' + name + '.dump'
    command(['podman', 'exec', 'goufayu-ws4-db', 'test', '!', '-e', container_dump])
    command(['podman', 'cp', backup['path'], 'goufayu-ws4-db:' + container_dump])
    toc = command(['podman', 'exec', 'goufayu-ws4-db', 'pg_restore', '--list', container_dump])
    need(b'TABLE DATA' not in toc and b'SEQUENCE SET' not in toc, 'schema_archive_must_not_include_player_data')
    command(['podman', 'exec', '--env', 'PGPASSWORD', 'goufayu-ws4-db',
             'pg_restore', '-h', '127.0.0.1', '-U', 'postgres', '-d', name,
             '--exit-on-error', '--single-transaction', container_dump],
            env={**os.environ, 'PGPASSWORD': password})
    with connect(name) as conn:
        # Seed only public immutable configuration metadata, never player,
        # account, wallet, receipt, sequence or payment table rows.
        from psycopg.types.json import Jsonb
        need(not PLAN['database_state']['ledger'], 'empty_original_migration_ledger_required')
        with connect() as live:
            live.execute('SET TRANSACTION READ ONLY')
            configs = live.execute('SELECT config_hash,config FROM public.archive_config_sets').fetchall()
        need({key for key, value in configs} == set(PLAN['database_state']['configs']), 'public_configs_changed')
        for key, value in configs:
            conn.execute('INSERT INTO public.archive_config_sets(config_hash,config) VALUES(%s,%s)', (key, Jsonb(value)))
        conn.commit()
        # Restore owners and ACLs from the actual schema, unchanged.
        result = migrate(conn)
        conn.commit()
        probe_name = PLAN.get('runtime_probe_file', 'runtime_probe.py')
        need(re.fullmatch(r'runtime_probe(?:_ws4)?\.py', probe_name)
             and sha((STAGE / probe_name).read_bytes()) == PLAN['files'][probe_name], 'sealed_runtime_probe_changed')
        spec = importlib.util.spec_from_file_location('ws4_catalog_runtime_probe', STAGE / probe_name)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        result['runtime'] = module.run(conn, NEW)
        conn.rollback()
    # Preserve this clone and both dumps as recovery/validation artifacts.
    result.update(clone=name, backup=backup, status='SCHEMA_CLONE_VALIDATED_LIVE_UNCHANGED', live_changed=False,
                  production_player_data_copied=False, public_config_rows=len(configs))
    return save('validated_clone', result)


def control(action):
    need(action in ('start', 'stop'), 'invalid_service_action')
    command(['systemctl', action, 'goufayu-ws4.service'])


def quiesce():
    verify_source()
    need((STAGE / 'validated_clone.json').is_file(), 'clone_validation_required')
    with connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); pending(conn)
        need(state(conn) == PLAN['database_state'], 'database_baseline_changed')
    control('stop')
    try:
        with connect() as conn:
            conn.execute('SET TRANSACTION READ ONLY'); pending(conn)
        result = dump('final_backup')
        return save('final_backup', result)
    except Exception:
        control('start')
        raise


def launch_bytes(root):
    need(root in (NEW, SAFE), 'release_scope_invalid')
    original_unit = (STAGE / 'unit.original').read_bytes()
    original_env = (STAGE / 'env.original').read_bytes()
    unit, count = re.subn(rb'(?m)^(\s*WorkingDirectory=)[^\r\n]+',
                         lambda m: m[1] + str(root / 'backend').encode(), original_unit)
    need(count == 1, 'unit_workdir_anchor_invalid')
    env, count = re.subn(rb'(?m)^(SURVIVAL_ADDON_ROOT=)[^\r\n]+',
                        lambda m: m[1] + json.dumps(str(root / 'addon')).encode(), original_env)
    need(count == 1, 'addon_root_anchor_invalid')
    return unit, env


def switch(root):
    unit, env = launch_bytes(root)
    for target, raw in ((UNIT, unit), (ENV, env)):
        info = target.stat(); temporary = target.with_name(target.name + '.ws4-catalog-' + secrets.token_hex(6))
        with temporary.open('xb') as stream:
            stream.write(raw); stream.flush(); os.fsync(stream.fileno())
        temporary.chmod(info.st_mode & 0o777); os.chown(temporary, info.st_uid, info.st_gid)
        os.replace(temporary, target)
    command(['systemctl', 'daemon-reload'])


def health(expected):
    import urllib.request
    # The Workshop wrapper accepts pinned upstream credentials, not the base
    # API's FISHING_API_TOKEN. Reuse the existing approved sidecar identity.
    pid = command(['systemctl', 'show', 'goufayu-ws4-web.service', '--property=MainPID', '--value']).decode().strip()
    need(pid.isdigit() and int(pid) > 1, 'approved_upstream_not_running')
    values = dict(row.split(b'=', 1) for row in Path('/proc/' + pid + '/environ').read_bytes().split(b'\x00') if b'=' in row)
    token = values[b'PLAYER_WEB_AUTH_UPSTREAM_BEARER'].decode('ascii')
    pins = json.loads(Path('/etc/goufayu-ws4/pins.json').read_bytes())
    need(pins.get('workshop_id') == '3824360109' and sha(token.encode('ascii')) in pins.get('sha256', []),
         'approved_upstream_pin_required')
    for attempt in range(20):
        try:
            request = urllib.request.Request('http://127.0.0.1:18765/v1/archive/config', data=b'{}',
                headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
            with urllib.request.urlopen(request, timeout=3) as response:
                result = json.load(response)
            if result.get('ok') and result.get('config_hash') == expected:
                return True
        except Exception:
            pass
        time.sleep(.5)
    raise RuntimeError('ws4_expected_bundle_not_healthy')


def activate():
    verify_source()
    need((STAGE / 'validated_clone.json').is_file(), 'clone_validation_required')
    backup = json.loads((STAGE / 'final_backup.json').read_bytes())
    ack = json.loads((STAGE / 'offsite_ack.json').read_bytes())
    need(ack['encrypted_verified'] and ack['sha256'] == backup['sha256']
         and sha(Path(backup['path']).read_bytes()) == backup['sha256']
         and time.time() - backup['at'] < 900, 'verified_fresh_offsite_backup_required')
    need(command(['systemctl', 'show', 'goufayu-ws4.service', '--property=ActiveState', '--value']).decode().strip() == 'inactive', 'ws4_must_be_quiesced')
    committed = False
    try:
        with connect() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ'); pending(conn)
            result = migrate(conn); conn.commit(); committed = True
        switch(NEW); control('start'); health(HASH)
        need(services() == PLAN['retained_services'], 'retained_service_changed')
        return save('activated', dict(**result, status='LIVE_WS4_CATALOG_SYNCHRONIZED', payment_untouched=True))
    except Exception:
        # Preserve new receipts/data. Never restore a database dump over live rows.
        if committed:
            control('stop'); switch(SAFE); control('start'); health(PLAN['old_bundle'])
        else:
            UNIT.write_bytes((STAGE / 'unit.original').read_bytes())
            ENV.write_bytes((STAGE / 'env.original').read_bytes())
            command(['systemctl', 'daemon-reload']); control('start')
        save('activation_failure', dict(status='SAFE_RECOVERY', database_commit_acknowledged=committed,
                                       database_restored=False, player_data_preserved=True))
        raise


def resume():
    # A failed backup/ack must not strand the old API in maintenance.
    need(services() == PLAN['retained_services'], 'retained_service_changed')
    with connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        before_migration = state(conn) == PLAN['database_state']
    if before_migration:
        need(sha(UNIT.read_bytes()) == PLAN['unit_sha256'] and sha(ENV.read_bytes()) == PLAN['env_sha256'],
             'old_launch_baseline_changed')
        control('start'); health(PLAN['old_bundle'])
    else:
        need((STAGE / 'activation_failure.json').is_file(), 'unowned_database_change')
        control('stop'); switch(SAFE); control('start'); health(PLAN['old_bundle'])
    return dict(status='WS4_API_RESUMED', database_restored=False)


def reconcile_activation():
    # v6's wrong health credential triggered a disk-only fallback: systemctl
    # start on the already-running NEW process did not restart it. Only repair
    # that exact state, without another migration or a running API restart.
    verify_source(launch_root=SAFE)
    validated = json.loads((STAGE / 'validated_clone.json').read_bytes())
    backup = json.loads((STAGE / 'final_backup.json').read_bytes())
    ack = json.loads((STAGE / 'offsite_ack.json').read_bytes())
    need(ack['encrypted_verified'] and ack['sha256'] == backup['sha256']
         and sha(Path(backup['path']).read_bytes()) == backup['sha256'], 'verified_offsite_backup_required')
    need(sha((STAGE / 'unit.original').read_bytes()) == PLAN['unit_sha256']
         and sha((STAGE / 'env.original').read_bytes()) == PLAN['env_sha256'], 'original_launch_backup_changed')
    with connect() as live, connect(validated['clone']) as clone_conn:
        live.execute('SET TRANSACTION READ ONLY'); clone_conn.execute('SET TRANSACTION READ ONLY')
        need(state(live) == state(clone_conn), 'validated_contract_state_required')
    for name, digest in json.loads((SOURCE / 'release_manifest.json').read_bytes())['files'].items():
        path = NEW / name
        need(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(NEW)
             and sha(path.read_bytes()) == PLAN['ws4_wrappers'].get(name, digest), 'candidate_source_changed')
    for name, digest in PLAN['ws4_wrappers'].items():
        need(sha((NEW / name).read_bytes()) == digest, 'candidate_auth_wrapper_changed')
    pid = command(['systemctl', 'show', 'goufayu-ws4.service', '--property=MainPID', '--value']).decode().strip()
    need(pid.isdigit() and int(pid) > 1 and Path('/proc/' + pid + '/cwd').resolve() == NEW / 'backend',
         'new_process_must_already_be_running')
    environment = dict(row.split(b'=', 1) for row in Path('/proc/' + pid + '/environ').read_bytes().split(b'\x00') if b'=' in row)
    need(environment.get(b'SURVIVAL_ADDON_ROOT') == str(NEW / 'addon').encode(), 'new_runtime_root_required')
    health(HASH)
    switch(NEW); health(HASH)
    need(services() == PLAN['retained_services'] and pid == command([
        'systemctl', 'show', 'goufayu-ws4.service', '--property=MainPID', '--value']).decode().strip(),
         'retained_service_changed')
    return save('activated', dict(ok=True, status='LIVE_WS4_CATALOG_SYNCHRONIZED', bundle=HASH,
        config_digest=validated['config_digest'], existing_tables_unchanged=validated['existing_tables_unchanged'],
        new_migrations=validated['new_migrations'], payment_untouched=True, health_credential_corrected=True,
        running_api_restarted=False, database_reapplied=False))


def run(action):
    import fcntl
    need(STAGE.parent == Path('/root/goufayu_upload') and not STAGE.is_symlink(), 'stage_scope_invalid')
    with (STAGE / 'operator.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return {'prepare': prepare, 'clone': clone, 'quiesce': quiesce, 'activate': activate, 'resume': resume,
                'reconcile': reconcile_activation}[action]()
