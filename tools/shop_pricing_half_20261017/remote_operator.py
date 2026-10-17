"""Server-side scoped price publication. Fixtures always roll back before activation."""
from pathlib import Path
import contextlib
import copy
import hashlib
import io
import json
import os
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request

# TRANSPORT supplies STAGE, MODE and EXPECTED_TAR_SHA; never read credentials locally.
STAGE = Path(STAGE)
P = json.loads((STAGE / 'plan.json').read_bytes())
OLD_PAY = Path('/opt/goufayu/payments') / P['payment_baseline']
NEW_PAY = OLD_PAY.parent / P['payment_release']
OLD_ARCHIVE = Path('/opt/goufayu/releases') / P['archive_baseline']
NEW_ARCHIVE = OLD_ARCHIVE.parent / P['archive_release']
sys.path.insert(0, str(NEW_PAY if NEW_PAY.is_dir() else OLD_PAY))
from deploy import connection, backup


def need(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(name, value):
    path = STAGE / (name + '.json')
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str) + '\n')
    path.chmod(0o600)
    return value


def run(*args):
    result = subprocess.run(args, capture_output=True, timeout=120)
    need(result.returncode == 0, 'system_command_failed:' + args[0])
    return result.stdout.decode().strip()


def pointers(new=False):
    need(Path('/opt/goufayu/payments/current').resolve() == (NEW_PAY if new else OLD_PAY), 'payment_pointer_drift')
    need(Path('/opt/goufayu/releases/current').resolve() == (NEW_ARCHIVE if new else OLD_ARCHIVE), 'archive_pointer_drift')


def baseline(conn):
    pointers()
    need(sha(OLD_PAY / 'manifest.json') == P['payment_manifest_sha256'], 'payment_manifest_drift')
    need(sha(OLD_ARCHIVE / 'release_manifest.json') == P['archive_manifest_sha256'], 'archive_manifest_drift')
    need(conn.info.dbname == 'goufayu_test', 'database_scope_changed')
    for signature, digest in P['baseline_functions'].items():
        value = conn.execute('SELECT pg_get_functiondef(to_regprocedure(%s))', (signature,)).fetchone()[0]
        need(hashlib.sha256(value.encode()).hexdigest() == digest, 'payment_function_drift:' + signature)
    value = conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
    need(hashlib.sha256(value.encode()).hexdigest() == P['archive_sync_sha256'], 'archive_sync_function_drift')
    need(conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0] == P['baseline_catalog_hash'], 'payment_catalog_drift')


def table_state(conn):
    from psycopg import sql
    tables = conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('payments','public') ORDER BY 1,2").fetchall()
    return {s + '.' + t: conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(s), sql.Identifier(t))).fetchone() for s, t in tables}


def prepare():
    pointers()
    need(not NEW_PAY.exists() and not NEW_ARCHIVE.exists(), 'candidate_directory_exists')
    for name, digest in P['payment_files'].items():
        need(sha(STAGE / 'payment' / name) == digest, 'payment_payload_mismatch')
    NEW_PAY.mkdir(mode=0o755)
    for source in (STAGE / 'payment').rglob('*'):
        if source.is_file():
            destination = NEW_PAY / source.relative_to(STAGE / 'payment')
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination); destination.chmod(0o644)
    (NEW_PAY / '.venv').symlink_to(OLD_PAY / '.venv', target_is_directory=True)
    old_manifest = json.loads((OLD_ARCHIVE / 'release_manifest.json').read_bytes())
    NEW_ARCHIVE.mkdir(mode=0o755)
    for name, digest in old_manifest['files'].items():
        source = OLD_ARCHIVE / name
        need(sha(source) == digest and not source.is_symlink(), 'archive_baseline_file_drift:' + name)
        destination = NEW_ARCHIVE / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination); destination.chmod(source.stat().st_mode & 0o777)
    (NEW_ARCHIVE / '.venv').symlink_to(OLD_ARCHIVE / '.venv', target_is_directory=True)
    new_manifest = copy.deepcopy(old_manifest)
    for name, digest in P['archive_files'].items():
        source = STAGE / 'archive' / name
        need(sha(source) == digest, 'archive_payload_mismatch')
        destination = NEW_ARCHIVE / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination); destination.chmod(0o644)
        new_manifest['files'][name] = digest
    new_manifest.update(release=P['archive_release'], archive_bundle=P['bundle'])
    (NEW_ARCHIVE / 'release_manifest.json').write_text(json.dumps(new_manifest, ensure_ascii=False, indent=2) + '\n')
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    return save('prepared', dict(status='PREPARED', payment=NEW_PAY.name, archive=NEW_ARCHIVE.name, bundle=P['bundle'], orders_created=0))


def apply(conn):
    from psycopg.types.json import Jsonb
    from payment_backend.sync_catalog import apply as apply_catalog
    conn.execute('SET LOCAL ROLE goufayu_owner')
    conn.execute((NEW_PAY / 'payment_backend/upgrade_ucoin_rate_100.sql').read_text())
    package = json.loads((STAGE / 'payment_package.json').read_bytes())
    apply_catalog(conn, package)
    data = json.loads((NEW_ARCHIVE / 'addon/server/bundles' / P['bundle'] / 'bundle.json').read_bytes())
    config = dict(configs=data['configs'], compatible_config_hashes=data['compatible_config_hashes'])
    pg_sha = conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(config),)).fetchone()[0]
    old = (STAGE / 'archive_sync_before.sql').read_text()
    need(hashlib.sha256(old.encode()).hexdigest() == P['archive_sync_sha256'], 'archive_sync_backup_changed')
    marker = ' -- Reviewed endless titles:'
    need(old.count(marker) == 1, 'archive_sync_anchor_changed')
    branch = """ -- Reviewed half-price shop: one exact config and explicit parent commerce route.
 if p_hash='%s' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then
   raise exception 'archive_half_price_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
""" % (P['bundle'], pg_sha)
    conn.execute(old.replace(marker, branch + marker, 1))
    need(conn.execute('SELECT public.archive_sync_config(%s,%s)', (P['bundle'], Jsonb(config))).fetchone()[0]['ok'], 'archive_config_registration_failed')
    return dict(pg_config_sha256=pg_sha, catalog_hash=package['catalog_hash'])


def validate():
    need((STAGE / 'prepared.json').is_file(), 'prepare_required')
    from payment_backend.test_ucoin_rate_100_database import run_checks
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            baseline(conn); before = table_state(conn)
            result = apply(conn)
            stable = table_state(conn)
            conn.execute('SAVEPOINT synthetic_price_validation')
            checks = run_checks(conn)
            conn.execute('ROLLBACK TO SAVEPOINT synthetic_price_validation')
            need(table_state(conn) == stable, 'synthetic_validation_state_leaked')
            allowed = {'payments.products', 'payments.catalog_state', 'public.archive_config_sets'}
            need(all(before[k] == stable[k] for k in before if k not in allowed), 'validation_changed_player_or_order_state')
        finally:
            conn.rollback()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    return save('validated', dict(status='VALIDATED', **result, checks=checks, rolled_back=True, real_orders_created=0, gateway_requests=0))


def switch(current, target):
    path = current.with_name(current.name + '.shop-half.' + secrets.token_hex(4))
    path.symlink_to(target, target_is_directory=True); os.replace(path, current)


def health():
    result = {}
    for name, port in (('archive', 8765), ('payments', 8766)):
        with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=5) as response:
            body = json.load(response); need(response.status == 200 and body.get('ok') is True, 'health_failed:' + name)
            result[name] = True
    return result


def activate():
    need(json.loads((STAGE / 'validated.json').read_bytes())['rolled_back'] is True, 'validation_required')
    pointers()
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        backup()
    backup_record = json.loads(captured.getvalue().splitlines()[-1])
    save('backup', backup_record)
    run('systemctl', 'stop', 'goufayu-api.service', 'goufayu-payment.service')
    try:
        with connection() as conn:
            conn.execute("SET LOCAL lock_timeout='5s'")
            baseline(conn); before = table_state(conn)
            private = dict(products=[r[0] for r in conn.execute('SELECT to_jsonb(p) FROM payments.products p ORDER BY sku')],
                           catalog=conn.execute('SELECT to_jsonb(c) FROM payments.catalog_state c WHERE singleton').fetchone()[0])
            save('catalog_before', private)
            result = apply(conn)
            after = table_state(conn)
            allowed = {'payments.products', 'payments.catalog_state', 'public.archive_config_sets'}
            need(all(before[k] == after[k] for k in before if k not in allowed), 'activation_changed_player_or_order_rows')
        switch(Path('/opt/goufayu/payments/current'), NEW_PAY)
        switch(Path('/opt/goufayu/releases/current'), NEW_ARCHIVE)
        run('systemctl', 'start', 'goufayu-payment.service', 'goufayu-api.service')
        for attempt in range(30):
            try:
                healthy = health(); break
            except Exception:
                if attempt == 29:
                    raise
                time.sleep(.5)
    except Exception:
        # Never restore player/order tables or substitute an old reader after
        # new-rate orders can exist. Keep the compatible candidate for recovery.
        run('systemctl', 'start', 'goufayu-payment.service', 'goufayu-api.service')
        raise
    return save('activated', dict(status='ACTIVATED', **result, health=healthy, backup=backup_record,
                                  player_and_order_rows_preserved=True, real_orders_created=0, gateway_requests=0))


if MODE == 'prepare':
    report = prepare()
elif MODE == 'validate':
    report = validate()
elif MODE == 'activate':
    report = activate()
else:
    raise RuntimeError('invalid_operator_mode')
print(json.dumps(report, default=str))
