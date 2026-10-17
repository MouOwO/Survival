"""Exact monthly-pass publication; supplied MODE/STAGE never contact a gateway.

Transport verifies the reviewed archive before executing this file. Validation
uses nonce identities inside a savepoint and rolls back its entire transaction.
Activation only changes the one product's amount/description, catalog revision,
and additive archive configuration admission. Existing receipts stay frozen.
"""
from pathlib import Path, PurePosixPath
import contextlib
import copy
import hashlib
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

STAGE = Path(STAGE)
P = json.loads((STAGE / 'plan.json').read_bytes())
SKU = 'archive_pass_monthly'
OLD_PAY = Path('/opt/goufayu/payments') / P['payment_baseline']
NEW_PAY = OLD_PAY.parent / P['payment_release']
OLD_ARCHIVE = Path('/opt/goufayu/releases') / P['archive_baseline']
NEW_ARCHIVE = OLD_ARCHIVE.parent / P['archive_release']
sys.path.insert(0, str(OLD_PAY))
from deploy import connection, backup


def need(value, message):
    if not value:
        raise RuntimeError(message)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def row_sha(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def save(name, value):
    path = STAGE / (name + '.json')
    need(not path.is_symlink(), 'report_symlink_refused')
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str) + '\n')
    path.chmod(0o600)
    return value


def run(*args):
    result = subprocess.run(args, capture_output=True, timeout=120)
    need(result.returncode == 0, 'system_command_failed:' + args[0])
    return result.stdout.decode().strip()


def safe_path(root, relative):
    parts = PurePosixPath(relative)
    need(parts.as_posix() == relative and not parts.is_absolute() and '..' not in parts.parts
         and '\\' not in relative and ':' not in relative and bool(parts.parts), 'unsafe_manifest_path')
    result = root / relative
    need(all(not p.is_symlink() for p in [result, *result.parents] if p != root.parent), 'manifest_symlink_refused')
    return result


def manifest(root, archive=False):
    name = 'release_manifest.json' if archive else 'manifest.json'
    value = json.loads((root / name).read_bytes())
    files = value['files'] if archive else value
    need(isinstance(files, dict) and bool(files), 'empty_release_manifest')
    for relative, digest in files.items():
        need(re.fullmatch('[0-9a-f]{64}', digest) is not None, 'invalid_manifest_digest')
        need(sha(safe_path(root, relative)) == digest, 'release_file_drift:' + relative)
    return value


def pointers(new=False):
    need(Path('/opt/goufayu/payments/current').resolve() == (NEW_PAY if new else OLD_PAY), 'payment_pointer_drift')
    need(Path('/opt/goufayu/releases/current').resolve() == (NEW_ARCHIVE if new else OLD_ARCHIVE), 'archive_pointer_drift')


def payment_functions(conn):
    for signature, digest in P['baseline_functions'].items():
        value = conn.execute('SELECT pg_get_functiondef(to_regprocedure(%s))', (signature,)).fetchone()[0]
        need(value is not None and hashlib.sha256(value.encode()).hexdigest() == digest,
             'payment_function_drift:' + signature)


def monthly_row(conn):
    row = conn.execute('SELECT to_jsonb(p) FROM payments.products p WHERE sku=%s', (SKU,)).fetchone()
    need(row is not None, 'monthly_product_missing')
    return row[0]


def baseline(conn):
    pointers()
    need(sha(OLD_PAY / 'manifest.json') == P['payment_manifest_sha256'], 'payment_manifest_drift')
    need(sha(OLD_ARCHIVE / 'release_manifest.json') == P['archive_manifest_sha256'], 'archive_manifest_drift')
    need(conn.info.dbname == 'goufayu_test', 'database_scope_changed')
    payment_functions(conn)
    value = conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
    need(hashlib.sha256(value.encode()).hexdigest() == P['archive_sync_sha256'], 'archive_sync_function_drift')
    need(conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
         == P['baseline_catalog_hash'], 'payment_catalog_drift')
    old = monthly_row(conn)
    need(row_sha(old) == P['monthly_before_sha256'] and old['amount'] == 1000, 'monthly_product_drift')
    expected = copy.deepcopy(old)
    expected.update(amount=5800, description=old['description'].replace('10元', '58元', 1))
    need(old['description'].count('10元') == 1 and expected == P['monthly_product'], 'monthly_scope_invalid')
    need(expected['grants'].get('entitlement_days') == {'archive_pass': 30}
         and expected['purchase_limit'] == 0, 'monthly_entitlement_scope_changed')


def table_state(conn):
    from psycopg import sql
    tables = conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('payments','public') ORDER BY 1,2").fetchall()
    return {s + '.' + t: conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t")
            .format(sql.Identifier(s), sql.Identifier(t))).fetchone() for s, t in tables}


def others(conn):
    return conn.execute("SELECT count(*),md5(coalesce(string_agg(to_jsonb(p)::text,chr(10) ORDER BY sku),'')) FROM payments.products p WHERE sku<>%s", (SKU,)).fetchone()


def config_rows(conn):
    return {key: row_sha(value) for key, value in conn.execute('SELECT config_hash,config FROM public.archive_config_sets')}


def bundle_scope():
    parent = json.loads((OLD_ARCHIVE / 'addon/server/bundles' / P['parent_bundle'] / 'bundle.json').read_bytes())
    location = NEW_ARCHIVE / 'addon/server/bundles' / P['bundle'] / 'bundle.json'
    need(sha(location) == P['bundle'], 'candidate_bundle_digest_changed')
    data = json.loads(location.read_bytes())
    need(set(parent) == set(data), 'bundle_keys_changed')
    expected = copy.deepcopy(parent)
    old_daily = expected['configs']['archive_daily_rules']['rows']
    need(len(old_daily) == 1 and old_daily[0]['price_text'] == '10元', 'monthly_daily_baseline_changed')
    old_daily[0]['price_text'] = '58元'
    csv_name = 'data/csv/存档系统/archive_daily_rules.csv'
    expected['csv_hashes'][csv_name] = data['csv_hashes'][csv_name]
    old_aliases = expected.setdefault('compatible_config_hashes', {})
    alias = data['compatible_config_hashes'].get(P['parent_bundle'])
    allowed_commands = sorted({c for value in old_aliases.values() for c in value['commands']})
    need(alias == dict(commands=allowed_commands, upgrade_commands=['commerce_purchase']), 'monthly_parent_compatibility_changed')
    need(P['parent_bundle'] not in old_aliases, 'monthly_parent_alias_already_exists')
    old_aliases[P['parent_bundle']] = alias
    need(data == expected, 'unrelated_bundle_configuration_changed')
    return data


def candidate_scope():
    payment = manifest(NEW_PAY)
    old_payment = manifest(OLD_PAY)
    need(payment == P['payment_files'] and set(payment) >= set(old_payment), 'payment_candidate_manifest_changed')
    changed = {name for name in payment if payment[name] != old_payment.get(name)}
    need(changed == {'payment_backend/csv_catalog.py', 'reference_csv/商城支付系统/payment_products.csv'}, 'payment_source_scope_changed')
    archive = manifest(NEW_ARCHIVE, True)
    old_archive = manifest(OLD_ARCHIVE, True)
    expected = {**old_archive['files'], **P['archive_files']}
    need(archive['files'] == expected and archive['release'] == P['archive_release']
         and archive['archive_bundle'] == P['bundle'], 'archive_candidate_manifest_changed')
    bundle_scope()


def prepare():
    pointers()
    need(not NEW_PAY.exists() and not NEW_ARCHIVE.exists(), 'candidate_directory_exists')
    old_pay = manifest(OLD_PAY)
    old_archive = manifest(OLD_ARCHIVE, True)
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    for namespace, files in (('payment', P['payment_files']), ('archive', P['archive_files'])):
        for name, digest in files.items():
            need(sha(safe_path(STAGE / namespace, name)) == digest, 'candidate_payload_changed:' + name)
    for source_root, target_root, files in ((OLD_PAY, NEW_PAY, old_pay), (OLD_ARCHIVE, NEW_ARCHIVE, old_archive['files'])):
        target_root.mkdir(mode=0o755)
        for name in files:
            source = safe_path(source_root, name); target = safe_path(target_root, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target); target.chmod(source.stat().st_mode & 0o777)
        (target_root / '.venv').symlink_to(source_root / '.venv', target_is_directory=True)
    for namespace, target_root, files in (('payment', NEW_PAY, P['payment_files']), ('archive', NEW_ARCHIVE, P['archive_files'])):
        for name in files:
            target = safe_path(target_root, name); target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(safe_path(STAGE / namespace, name), target); target.chmod(0o644)
    pay_manifest = json.loads((STAGE / 'payment/manifest.json').read_bytes())
    need(pay_manifest == P['payment_files'], 'payment_payload_manifest_changed')
    (NEW_PAY / 'manifest.json').write_bytes((STAGE / 'payment/manifest.json').read_bytes())
    archive_manifest = copy.deepcopy(old_archive)
    archive_manifest['files'].update(P['archive_files'])
    archive_manifest.update(release=P['archive_release'], archive_bundle=P['bundle'])
    (NEW_ARCHIVE / 'release_manifest.json').write_text(json.dumps(archive_manifest, ensure_ascii=False, indent=2) + '\n')
    candidate_scope()
    return save('prepared', dict(status='PREPARED', payment=NEW_PAY.name, archive=NEW_ARCHIVE.name, bundle=P['bundle'], orders_created=0))


def apply(conn):
    from psycopg.types.json import Jsonb
    conn.execute('SET LOCAL ROLE goufayu_owner')
    conn.execute('LOCK TABLE payments.products,payments.catalog_state,public.archive_config_sets IN SHARE ROW EXCLUSIVE MODE')
    before_other = others(conn)
    before_catalog = conn.execute('SELECT to_jsonb(c) FROM payments.catalog_state c WHERE singleton').fetchone()[0]
    before_configs = config_rows(conn)
    need(P['bundle'] not in before_configs, 'candidate_configuration_already_registered')
    need(before_catalog['catalog_hash'] == P['baseline_catalog_hash'], 'catalog_revision_changed')
    baseline_product = monthly_row(conn)
    need(row_sha(baseline_product) == P['monthly_before_sha256'], 'monthly_product_changed_before_update')
    result = conn.execute('UPDATE payments.products SET amount=%s,description=%s WHERE sku=%s AND amount=1000',
                          (5800, P['monthly_product']['description'], SKU))
    need(result.rowcount == 1 and monthly_row(conn) == P['monthly_product'], 'monthly_exact_update_failed')
    need(others(conn) == before_other, 'other_product_rows_changed')
    result = conn.execute('UPDATE payments.catalog_state SET catalog_hash=%s WHERE singleton AND catalog_hash=%s',
                          (P['catalog_hash'], P['baseline_catalog_hash']))
    expected_catalog = {**before_catalog, 'catalog_hash': P['catalog_hash']}
    need(result.rowcount == 1 and conn.execute('SELECT to_jsonb(c) FROM payments.catalog_state c WHERE singleton').fetchone()[0]
         == expected_catalog, 'catalog_metadata_changed')
    data = bundle_scope()
    config = dict(configs=data['configs'], compatible_config_hashes=data['compatible_config_hashes'])
    pg_sha = conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(config),)).fetchone()[0]
    old = (STAGE / 'archive_sync_before.sql').read_text()
    need(hashlib.sha256(old.encode()).hexdigest() == P['archive_sync_sha256'], 'archive_sync_backup_changed')
    marker = ' -- Reviewed half-price shop:'
    need(old.count(marker) == 1, 'archive_sync_anchor_changed')
    branch = """ -- Reviewed 58-yuan monthly pass: one exact configuration, unchanged reward rules.
 if p_hash='%s' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then
   raise exception 'archive_monthly_58_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
""" % (P['bundle'], pg_sha)
    conn.execute(old.replace(marker, branch + marker, 1))
    need(conn.execute('SELECT public.archive_sync_config(%s,%s)', (P['bundle'], Jsonb(config))).fetchone()[0]['ok'],
         'archive_configuration_registration_failed')
    need(config_rows(conn) == {**before_configs, P['bundle']: row_sha(config)}, 'existing_archive_configuration_changed')
    payment_functions(conn)
    return dict(catalog_hash=P['catalog_hash'], monthly_amount_fen=5800, monthly_u_coin_price=5800,
                duration_days=30, pg_config_sha256=pg_sha, other_product_rows_preserved=True)


def synthetic_checks(conn):
    """Exercise the actual catalog/create/deliver routines in an outer savepoint."""
    from datetime import timedelta
    from psycopg.types.json import Jsonb
    from payment_backend.service import ucoin_quote
    need(ucoin_quote(5800) == dict(u_coin_price=5800, u_coin_per_yuan=100), 'python_monthly_quote_invalid')
    nonce = secrets.token_hex(16); session = 'monthly58_' + nonce
    digest = lambda value: hashlib.sha256(('monthly58:' + nonce + ':' + value).encode()).hexdigest()
    account = digest('account')
    need(not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (account,)).fetchone(), 'synthetic_identity_collision')
    defaults = conn.execute('SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules').fetchone()[0]
    conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)', (account, Jsonb(defaults)))
    need(conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s)', (account, session, 'standard', Jsonb(defaults))).fetchone()[0]['ok'], 'synthetic_login_failed')
    conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{}','{}')", (account,))
    def call(name, *args):
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]
    listed = next(p for p in call('catalog', account, session)['products'] if p['sku'] == SKU)
    need(listed['enabled'] and listed['amount_fen'] == listed['unit_amount_fen'] == listed['unit_u_coin_price'] == 5800,
         'sql_monthly_catalog_quote_invalid')
    provider = conn.execute("SELECT appid,mchid FROM payments.providers WHERE provider='wechat' AND enabled").fetchone()
    need(provider is not None, 'synthetic_provider_missing')
    def make(label):
        return call('create_order_quantity', account, session, 'WX' + digest('order:' + label)[:30], SKU, 'wechat', 1)
    def pay(order, label):
        transaction = '420000' + str(int(digest('tx:' + label)[:30], 16)).zfill(37)
        return call('deliver', order['order_id'], transaction, order['amount'], *provider)
    def expiry():
        return conn.execute("SELECT expires_at FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='archive_pass'", (account,)).fetchone()[0]
    now = conn.execute('SELECT now()').fetchone()[0]
    first = make('first')
    need(first['amount'] == 5800 and first['reward']['grants']['entitlement_days'] == {'archive_pass': 30}, 'synthetic_monthly_snapshot_invalid')
    need(pay(first, 'first')['state'] == 'delivered', 'synthetic_first_delivery_failed')
    original_expiry = expiry()
    need(original_expiry - now == timedelta(days=30), 'monthly_duration_changed')
    need(pay(first, 'first')['state'] == 'delivered' and expiry() == original_expiry, 'duplicate_delivery_extended_monthly')
    second = make('renewal')
    need(second['order_id'] != first['order_id'] and pay(second, 'renewal')['state'] == 'delivered', 'synthetic_renewal_failed')
    need(expiry() - original_expiry == timedelta(days=30), 'monthly_renewal_changed')
    return dict(sql_catalog_price_fen=5800, python_u_coin_price=5800, duration_days=30,
                renewal_adds_days=30, repeated_delivery_idempotent=True, synthetic_orders_created=2,
                synthetic_rows_rolled_back=True, gateway_requests=0)


def validate():
    need((STAGE / 'prepared.json').is_file(), 'prepare_required')
    candidate_scope()
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET LOCAL lock_timeout='5s'")
            baseline(conn); before = table_state(conn)
            result = apply(conn); stable = table_state(conn)
            conn.execute('SAVEPOINT monthly_58_synthetic')
            checks = synthetic_checks(conn)
            conn.execute('ROLLBACK TO SAVEPOINT monthly_58_synthetic')
            need(table_state(conn) == stable, 'synthetic_rows_leaked')
            allowed = {'payments.products', 'payments.catalog_state', 'public.archive_config_sets'}
            need(set(before) == set(stable) and all(before[k] == stable[k] for k in before if k not in allowed),
                 'validation_changed_existing_player_or_order_rows')
        finally:
            conn.rollback()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    return save('validated', dict(status='VALIDATED', **result, checks=checks, rolled_back=True,
                                  real_orders_created=0, gateway_requests=0))


def switch(current, target):
    path = current.with_name(current.name + '.monthly58.' + secrets.token_hex(4))
    path.symlink_to(target, target_is_directory=True); os.replace(path, current)


def health():
    result = {}
    for name, port in (('archive', 8765), ('payments', 8766)):
        with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=5) as response:
            body = json.load(response)
            need(response.status == 200 and body.get('ok') is True, 'health_failed:' + name)
            result[name] = True
    return result


def activate():
    validation = json.loads((STAGE / 'validated.json').read_bytes())
    need(validation.get('rolled_back') is True and validation.get('catalog_hash') == P['catalog_hash'], 'validation_required')
    candidate_scope(); pointers()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        backup()
    record = json.loads(captured.getvalue().splitlines()[-1]); save('backup', record)
    committed = False
    try:
        run('systemctl', 'stop', 'goufayu-api.service', 'goufayu-payment.service')
        with connection() as conn:
            conn.execute("SET LOCAL lock_timeout='5s'")
            baseline(conn); before = table_state(conn)
            save('monthly_before', dict(product=monthly_row(conn), catalog=conn.execute('SELECT to_jsonb(c) FROM payments.catalog_state c WHERE singleton').fetchone()[0]))
            result = apply(conn); after = table_state(conn)
            allowed = {'payments.products', 'payments.catalog_state', 'public.archive_config_sets'}
            need(set(before) == set(after) and all(before[k] == after[k] for k in before if k not in allowed),
                 'activation_changed_existing_player_or_order_rows')
        committed = True
        pointers()
        switch(Path('/opt/goufayu/payments/current'), NEW_PAY)
        switch(Path('/opt/goufayu/releases/current'), NEW_ARCHIVE)
        run('systemctl', 'start', 'goufayu-payment.service', 'goufayu-api.service')
        for attempt in range(30):
            try:
                healthy = health(); break
            except Exception:
                if attempt == 29:raise
                time.sleep(.5)
        pointers(True)
    except Exception:
        # A lost COMMIT acknowledgement is inspected, never guessed. This price
        # change needs no older reader; complete only our verified own pointers.
        try:
            with connection() as conn:
                conn.execute('SET TRANSACTION READ ONLY')
                published = monthly_row(conn) == P['monthly_product'] and conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0] == P['catalog_hash']
                conn.rollback()
            if published:
                for pointer, old, new in ((Path('/opt/goufayu/payments/current'), OLD_PAY, NEW_PAY),
                                          (Path('/opt/goufayu/releases/current'), OLD_ARCHIVE, NEW_ARCHIVE)):
                    need(pointer.resolve() in (old, new), 'recovery_pointer_changed_by_another_operator')
                    if pointer.resolve() == old:switch(pointer, new)
            save('activation_recovery', dict(commit_acknowledged=committed, candidate_published=published,
                 player_rows_restored=False, other_products_restored=False))
        finally:
            run('systemctl', 'start', 'goufayu-payment.service', 'goufayu-api.service')
        raise
    return save('activated', dict(status='ACTIVATED', **result, health=healthy, backup=record,
         player_and_order_rows_preserved=True, payment_functions_unchanged=True, real_orders_created=0, gateway_requests=0))


if MODE == 'prepare':
    report = prepare()
elif MODE == 'validate':
    report = validate()
elif MODE == 'activate':
    report = activate()
else:
    raise RuntimeError('invalid_operator_mode')
print(json.dumps(report, default=str))
