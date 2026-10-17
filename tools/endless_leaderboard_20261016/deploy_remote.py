"""Hash-pinned, additive archive leaderboard deployment (root executes only).

No payment service restart, gateway request, real login or player command.
Validation rolls back migration and all fixtures. Activation stops the archive
API before granting new RPCs and pairs rollback business code with the new RPC
allowlist, preserving the additive SQL and every legitimate account change.
"""
from __future__ import annotations

import argparse
import ast
import contextlib
import copy
from datetime import datetime, timezone
import fcntl
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request

STAGE = Path(__file__).resolve().parent
BASE = Path('/opt/goufayu/releases')
OLD = BASE / '20261016-endless-titles-v1'
TARGET = BASE / '20261016-endless-leaderboard-v1'
ROLLBACK = BASE / '20261016-endless-leaderboard-rollback-v1'
PAY = Path('/opt/goufayu/payments/20261015-payment02')
BUNDLE = '60d6ce00a7d3257b6982492fdfdf68aa8deacdb4d46f837248ecfbef5ebdec94'
OLD_MANIFEST = '1c6d4ba19d44d059e8630369a4e388018344241fac27e7efd3e6230b96041e62'
PAY_MANIFEST = 'ab18979b1194a3a3877b3a0635ff9f970e2838ff97783227d2e27a06571b1419'
CASH_HASH = 'b56e72aaf6b1cd512ada1f5fe460be98a2f871e7d5dc1b7131701fb4654f4cbe'
SYNC_SHA = '2bc0a1e239f8e134b01293e5782f09cd9ad78cda4cab44b657f07ba44f3d7bad'
APPLY_SHA = '6bef548e25b839749ce042748aa3f79ad5ae43c6fa898bedd785c9b940f038f5'
SYNC = 'public.archive_sync_config(text,jsonb)'
APPLY = 'payments.apply_effects(text,jsonb,boolean)'
IDENTITY = 'public.archive_leaderboard_identities'
TARGET_FILES = {'backend/fishing_api/server.py', 'backend/fishing_api/postgres.py',
                'backend/archive_backend/service.py', 'backend/archive_backend/endless_leaderboard.py'}
ROLLBACK_FILES = {'backend/fishing_api/postgres.py'}
NEW_FUNCTIONS = {'public.archive_seed_leaderboard_identity()',
                 'public.archive_leaderboard_integer(jsonb)',
                 'public.archive_bind_leaderboard_identity(text,text)',
                 'public.archive_endless_leaderboard()'}
NEW_RELATIONS = {'public.archive_leaderboard_identities',
    'public.archive_leaderboard_identities_pkey',
    'public.archive_leaderboard_identities_entry_id_key',
    'public.archive_leaderboard_identities_public_account_id_key',
    'public.player_archive_endless_leaderboard_idx'}
NEW_TRIGGER = 'public.player_archive_state:archive_seed_leaderboard_identity'
EXPECTED_PLAN_SHA = None
EXPECTED_OPERATOR_SHA = None


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def stamp(value):
    return {**value, 'plan_sha256': EXPECTED_PLAN_SHA, 'operator_sha256': EXPECTED_OPERATOR_SHA}


def save(name, value):
    path = STAGE / name
    need(not path.is_symlink(), 'report_symlink_refused')
    temporary = path.with_name(path.name + '.' + secrets.token_hex(4))
    with temporary.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(stamp(value), stream, ensure_ascii=False, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    temporary.chmod(0o600)
    os.replace(temporary, path)


def record(name):
    value = json.loads((STAGE / name).read_bytes())
    need(value.get('plan_sha256') == EXPECTED_PLAN_SHA
         and value.get('operator_sha256') == EXPECTED_OPERATOR_SHA, 'phase_record_changed:' + name)
    return value


def relative(name):
    need(isinstance(name, str), 'payload_name_type_invalid')
    value = PurePosixPath(name)
    need(name and not value.is_absolute() and '..' not in value.parts
         and '\\' not in name and ':' not in name and value.as_posix() == name,
         'unsafe_relative_path')
    return value


def plan():
    need(EXPECTED_PLAN_SHA and sha(STAGE / 'release_plan.json') == EXPECTED_PLAN_SHA,
         'release_plan_changed')
    need(EXPECTED_OPERATOR_SHA and sha(__file__) == EXPECTED_OPERATOR_SHA,
         'deployment_operator_changed')
    value = json.loads((STAGE / 'release_plan.json').read_bytes())
    expected = {'version': 1, 'kind': 'endless_leaderboard_readonly', 'old_release': str(OLD),
        'target_release': str(TARGET), 'rollback_release': str(ROLLBACK), 'old_manifest': OLD_MANIFEST,
        'bundle': BUNDLE, 'payment_release': str(PAY), 'payment_manifest': PAY_MANIFEST,
        'payment_catalog_hash': CASH_HASH, 'old_sync_function': SYNC_SHA, 'old_apply_function': APPLY_SHA}
    need(all(value.get(k) == v for k, v in expected.items()), 'reviewed_plan_baseline_differs')
    need(re.fullmatch('[0-9a-f]{64}', str(value.get('tar_sha256', ''))), 'plan_tar_digest_invalid')
    for key in ('files', 'target_files', 'rollback_files'):
        need(isinstance(value.get(key), dict) and bool(value[key]), 'plan_file_map_invalid:' + key)
        for name, digest in value[key].items():
            relative(name)
            need(re.fullmatch('[0-9a-f]{64}', str(digest)), 'plan_digest_invalid:' + name)
    need(set(value['target_files']) == TARGET_FILES
         and set(value['rollback_files']) == ROLLBACK_FILES, 'plan_changed_file_set_invalid')
    expected_payload = {'overlay/' + p for p in TARGET_FILES} | {
        'rollback_overlay/' + p for p in ROLLBACK_FILES} | {'migration_body.sql', 'test_database.py'}
    need(set(value['files']) == expected_payload, 'plan_payload_set_invalid')
    for key, prefix in (('target_files', 'overlay/'), ('rollback_files', 'rollback_overlay/')):
        need(all(value['files'][prefix + p] == digest for p, digest in value[key].items()),
             'overlay_and_release_digest_disagree')
    need(value['target_files']['backend/fishing_api/postgres.py']
         == value['rollback_files']['backend/fishing_api/postgres.py'], 'rollback_allowlist_differs')
    return value


def check_files(root, files):
    for name, expected in files.items():
        path = root.joinpath(*relative(name).parts)
        need(not any(p.is_symlink() for p in (path, *path.parents) if p != root.parent),
             'manifest_symlink_refused')
        need(path.is_file() and sha(path) == expected, 'file_digest_changed:' + name)


def current(directory):
    plan()
    need((BASE / 'current').is_symlink() and (BASE / 'current').resolve() == directory,
         'archive_current_changed')
    need((PAY.parent / 'current').is_symlink() and (PAY.parent / 'current').resolve() == PAY,
         'payment_current_changed')


def baseline():
    plan()
    need(sha(OLD / 'release_manifest.json') == OLD_MANIFEST, 'baseline_manifest_changed')
    metadata = json.loads((OLD / 'release_manifest.json').read_bytes())
    check_files(OLD, metadata['files'])
    need(json.loads((OLD / 'addon/server/bundles/current.json').read_bytes())['hash'] == BUNDLE,
         'baseline_bundle_changed')
    need(sha(PAY / 'manifest.json') == PAY_MANIFEST, 'payment_manifest_changed')
    check_files(PAY, json.loads((PAY / 'manifest.json').read_bytes()))
    with contextlib.redirect_stdout(io.StringIO()):
        load('ranking_baseline_manage', OLD / 'deploy/manage.py').validated_release(str(OLD))
    return metadata


def payment_deploy():
    return load('ranking_backup_connection', PAY / 'deploy.py')


def table_names(connection):
    return connection.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()


def table_state(connection, names=None):
    from psycopg import sql
    result = {}
    for schema, name in names if names is not None else table_names(connection):
        result[schema + '.' + name] = connection.execute(sql.SQL(
            "SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t"
        ).format(sql.Identifier(schema), sql.Identifier(name))).fetchone()
    return result


def function_state(connection):
    rows = connection.execute("""SELECT n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')',
        pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.prosecdef,p.proconfig,p.proacl::text
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','payments') AND p.prokind='f'
        AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
          AND d.objid=p.oid AND d.deptype='e') ORDER BY 1""").fetchall()
    return {name.replace(', ', ','): {'definition_sha256': hashlib.sha256(text.encode()).hexdigest(),
        'owner': owner, 'security_definer': definer, 'configuration': config, 'acl': acl}
        for name, text, owner, definer, config, acl in rows}


def schema_state(connection):
    relations = connection.execute("""SELECT n.nspname||'.'||c.relname,c.relkind,
        pg_get_userbyid(c.relowner),c.relrowsecurity,c.relforcerowsecurity,c.relacl::text
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','payments') ORDER BY 1""").fetchall()
    triggers = connection.execute("""SELECT n.nspname||'.'||c.relname||':'||t.tgname,
        pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','payments') AND NOT t.tgisinternal ORDER BY 1""").fetchall()
    return {'relations': {row[0]: list(row[1:]) for row in relations},
            'triggers': dict(triggers)}


def reject_existing_objects(connection):
    schema = schema_state(connection)
    need(not (set(schema['relations']) & NEW_RELATIONS)
         and NEW_TRIGGER not in schema['triggers'], 'leaderboard_relation_or_trigger_already_exists')
    names = {f.split('(')[0] for f in NEW_FUNCTIONS}
    existing = function_state(connection)
    need(not any(f.split('(')[0] in names for f in existing), 'leaderboard_function_name_already_exists')
    return schema


def invariants(connection):
    need(connection.execute('SELECT current_database()').fetchone()[0] == 'goufayu_test', 'unexpected_database')
    functions = function_state(connection)
    need(functions[SYNC]['definition_sha256'] == SYNC_SHA, 'archive_sync_function_changed')
    need(functions[APPLY]['definition_sha256'] == APPLY_SHA, 'payment_function_changed')
    need(connection.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0] == CASH_HASH,
         'payment_catalog_changed')
    need(connection.execute('SELECT count(*) FROM payments.products WHERE enabled').fetchone()[0] == 44,
         'payment_product_count_changed')
    return functions


def health():
    result = {}
    for name, port in (('archive', 8765), ('payment', 8766)):
        with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=5) as response:
            value = json.load(response)
            need(response.status == 200 and value.get('ok') is True, 'health_failed:' + name)
            result[name] = {'ok': True, 'service': value.get('service')}
    return result


def backup():
    current(OLD)
    metadata = baseline()
    health()
    directory = Path('/var/backups/goufayu-endless-leaderboard') / EXPECTED_PLAN_SHA
    need(not directory.exists() and not directory.is_symlink(), 'backup_already_exists')
    directory.mkdir(parents=True, mode=0o700)
    directory.chmod(0o700)
    with payment_deploy().connection() as connection:
        connection.execute('SET TRANSACTION READ ONLY')
        functions = invariants(connection)
        names = table_names(connection)
        need(len(names) == 28 and IDENTITY not in {'.'.join(n) for n in names}, 'baseline_table_set_changed')
        need(not (set(functions) & NEW_FUNCTIONS), 'leaderboard_function_already_exists')
        reject_existing_objects(connection)
        connection.rollback()
    with tarfile.open(directory / 'release_sources.tar.gz', 'x:gz') as archive:
        for name in [*metadata['files'], 'release_manifest.json']:
            archive.add(OLD / name, arcname='archive/' + name, recursive=False)
    (directory / 'release_sources.tar.gz').chmod(0o600)
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        payment_deploy().backup()
    details = json.loads(captured.getvalue().splitlines()[-1])
    dump = Path(details['local_backup'])
    need(dump.is_file() and dump.stat().st_size > 0
         and dump.with_suffix('.sha256').read_text().strip() == sha(dump), 'database_backup_invalid')
    result = {'status': 'BACKED_UP', 'created_utc': datetime.now(timezone.utc).isoformat(),
        'directory': str(directory), 'database_backup': str(dump), 'database_sha256': sha(dump),
        'source_backup': str(directory / 'release_sources.tar.gz'),
        'source_sha256': sha(directory / 'release_sources.tar.gz'),
        'old_functions': functions, 'old_tables': names, 'offsite': False}
    save('backup.json', result)
    (directory / 'backup.json').write_text(json.dumps(stamp(result), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (directory / 'backup.json').chmod(0o600)
    return result


def backup_verified():
    result = record('backup.json')
    need(sha(result['database_backup']) == result['database_sha256']
         and sha(result['source_backup']) == result['source_sha256'], 'backup_changed')
    return result


def unpack():
    data = plan()
    archive_path, directory = STAGE / 'overlay.tar.gz', STAGE / 'payload'
    need(sha(archive_path) == data['tar_sha256'], 'uploaded_tar_changed')
    need(not directory.exists() and not directory.is_symlink(), 'payload_already_exists')
    directory.mkdir(mode=0o700)
    with tarfile.open(archive_path, 'r:gz') as archive:
        seen = set()
        for member in archive.getmembers():
            relative(member.name)
            need(member.isfile() and member.name not in seen, 'unsafe_tar_member')
            seen.add(member.name)
            need(member.name in data['files'], 'unapproved_tar_member')
            target = directory / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as source, target.open('xb') as sink:
                shutil.copyfileobj(source, sink)
            target.chmod(0o600)
    need(seen == set(data['files']), 'payload_file_set_changed')
    check_files(directory, data['files'])


def clone(destination, original, overlay_name, selected):
    data = plan()
    need(not destination.exists() and not destination.is_symlink(), 'release_destination_exists')
    destination.mkdir(mode=0o755)
    for name in original['files']:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(OLD / name, target)
    for name in selected:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(STAGE / 'payload' / overlay_name / name, target)
    changed = {name for name, digest in original['files'].items() if sha(destination / name) != digest}
    added = set(selected) - set(original['files'])
    need(changed == set(selected) - added, 'unapproved_release_change')
    need(json.loads((destination / 'addon/server/bundles/current.json').read_bytes())['hash'] == BUNDLE,
         'prepared_bundle_changed')
    metadata = copy.deepcopy(original)
    metadata.update(release=destination.name, previous_release=OLD.name,
        description='Additive endless leaderboard; original economic reducers and immutable bundles retained')
    metadata['files'] = {p.relative_to(destination).as_posix(): sha(p)
                         for p in destination.rglob('*') if p.is_file()}
    (destination / 'release_manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for path in destination.rglob('*'):
        path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
    (destination / '.venv').symlink_to(OLD / '.venv', target_is_directory=True)
    with contextlib.redirect_stdout(io.StringIO()):
        load('ranking_validate_' + destination.name, destination / 'deploy/manage.py').validated_release(str(destination))
    return {'release': str(destination), 'manifest_sha256': sha(destination / 'release_manifest.json'),
            'changed_existing_files': sorted(changed), 'added_files': sorted(added)}


def prepare():
    current(OLD)
    original = baseline()
    backup_verified()
    unpack()
    data = plan()
    result = {'status': 'PREPARED_NOT_ACTIVATED',
        'target': clone(TARGET, original, 'overlay', data['target_files']),
        'rollback': clone(ROLLBACK, original, 'rollback_overlay', data['rollback_files'])}
    save('prepared.json', result)
    prepared()
    return result


def prepared():
    data = plan()
    original = baseline()
    backup_verified()
    saved = record('prepared.json')
    check_files(STAGE / 'payload', data['files'])
    for name, directory, chosen in (('target', TARGET, data['target_files']),
                                     ('rollback', ROLLBACK, data['rollback_files'])):
        need(sha(directory / 'release_manifest.json') == saved[name]['manifest_sha256'], 'prepared_manifest_changed')
        manifest = json.loads((directory / 'release_manifest.json').read_bytes())
        check_files(directory, manifest['files'])
        need(set(manifest['files']) == set(original['files']) | set(chosen), 'prepared_file_set_changed')
        for path, digest in original['files'].items():
            need(sha(directory / path) == chosen.get(path, digest), 'unapproved_prepared_file_change:' + path)
        check_files(directory, chosen)
        need(json.loads((directory / 'addon/server/bundles/current.json').read_bytes())['hash'] == BUNDLE,
             'prepared_bundle_hash_changed')
        with contextlib.redirect_stdout(io.StringIO()):
            load('ranking_prepared_' + name, directory / 'deploy/manage.py').validated_release(str(directory))
    old_service = (OLD / 'backend/archive_backend/service.py').read_text(encoding='utf-8')
    addition = ('    from .endless_leaderboard import install as install_endless_leaderboard\n'
                '    install_endless_leaderboard(service)\n')
    target_service = (TARGET / 'backend/archive_backend/service.py').read_text(encoding='utf-8')
    need(target_service.count(addition) == 1 and target_service.replace(addition, '', 1) == old_service,
         'archive_economic_service_changed')
    need((ROLLBACK / 'backend/archive_backend/service.py').read_text(encoding='utf-8') == old_service,
         'rollback_economic_service_changed')
    for directory in (TARGET, ROLLBACK):
        compile((directory / 'backend/fishing_api/postgres.py').read_text(encoding='utf-8'), '<postgres-rpc>', 'exec')


def runtime_probe(connection):
    """Check the target's exact guard SQL against uncommitted new functions.

    SET ROLE cannot change session_user on an administrative connection. This
    verifies that explicit, real difference and all effective-role checks; the
    subsequent live /ready uses a true app session for the unmodified full guard.
    """
    tree = ast.parse((TARGET / 'backend/fishing_api/postgres.py').read_text(encoding='utf-8'))
    selected = []
    names = {'Parameter', '_params', '_signature'}
    assignments = {'RPC_SIGNATURES', 'ALLOWED_FUNCTIONS', '_RUNTIME_CHECK', '_FUNCTION_CHECK'}
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in names:
            selected.append(node)
        elif isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in assignments for t in node.targets):
            selected.append(node)
    namespace = {'__name__': 'ranking_guard_' + secrets.token_hex(4)}
    from dataclasses import dataclass
    namespace['dataclass'] = dataclass
    sys.modules[namespace['__name__']] = type(sys)(namespace['__name__'])
    try:
        exec(compile(ast.Module(body=selected, type_ignores=[]), '<target-rpc-guard>', 'exec'), namespace)
    finally:
        del sys.modules[namespace['__name__']]
    allowed = list(namespace['ALLOWED_FUNCTIONS'])
    need({'public.archive_bind_leaderboard_identity(text,text)', 'public.archive_endless_leaderboard()'} <= set(allowed),
         'target_missing_new_rpc_allowlist')
    session = connection.execute('SELECT session_user::text').fetchone()[0]
    connection.execute('SAVEPOINT app_effective_role_probe')
    try:
        connection.execute('SET LOCAL ROLE goufayu_app')
        row = connection.execute(namespace['_RUNTIME_CHECK'], (allowed,)).fetchone()
        need(row and len(row) == 10 and row[0] == 'goufayu_app' and row[1] == session
             and row[2] == 'goufayu_test' and not any(row[3:]), 'target_effective_runtime_permissions_invalid')
        rows = connection.execute(namespace['_FUNCTION_CHECK'], (allowed,)).fetchall()
        need(len(rows) == len(allowed) and {r[0] for r in rows} == set(allowed)
             and all(r[1] is True for r in rows), 'target_rpc_function_permissions_invalid')
        value = connection.execute('SELECT public.archive_endless_leaderboard()').fetchone()[0]
        need(value.get('ok') is True and isinstance(value.get('entries'), list)
             and len(value['entries']) <= 100, 'live_ranking_read_invalid')
        count = len(value['entries'])
    finally:
        connection.execute('ROLLBACK TO SAVEPOINT app_effective_role_probe')
        connection.execute('RELEASE SAVEPOINT app_effective_role_probe')
    return {'effective_role': 'goufayu_app', 'administrative_session_preserved': True,
            'full_app_session_guard_pending_live_ready': True, 'rpc_count': len(allowed), 'public_rows': count}


def transaction(connection, publish):
    from psycopg import sql
    connection.execute('SET TRANSACTION ISOLATION LEVEL ' + ('READ COMMITTED' if publish else 'REPEATABLE READ'))
    connection.execute("SET LOCAL lock_timeout='5s'")
    connection.execute("SET LOCAL statement_timeout='90s'")
    connection.execute('SET ROLE goufayu_owner')
    for lock in ('payments.order_quantity.publish', 'payments.catalog.publish',
                 'survival.wife_collection.publish', 'survival.shop_catalog.publish',
                 'survival.endless_leaderboard.publish'):
        connection.execute('SELECT pg_advisory_xact_lock(hashtext(%s))', (lock,))
    names = table_names(connection)
    need(len(names) == 28 and IDENTITY not in {'.'.join(n) for n in names}, 'baseline_table_set_changed')
    reject_existing_objects(connection)
    if publish:
        connection.execute(sql.SQL('LOCK TABLE {} IN EXCLUSIVE MODE').format(sql.SQL(',').join(
            sql.Identifier(schema, name) for schema, name in names)))
    return names


def migration(connection):
    body = (STAGE / 'payload/migration_body.sql').read_text(encoding='utf-8')
    # The root strips transaction controls; never let a payload prematurely
    # commit a validation transaction or alter an existing function.
    need(not re.search(r'^\s*(BEGIN|COMMIT|ROLLBACK|END)\s*;\s*$', body, re.I | re.M),
         'migration_transaction_control_refused')
    connection.execute(body)


def check_migrated(connection, old_names, before_rows, before_functions, before_schema):
    names = table_names(connection)
    need({'.'.join(n) for n in names} == {'.'.join(n) for n in old_names} | {IDENTITY}, 'migration_table_set_invalid')
    need(table_state(connection, old_names) == before_rows, 'migration_changed_old_business_rows')
    functions = invariants(connection)
    need(set(functions) - set(before_functions) == NEW_FUNCTIONS
         and all(functions.get(name) == value for name, value in before_functions.items()),
         'migration_changed_old_function_definition_or_security')
    schema = schema_state(connection)
    need(set(schema['relations']) - set(before_schema['relations']) == NEW_RELATIONS
         and all(schema['relations'].get(k) == v for k, v in before_schema['relations'].items()),
         'migration_changed_old_relation_owner_rls_or_acl')
    need(set(schema['triggers']) - set(before_schema['triggers']) == {NEW_TRIGGER}
         and all(schema['triggers'].get(k) == v for k, v in before_schema['triggers'].items()),
         'migration_changed_existing_trigger')
    need(schema['relations'][IDENTITY][0] == 'r' and schema['relations'][IDENTITY][2] is True,
         'new_identity_table_rls_disabled')
    count = connection.execute('SELECT count(*) FROM public.archive_leaderboard_identities').fetchone()[0]
    archives = connection.execute('SELECT count(*) FROM public.player_archive_state').fetchone()[0]
    need(count == archives, 'historical_identity_seed_incomplete')
    need(connection.execute('SELECT count(*) FROM public.archive_leaderboard_identities WHERE public_account_id IS NOT NULL').fetchone()[0] == 0,
         'migration_invented_historical_public_identity')
    return {'old_tables_preserved': len(old_names), 'new_identity_rows': count,
            'new_table_count': 1, 'new_function_count': 4, 'old_functions_preserved': len(before_functions)}


def database_trial():
    current(OLD)
    with payment_deploy().connection() as connection:
        try:
            names = transaction(connection, False)
            functions, rows = invariants(connection), table_state(connection, names)
            schema = schema_state(connection)
            connection.execute('SAVEPOINT entire_leaderboard_migration_trial')
            migration(connection)
            checked = load('ranking_database_acceptance', STAGE / 'payload/test_database.py').run_checks(connection)
            need(checked.get('ok') is True and checked.get('groups', 0) >= 10
                 and checked.get('durable_player_changes') == 0, 'database_fixture_validation_failed')
            proof = check_migrated(connection, names, rows, functions, schema)
            guard = runtime_probe(connection)
            connection.execute('ROLLBACK TO SAVEPOINT entire_leaderboard_migration_trial')
            connection.execute('RELEASE SAVEPOINT entire_leaderboard_migration_trial')
            need(table_names(connection) == names and table_state(connection, names) == rows
                 and function_state(connection) == functions and schema_state(connection) == schema,
                 'migration_trial_not_fully_rolled_back')
            connection.rollback()
        except BaseException:
            connection.rollback()
            raise
    return {'status': 'PASS_ROLLED_BACK', 'checks': checked, 'proof': proof, 'runtime_probe': guard,
            'fixture_rows_committed': 0, 'schema_changes_committed': 0}


def validate():
    current(OLD)
    prepared()
    result = {'status': 'VALIDATED_NOT_ACTIVATED', 'database': database_trial()}
    save('validation.json', result)
    return result


def systemctl(action):
    result = subprocess.run(['systemctl', action, 'goufayu-api.service'], capture_output=True, timeout=35)
    need(result.returncode == 0, 'archive_service_' + action + '_failed')


def switch(directory):
    need(directory in (TARGET, ROLLBACK, OLD), 'switch_release_refused')
    temporary = BASE / ('.leaderboard-current-' + secrets.token_hex(6))
    temporary.symlink_to(directory, target_is_directory=True)
    os.replace(temporary, BASE / 'current')


def ready(directory):
    manage = load('ranking_live_readiness_' + directory.name, directory / 'deploy/manage.py')
    for attempt in range(25):
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                manage.health()
            pid = subprocess.run(['systemctl', 'show', 'goufayu-api.service', '--property=MainPID', '--value'],
                                 capture_output=True, text=True, check=True, timeout=5).stdout.strip()
            need(pid.isdigit() and int(pid) > 1, 'archive_pid_invalid')
            need(Path('/proc/' + pid + '/cwd').resolve() == directory / 'backend', 'archive_running_old_release')
            return
        except Exception:
            if attempt == 24:
                raise RuntimeError('archive_full_readiness_failed')
            time.sleep(0.5)


def committed_schema_state():
    """Resolve an ambiguous COMMIT using a fresh read-only connection.

    A lost COMMIT acknowledgement is not evidence of a rollback. All reviewed
    objects are in one database transaction, so only all-present/all-absent are
    accepted; a partial or unavailable result requires explicit recovery.
    """
    for attempt in range(3):
        try:
            with payment_deploy().connection() as connection:
                connection.execute('SET TRANSACTION READ ONLY')
                states = [connection.execute('SELECT to_regclass(%s) IS NOT NULL', (IDENTITY,)).fetchone()[0]]
                states += [connection.execute('SELECT to_regprocedure(%s) IS NOT NULL', (name,)).fetchone()[0]
                           for name in sorted(NEW_FUNCTIONS)]
                invariants(connection)
                connection.rollback()
            if all(states):
                return True
            if not any(states):
                return False
            raise RuntimeError('ambiguous_commit_partial_schema')
        except Exception:
            if attempt == 2:
                raise RuntimeError('ambiguous_commit_database_state_unavailable') from None
            time.sleep(0.5)


def recover(committed, commit_attempted):
    errors = []
    if commit_attempted and not committed:
        try:
            committed = committed_schema_state()
        except Exception:
            committed = None
            errors.append('database_commit_state_unconfirmed')
    # An unknown COMMIT state must never silently restore the old strict client.
    # Prefer compatible code, report the ambiguity, and let real readiness prove
    # whether the additive functions exist. No SQL is guessed or replayed here.
    recovery = OLD if committed is False else ROLLBACK
    actual = (BASE / 'current').resolve()
    if actual not in (OLD, TARGET, ROLLBACK):
        errors.append('archive_pointer_changed_by_external_actor')
    else:
        try:
            systemctl('stop')
        except Exception:
            errors.append('best_effort_recovery_stop_failed')
        try:
            switch(recovery)
        except Exception:
            errors.append('recovery_pointer_switch_failed')
        # Always attempt start, even if either the initial or recovery stop
        # failed. systemctl start is idempotent for an already running service.
        try:
            systemctl('start')
        except Exception:
            errors.append('recovery_start_failed')
        try:
            ready(recovery)
        except Exception:
            errors.append('recovery_full_readiness_failed')
    status = ('RECOVERY_REQUIRES_ATTENTION' if errors else
              'COMPAT_CODE_ROLLED_BACK' if committed else 'OLD_CODE_RESTARTED')
    result = {'status': status, 'database_migration_committed': committed,
        'commit_was_attempted': commit_attempted, 'current': str((BASE / 'current').resolve()),
        'recovery_errors': errors,
        'committed_additive_sql_and_legitimate_identity_rows_retained': committed is True}
    save('activation_failed.json', result)
    return result


def activate():
    current(OLD)
    prepared()
    need(record('validation.json').get('status') == 'VALIDATED_NOT_ACTIVATED', 'validation_required')
    committed, commit_attempted = False, False
    try:
        systemctl('stop')
        with payment_deploy().connection() as connection:
            try:
                names = transaction(connection, True)
                functions, rows = invariants(connection), table_state(connection, names)
                schema = schema_state(connection)
                migration(connection)
                proof = check_migrated(connection, names, rows, functions, schema)
                guard = runtime_probe(connection)
                current(OLD)
                commit_attempted = True
                connection.commit()
                committed = True
            except BaseException:
                connection.rollback()
                raise
        save('database_committed.json', {'status': 'COMMITTED', 'proof': proof, 'runtime_probe': guard,
             'old_business_rows_unchanged': True, 'real_player_commands': 0})
        switch(TARGET)
        systemctl('start')
        ready(TARGET)
        result = verify()
        result.update(status='DEPLOYED', previous_release=str(OLD), rollback_release=str(ROLLBACK),
                      backup=record('backup.json')['directory'])
        save('activated.json', result)
        return result
    except BaseException:
        recover(committed, commit_attempted)
        raise


def route_probe():
    manage = load('ranking_route_environment', TARGET / 'deploy/manage.py')
    config = manage.read_environment(Path('/etc/goufayu/api.env'))
    statuses = []
    for authorized in (False, True):
        headers = {'Content-Type': 'application/json'}
        if authorized:
            headers['Authorization'] = 'Bearer ' + config['FISHING_API_TOKEN']
        request = urllib.request.Request('http://127.0.0.1:8765/v1/archive/endless-leaderboard',
                                         data=b'{}', method='POST', headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                status, value = response.status, json.load(response)
        except urllib.error.HTTPError as error:
            status, value = error.code, json.load(error)
        need(status == 401 if not authorized else status in (400, 409), 'leaderboard_http_gate_invalid')
        need(value.get('ok') is False, 'invalid_probe_request_accepted')
        statuses.append(status)
    return {'unauthorized_status': statuses[0], 'authenticated_empty_payload_status': statuses[1],
            'real_login_or_account_supplied': False}


def verify():
    current(TARGET)
    prepared()
    ready(TARGET)
    with payment_deploy().connection() as connection:
        connection.execute('SET TRANSACTION READ ONLY')
        functions = invariants(connection)
        previous = record('backup.json')['old_functions']
        need(set(functions) - set(previous) == NEW_FUNCTIONS
             and all(functions.get(name) == value for name, value in previous.items()),
             'published_existing_function_changed')
        names = table_names(connection)
        need(len(names) == 29 and IDENTITY in {'.'.join(n) for n in names}, 'published_table_set_invalid')
        guard = runtime_probe(connection)
        connection.rollback()
    return {'status': 'VERIFIED', 'archive_release': str(TARGET), 'archive_bundle': BUNDLE,
        'payment_release': str(PAY), 'payment_catalog_hash': CASH_HASH, 'payment_enabled_products': 44,
        'health': health(), 'live_authenticated_full_runtime_guard': 'PASS',
        'effective_role_probe': guard, 'route_probe': route_probe(),
        'all_original_functions_unchanged': True, 'all_economic_reducers_retained': True,
        'cash_service_source_unchanged': True, 'fixture_rows_committed': 0,
        'real_login_commands': 0, 'gateway_requests': 0, 'nginx_modified': False}


def main():
    global EXPECTED_PLAN_SHA, EXPECTED_OPERATOR_SHA
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('backup', 'prepare', 'validate', 'activate', 'verify'))
    parser.add_argument('--plan-sha', required=True)
    parser.add_argument('--operator-sha', required=True)
    args = parser.parse_args()
    EXPECTED_PLAN_SHA, EXPECTED_OPERATOR_SHA = args.plan_sha, args.operator_sha
    need(os.geteuid() == 0 and STAGE == Path('/tmp/survival-endless-leaderboard-20261016-v2'),
         'approved_root_stage_required')
    os.umask(0o022)
    sys.dont_write_bytecode = True
    with open('/var/lock/goufayu-endless-leaderboard.lock', 'w') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        plan()
        result = globals()[args.action]()
        save(args.action + '_result.json', result)
        print(json.dumps(stamp(result), ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        code = str(error) if type(error) is RuntimeError and re.fullmatch(r'[a-zA-Z0-9_./:, -]{1,240}', str(error)) else type(error).__name__
        print(json.dumps({'status': 'FAILED', 'error': code}))
        sys.exit(1)
