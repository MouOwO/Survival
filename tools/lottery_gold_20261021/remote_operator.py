"""Pinned test-host publication of cultivation gold-ticket costs and one title.

This file is executed only by the local driver with a sealed plan. No account,
inventory, payment amount, delivery rule, historical order, or receipt is edited.
Rollback returns the archive pointer to its preserved parent; additive config
registration remains available for already prepared operations.
"""
from pathlib import Path, PurePosixPath
import copy
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import sys
import time
import urllib.request

STAGE = Path(STAGE)
sha = lambda raw: hashlib.sha256(raw).hexdigest()
canonical = lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
P = json.loads((STAGE / 'plan.json').read_bytes())
OLD = Path('/opt/goufayu/releases') / P['archive_release']
NEW = OLD.parent / P['new_release']
PAY = Path('/opt/goufayu/payments') / P['payment_release']
CURRENT = OLD.parent / 'current'
sys.path.insert(0, str(PAY))
from deploy import connection, backup
from psycopg.types.json import Jsonb


def need(condition, code):
    if not condition:
        raise RuntimeError(code)


def save(name, value):
    target = STAGE / (name + '.json')
    need(not target.is_symlink(), 'report_symlink')
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    target.chmod(0o600)
    return value


def safe(root, name):
    path = PurePosixPath(name)
    need(not path.is_absolute() and '..' not in path.parts and '\\' not in name
         and ':' not in name and path.as_posix() == name, 'unsafe_release_path')
    result = root / name
    need(all(not (root.joinpath(*path.parts[:i])).is_symlink() for i in range(1, len(path.parts) + 1)), 'release_symlink')
    return result


def manifest(root):
    data = json.loads((root / 'release_manifest.json').read_bytes())
    for name, digest in data['files'].items():
        need(sha(safe(root, name).read_bytes()) == digest, 'release_manifest_drift')
    return data


def payment_pin():
    need(Path('/opt/goufayu/payments/current').resolve() == PAY, 'payment_pointer_drift')
    need(sha((PAY / 'manifest.json').read_bytes()) == P['payment_manifest_sha256'], 'payment_manifest_drift')
    pid = subprocess.check_output(['systemctl', 'show', '--property=MainPID', '--value', 'goufayu-payment.service'], text=True).strip()
    need(pid == P['payment_pid'], 'payment_process_changed')


def baseline(conn, after=False):
    need(conn.info.dbname == 'goufayu_test', 'database_scope_changed')
    need(CURRENT.resolve() == (NEW if after else OLD), 'archive_pointer_drift')
    payment_pin()
    need(sha((OLD / 'release_manifest.json').read_bytes()) == P['archive_manifest_sha256'], 'parent_manifest_changed')
    old = conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
    if not after:
        need(sha(old.encode()) == P['archive_sync_sha256'], 'sync_policy_changed')
    return old


def scope():
    parent = json.loads((OLD / 'addon/server/bundles' / P['archive_bundle'] / 'bundle.json').read_bytes())
    raw = (STAGE / 'bundle.json').read_bytes()
    need(sha(raw) == P['bundle'], 'candidate_bundle_changed')
    candidate = json.loads(raw)
    expected = copy.deepcopy(parent)
    for table, row_id, allowed in (
        ('lottery_pool_definitions', 'cultivation', {'ticket_content_id', 'description', 'pool_group'}),
        ('lottery_currency_definitions', 'special_lottery_ticket', {'notes'}),
        ('commerce_products', 'video_p001', {'display_name'}),
        ('commerce_import_status', 'P001', {'display_name', 'implementation_notes'}),
        ('commerce_catalog', 'video_p001', {'title'}),
    ):
        old = expected['configs'][table]
        new = candidate['configs'][table]
        key = old['key']
        old_rows = {row[key]: row for row in old['rows']}
        new_rows = {row[key]: row for row in new['rows']}
        need(old_rows.keys() == new_rows.keys(), 'configuration_row_set_changed')
        for identity, old_row in old_rows.items():
            fields = {field for field in old_row.keys() | new_rows[identity].keys()
                      if old_row.get(field) != new_rows[identity].get(field)}
            need(not fields or (identity == row_id and fields <= allowed), 'unrelated_configuration_field_changed')
        expected['configs'][table] = new
    for name in P['csv_files']:
        need(name in expected['csv_hashes'], 'unknown_configuration_csv')
        expected['csv_hashes'][name] = candidate['csv_hashes'][name]
    aliases = expected['compatible_config_hashes']
    commands = sorted({kind for rule in aliases.values() for kind in rule['commands']})
    need(P['archive_bundle'] not in aliases, 'parent_alias_already_exists')
    aliases[P['archive_bundle']] = dict(commands=commands, upgrade_commands=[])
    need(candidate == expected, 'unrelated_bundle_change')
    cultivation = next(row for row in candidate['configs']['lottery_pool_definitions']['rows'] if row['pool_id'] == 'cultivation')
    need(cultivation['ticket_content_id'] == 'special_lottery_ticket' and cultivation['unlock_pool_id'] == 'map'
         and cultivation['unlock_draws'] == 100 and cultivation['single_cost'] == 1 and cultivation['ten_cost'] == 10,
         'cultivation_contract_changed')
    return candidate


def worker_checks(data):
    directory = NEW / 'addon/server/bundles' / P['bundle']
    defaults = {row['field_id']: row['default_value'] for row in data['configs']['player_gameplay_stats']['rows']}
    profile = dict(save=dict(archive=dict(lottery_state=dict(pools=dict(map=dict(draws=100)))),
                             content_inventory=dict(lottery_ticket=100, special_lottery_ticket=17), gameplay_stats=defaults))
    def call(count, progress=100, special=17, pool='cultivation'):
        source = copy.deepcopy(profile)
        source['save']['content_inventory']['special_lottery_ticket'] = special
        source['save']['archive']['lottery_state']['pools']['map']['draws'] = progress
        command = dict(id='gold_ticket_review_20261021', kind='lottery_draw', pool_id=pool, count=count,
                       request_id='gold_ticket_review_20261021')
        payload = dict(configs=data['configs'], profile=source, command=command, seed=1, has_pass=False, server_time=0)
        result = subprocess.run([shutil.which('lua5.1') or shutil.which('lua'), 'worker.lua'], cwd=directory,
                                input=canonical(payload), capture_output=True, timeout=10, check=True)
        return json.loads(result.stdout)
    for count in (1, 10):
        result = call(count)
        need(result['ok'] and result['content_inventory']['lottery_ticket'] == 100
             and result['content_inventory']['special_lottery_ticket'] == 17 - count, 'cultivation_gold_debit_invalid')
        result = call(count, progress=99)
        need(not result['ok'] and result['error'] == 'lottery_pool_locked', 'cultivation_gate_removed')
        result = call(count, special=0)
        need(not result['ok'] and result['error'] == 'lottery_ticket_insufficient', 'normal_substituted_gold')
    result = call(10, special=9)
    need(not result['ok'] and result['error'] == 'lottery_ticket_insufficient', 'gold_shortage_accepted')
    result = call(10, pool='map')
    need(result['ok'] and result['content_inventory']['lottery_ticket'] == 90
         and result['content_inventory']['special_lottery_ticket'] == 17, 'map_currency_changed')
    return dict(cases=8, synthetic_memory_only=True, real_player_writes=0)


def prepared_scope():
    data = scope()
    old = manifest(OLD)
    new = manifest(NEW)
    need(new['files'] == {**old['files'], **P['overlay']}
         and new['archive_bundle'] == P['bundle'] and new['release'] == P['new_release'], 'candidate_manifest_changed')
    return data


def prepare():
    need(not NEW.exists(), 'candidate_release_exists')
    payment_pin()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        baseline(conn)
        conn.rollback()
    data = scope()
    old = manifest(OLD)
    NEW.mkdir(mode=0o755)
    for name in old['files']:
        source = safe(OLD, name)
        target = safe(NEW, name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(source.stat().st_mode & 0o777)
    (NEW / '.venv').symlink_to(OLD / '.venv', target_is_directory=True)
    relative = 'addon/server/bundles/' + P['bundle'] + '/'
    overlay = {relative + 'bundle.json': (STAGE / 'bundle.json').read_bytes(),
               **{relative + name: source.encode() for name, source in data['sources'].items()},
               'addon/server/bundles/current.json': canonical(dict(hash=P['bundle'], protocol=1))}
    need({name: sha(raw) for name, raw in overlay.items()} == P['overlay'], 'prepared_overlay_changed')
    for name, raw in overlay.items():
        target = safe(NEW, name)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        target.chmod(0o644)
    result = copy.deepcopy(old)
    result['files'].update(P['overlay'])
    result.update(release=P['new_release'], archive_bundle=P['bundle'])
    (NEW / 'release_manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    prepared_scope()
    checks = worker_checks(data)
    return save('prepared', dict(ok=True, phase='PREPARED', release=NEW.name, bundle=P['bundle'], worker_checks=checks))


def table_state(conn):
    from psycopg import sql
    tables = conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('payments','public') ORDER BY 1,2").fetchall()
    return {schema + '.' + table: conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t")
            .format(sql.Identifier(schema), sql.Identifier(table))).fetchone() for schema, table in tables}


def apply(conn, data):
    need(conn.info.dbname == 'goufayu_test', 'database_scope_changed')
    conn.execute('SET LOCAL ROLE goufayu_owner')
    conn.execute('LOCK TABLE public.archive_config_sets,payments.products,payments.catalog_state IN SHARE ROW EXCLUSIVE MODE')
    product = conn.execute("SELECT to_jsonb(p) FROM payments.products p WHERE sku='video_p001'").fetchone()[0]
    need(product == P['payment_product'], 'ticket_product_changed')
    need(product['amount'] == 600 and product['grants']['items'] == {'special_lottery_ticket': 1}, 'ticket_economics_changed')
    catalog = conn.execute('SELECT to_jsonb(c) FROM payments.catalog_state c WHERE singleton').fetchone()[0]
    need(catalog['catalog_hash'] == P['catalog_hash'], 'catalog_revision_changed')
    others = conn.execute("SELECT md5(coalesce(string_agg(to_jsonb(p)::text,chr(10) ORDER BY sku),'')) FROM payments.products p WHERE sku<>'video_p001'").fetchone()[0]
    configs = dict(conn.execute('SELECT config_hash,config FROM public.archive_config_sets'))
    need(P['bundle'] not in configs, 'bundle_already_registered')
    config = dict(configs=data['configs'], compatible_config_hashes=data['compatible_config_hashes'])
    pg_sha = conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(config),)).fetchone()[0]
    old = conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
    need(sha(old.encode()) == P['archive_sync_sha256'], 'sync_policy_changed')
    marker = ' -- Reviewed monthly challenge tickets and requested fragment/cage quotas.'
    need(old.count(marker) == 1, 'sync_policy_anchor_changed')
    branch = """ -- Reviewed cultivation gold-ticket costs and display-only ticket rename.
 if p_hash='%s' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then raise exception 'archive_gold_ticket_configuration_mismatch'; end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
""" % (P['bundle'], pg_sha)
    updated = old.replace(marker, branch + marker, 1)
    need(updated.replace(branch, '', 1) == old, 'old_sync_policy_changed')
    conn.execute(updated)
    need(conn.execute('SELECT public.archive_sync_config(%s,%s)', (P['bundle'], Jsonb(config))).fetchone()[0]['ok'], 'configuration_registration_failed')
    need(dict(conn.execute('SELECT config_hash,config FROM public.archive_config_sets')) == {**configs, P['bundle']: config}, 'existing_configurations_changed')
    result = conn.execute("UPDATE payments.products SET title='金色抽奖券' WHERE sku='video_p001' AND title='红色抽奖券'")
    need(result.rowcount == 1, 'ticket_title_update_failed')
    expected = {**product, 'title': '金色抽奖券'}
    need(conn.execute("SELECT to_jsonb(p) FROM payments.products p WHERE sku='video_p001'").fetchone()[0] == expected, 'ticket_product_scope_changed')
    need(conn.execute("SELECT md5(coalesce(string_agg(to_jsonb(p)::text,chr(10) ORDER BY sku),'')) FROM payments.products p WHERE sku<>'video_p001'").fetchone()[0] == others, 'other_products_changed')
    conn.execute('UPDATE payments.catalog_state SET catalog_hash=%s WHERE singleton AND catalog_hash=%s', (P['new_catalog_hash'], P['catalog_hash']))
    need(conn.execute('SELECT to_jsonb(c) FROM payments.catalog_state c WHERE singleton').fetchone()[0] == {**catalog, 'catalog_hash': P['new_catalog_hash']}, 'catalog_metadata_changed')
    return dict(configuration_jsonb_sha256=pg_sha, sync_sha256=sha(updated.encode()), payment_title_only=True)


def validate():
    need((STAGE / 'prepared.json').is_file(), 'prepare_required')
    data = prepared_scope()
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET LOCAL lock_timeout='5s'")
            baseline(conn)
            before = table_state(conn)
            result = apply(conn, data)
            after = table_state(conn)
            allowed = {'public.archive_config_sets', 'payments.products', 'payments.catalog_state'}
            need(before.keys() == after.keys() and all(before[key] == after[key] for key in before if key not in allowed), 'unexpected_database_row_change')
        finally:
            conn.rollback()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    return save('validated', dict(ok=True, phase='VALIDATED', rolled_back=True, player_writes=0, **result))


def switch(target):
    need(CURRENT.resolve() in (OLD, NEW), 'pointer_owned_by_other_release')
    temporary = CURRENT.with_name('current.gold-ticket.' + secrets.token_hex(6))
    temporary.symlink_to(target, target_is_directory=True)
    os.replace(temporary, CURRENT)


def systemctl(action):
    result = subprocess.run(['systemctl', action, 'goufayu-api.service'], capture_output=True, timeout=45)
    need(result.returncode == 0, 'archive_service_action_failed')


def health():
    for attempt in range(30):
        try:
            for port in (8765, 8766):
                with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=3) as response:
                    need(json.load(response).get('ok') is True, 'health_not_ready')
            return True
        except Exception:
            if attempt == 29:
                raise
            time.sleep(.5)


def activate():
    import contextlib, io
    need(json.loads((STAGE / 'validated.json').read_bytes())['rolled_back'] is True, 'validation_required')
    data = prepared_scope()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        backup()
    record = json.loads(captured.getvalue().splitlines()[-1])
    save('private_backup', record)
    committed = False
    try:
        systemctl('stop')
        with connection() as conn:
            conn.execute("SET LOCAL lock_timeout='5s'")
            baseline(conn)
            before = table_state(conn)
            result = apply(conn, data)
            after = table_state(conn)
            allowed = {'public.archive_config_sets', 'payments.products', 'payments.catalog_state'}
            need(before.keys() == after.keys() and all(before[key] == after[key] for key in before if key not in allowed), 'activation_changed_player_or_order_rows')
        committed = True
        switch(NEW)
        systemctl('start')
        health()
        payment_pin()
        need(CURRENT.resolve() == NEW, 'activated_pointer_changed')
    except Exception:
        # Never restore player data or undo a COMMIT whose acknowledgement was
        # lost. The additive config/title are safe under the preserved parent.
        if CURRENT.resolve() in (OLD, NEW):
            switch(OLD)
            systemctl('start')
            health()
        save('activation_recovery', dict(commit_acknowledged=committed, parent_pointer_restored=CURRENT.resolve() == OLD,
                                         player_rows_restored=False, payment_service_restarted=False))
        raise
    return save('activated', dict(ok=True, phase='ACTIVATED', release=NEW.name, bundle=P['bundle'],
                                 player_writes=0, historical_orders_changed=0, payment_service_restarted=False,
                                 backup=record, **result))


def verify():
    prepared_scope()
    payment_pin()
    need(CURRENT.resolve() == NEW, 'new_release_not_active')
    config = json.loads(Path('/etc/goufayu-payment/config.json').read_bytes())
    request = urllib.request.Request('http://127.0.0.1:8765/v1/lottery/catalog', data=b'{"md5":""}', method='POST',
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + config['game_token']})
    with urllib.request.urlopen(request, timeout=20) as response:
        catalog = json.load(response)
    need(catalog.get('ok') is True and catalog['config_hash'] == P['bundle'], 'live_catalog_hash_invalid')
    public = json.loads(catalog['catalog_json'])
    selected = next(row['selected_pool'] for row in public['snapshots'] if row['selected_pool_id'] == 'cultivation')
    need(selected['ticket_content_id'] == 'special_lottery_ticket' and selected['ticket_name'] == '金色抽奖券'
         and selected['unlock_required'] == 100, 'live_cultivation_ticket_invalid')
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        row = conn.execute("SELECT to_jsonb(p) FROM payments.products p WHERE sku='video_p001'").fetchone()[0]
        need(row == {**P['payment_product'], 'title': '金色抽奖券'}, 'live_payment_title_invalid')
        need(conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0] == P['new_catalog_hash'], 'live_payment_revision_invalid')
        expected = dict(configs=scope()['configs'], compatible_config_hashes=scope()['compatible_config_hashes'])
        need(conn.execute('SELECT config FROM public.archive_config_sets WHERE config_hash=%s', (P['bundle'],)).fetchone()[0] == expected, 'live_archive_config_invalid')
        conn.rollback()
    health()
    return save('verified', dict(ok=True, phase='LIVE_VERIFIED', release=NEW.name, bundle=P['bundle'],
                                catalog_md5=catalog['catalog_md5'], ticket_name=selected['ticket_name'],
                                ticket_content_id=selected['ticket_content_id'], unlock_required=100,
                                payment_title='金色抽奖券', payment_pid=P['payment_pid'], player_writes=0))


def rollback():
    need(CURRENT.resolve() == NEW, 'rollback_pointer_not_ours')
    payment_pin()
    manifest(OLD)
    systemctl('stop')
    switch(OLD)
    systemctl('start')
    health()
    return save('rolled_back', dict(ok=True, phase='PARENT_RESTORED', archive_release=OLD.name,
                                   database_restored=False, additive_configuration_preserved=True))


report = {'prepare': prepare, 'validate': validate, 'activate': activate, 'verify': verify, 'rollback': rollback}[MODE]()
print(json.dumps(report, ensure_ascii=False))
