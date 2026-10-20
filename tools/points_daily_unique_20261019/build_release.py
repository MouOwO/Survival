"""Daily-only overlay on the downloaded online immutable bundle; no activation."""
from pathlib import Path
import argparse
import ast
import base64
import contextlib
import copy
import gzip
import hashlib
import importlib.util
import io
import json
import sys
import tarfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/points_daily_unique_20261019/release_v3'
PREVIOUS_TAR = '5c8d72af4ed3d0af2a426a038e6f385477d9154ae56cb8f6936c20a9bb0870f6'
PREVIOUS = ROOT / 'output/points_daily_unique_20261019/release_v2/previous_seal' / PREVIOUS_TAR
BASE = 'ccc088836ff79f635a002095958f6bcd43f45361e71037c26bfe5054b42f1348'
RELEASE = '20261019-points-daily-unique-v3'
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle, read_csv
from archive_backend import daily_unique


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def write(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_bytes() == raw, 'immutable_candidate_changed:' + str(path.relative_to(OUT))
    else:
        path.write_bytes(raw)


def baseline_from_previous_seal():
    record = json.loads((PREVIOUS / 'archive_manifest.json').read_bytes())
    assert record['tar_sha256'] == PREVIOUS_TAR and record['bundle'] == '0328f6ba83a13d309b8b6df84524814cf10ed5287c019282e35e286161d27bac'
    for name, expected in record['files'].items():
        if '__pycache__' in Path(name).parts or name.endswith('.pyc'):
            continue
        if name.startswith('baseline/') or name == 'remote/preflight.json':
            raw = (PREVIOUS / name).read_bytes()
            assert sha(raw) == expected, 'previous_baseline_changed:' + name
            write(OUT / name, raw)


def frozen_candidate_file(name):
    """Reuse the reviewed v2 Lua/config payload without consulting the worktree."""
    record = json.loads((PREVIOUS / 'archive_manifest.json').read_bytes())
    relative = 'candidate/' + name
    raw = (PREVIOUS / relative).read_bytes()
    assert sha(raw) == record['files'][relative], 'previous_candidate_changed:' + name
    return raw


def identical_lottery_helper(before, parent, candidate, digest):
    """One directed trusted pair, after proving every lottery rule is unchanged."""
    configs = sorted(name for name in parent['configs'] if name.startswith('lottery_'))
    sources = sorted(name for name in parent['sources'] if 'lottery' in name or name == 'config/content_id_aliases.lua')
    assert configs and sources
    for name in configs:
        assert candidate['configs'][name] == parent['configs'][name], 'lottery_compatibility_rules_changed:' + name
    for name in sources:
        assert candidate['sources'][name] == parent['sources'][name], 'lottery_compatibility_reducer_changed:' + name
    anchor = "MIGRATION = '20261018_unique_lottery_points_v1'\n"
    assert before.count(anchor) == 1
    result = before.replace(anchor, anchor + "\n# One reviewed daily-only update with identical lottery rules and reducer.\n" +
        'IDENTICAL_LOTTERY_UPDATE = ' + repr((digest, BASE)) + '\n', 1)
    anchor = "    if recorded_hash != current_hash and kind in ('lottery_draw', 'lottery_exchange'):\n"
    assert result.count(anchor) == 1
    result = result.replace(anchor, "    if kind in ('lottery_draw', 'lottery_exchange') and (current_hash, recorded_hash) == IDENTICAL_LOTTERY_UPDATE:\n" +
        '        return None\n' + anchor, 1)
    compile(result, 'candidate/unique_points.py', 'exec')
    proof = dict(current_hash=digest, recorded_hash=BASE,
        configs={name: sha(canonical(parent['configs'][name])) for name in configs},
        sources={name: sha(parent['sources'][name].encode()) for name in sources},
        all_other_configs_equal=True, all_other_sources_equal=True)
    return result, proof


def remote_review(data, helper_source, configuration):
    """Read-only exact PostgreSQL JSONB hash and anonymous locked repair digest."""
    audit = json.loads((OUT / 'remote/preflight.json').read_bytes())['records'][0]
    source = 'EXPECTED=' + repr({key: audit[key] for key in ('archive_release', 'payment_release', 'archive_bundle', 'archive_manifest_sha256', 'payment_manifest_sha256', 'catalog_hash')}) + '\n'
    source += 'DATA=' + repr(base64.b64encode(canonical(data)).decode()) + '\n'
    source += 'HELPER=' + repr(helper_source) + '\n'
    source += 'CONFIGURATION=' + repr(base64.b64encode(configuration).decode()) + '\n'
    source += r'''
from pathlib import Path
from types import SimpleNamespace,ModuleType
import base64,hashlib,json,sys
sys.dont_write_bytecode=True
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
sha=lambda raw:hashlib.sha256(raw).hexdigest()
assert archive.name==EXPECTED['archive_release'] and payment.name==EXPECTED['payment_release'],'release_baseline_changed'
assert sha((archive/'release_manifest.json').read_bytes())==EXPECTED['archive_manifest_sha256'],'archive_manifest_changed'
assert sha((payment/'manifest.json').read_bytes())==EXPECTED['payment_manifest_sha256'],'payment_manifest_changed'
assert json.loads((archive/'addon/server/bundles/current.json').read_bytes())['hash']==EXPECTED['archive_bundle'],'bundle_baseline_changed'
raw=base64.b64decode(DATA);data=json.loads(raw);digest=sha(raw)
bundle=SimpleNamespace(hash=digest,configs=data['configs'],directory=archive/'addon/server/bundles'/EXPECTED['archive_bundle'],
 tables={name:{row[cfg['key']]:row for row in cfg['rows']} for name,cfg in data['configs'].items()})
sys.path.insert(0,str(archive/'backend'))
module=ModuleType('archive_backend.daily_unique_candidate');module.__package__='archive_backend'
exec(HELPER,module.__dict__)
sys.path.insert(0,str(payment))
from deploy import connection
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','database_scope_changed'
 assert conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]==EXPECTED['catalog_hash'],'payment_catalog_changed'
 assert not conn.execute("SELECT 1 FROM pg_constraint WHERE conrelid='public.player_archive_state'::regclass AND conname='archive_unique_points_20261019_check'").fetchone(),'daily_constraint_already_exists'
 assert conn.execute("SELECT to_regprocedure('public.archive_unique_points_20261019_valid(jsonb,jsonb)')").fetchone()[0] is None,'daily_function_already_exists'
 plans,repair_digest=module.plans(conn,bundle)
 config_rows={r[0]:sha(json.dumps(r[1],ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()) for r in conn.execute('SELECT config_hash,config FROM public.archive_config_sets')}
 jsonb_hash=conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(base64.b64decode(CONFIGURATION).decode(),)).fetchone()[0]
 fields={}
 for plan in plans:
  for field,value in plan['deltas'].items():fields[field]=fields.get(field,0)+value
 conn.rollback()
print(json.dumps(dict(status='READONLY_DAILY_REPAIR_PLAN_PASS',migration_plan_digest=repair_digest,
 changed_accounts=len(plans),changed_items=sum(p['changed_items'] for p in plans),
 extra_copies=sum(d['extra_copies'] for p in plans for d in p['details']),
 converted_points=sum(p['converted_points'] for p in plans),stat_deltas=fields,
 configuration_jsonb_sha256=jsonb_hash,config_rows=config_rows,database_writes=0,individual_account_ids_exported=False)))
'''
    spec = importlib.util.spec_from_file_location('daily_review_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    transport.OUT = OUT / 'remote'
    with contextlib.redirect_stdout(io.StringIO()):
        result = transport.execute(source, 'review', timeout=90)
    return result['records'][0]


def main(seal=False):
    baseline_from_previous_seal()
    audit = json.loads((OUT / 'remote/preflight.json').read_bytes())['records'][0]
    assert audit['archive_release'] == '20261018-points-unique-v1' and audit['archive_bundle'] == BASE
    assert audit['payment_release'] == '20261018-checkout-gcoin-v1'
    local_pointers = {name: (ROOT / name).read_bytes() for name in ('server/bundles/current.json', 'scripts/vscripts/config/generated/archive_http_bundle.lua')}
    raw = (OUT / 'baseline/addon/server/bundles' / BASE / 'bundle.json').read_bytes()
    assert sha(raw) == BASE
    parent = json.loads(raw)
    data = copy.deepcopy(parent)
    relative = 'data/csv/存档系统/archive_daily_items.csv'
    frozen_csv = frozen_candidate_file('addon/' + relative)
    fresh = read_csv(PREVIOUS / 'candidate/addon' / relative)
    old_rows = {row['item_id']: row for row in parent['configs']['archive_daily_items']['rows']}
    new_rows = {row['item_id']: row for row in fresh['rows']}
    assert old_rows.keys() == new_rows.keys() and len(new_rows) == 12
    changes = {}
    for identity, row in new_rows.items():
        assert row['max_owned'] == 1
        fields = {key for key in row.keys() | old_rows[identity].keys() if row.get(key) != old_rows[identity].get(key)}
        assert fields <= {'max_owned'}, 'daily_configuration_scope_changed:' + identity
        if fields:
            assert old_rows[identity]['max_owned'] == 999999
            changes[identity] = ['max_owned']
    assert len(changes) == 9
    data['configs']['archive_daily_items'] = fresh
    data['csv_hashes'][relative] = sha(frozen_csv.replace(b'\r\n', b'\n'))
    changed_source = 'systems/archive_daily_rewards.lua'
    prior_plan = json.loads((PREVIOUS / 'plan.json').read_bytes())
    data['sources'][changed_source] = frozen_candidate_file(
        'addon/server/bundles/' + prior_plan['bundle'] + '/' + changed_source).decode('utf-8-sig')
    assert data['sources'][changed_source] != parent['sources'][changed_source]
    before_service = (OUT / 'baseline/backend/archive_backend/service.py').read_text('utf-8-sig')
    tree = ast.parse(before_service)
    fields = next(node.value for node in tree.body if isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == 'FIELDS' for target in node.targets))
    commands = sorted(set(ast.literal_eval(fields)) | {'lottery_snapshot'})
    daily_commands = {'daily_init', 'daily_claim'}
    compatibility = data.setdefault('compatible_config_hashes', {})
    assert BASE not in compatibility
    compatibility[BASE] = {'commands': commands, 'upgrade_commands': sorted(daily_commands)}
    # Only daily intents advance to the new reducer. All other compatibility
    # entries and recorded operation rules retain their baseline behavior.
    compatibility_changed = []
    for digest, rule in compatibility.items():
        if daily_commands <= set(rule['commands']):
            upgraded = sorted(set(rule['upgrade_commands']) | daily_commands)
            if upgraded != rule['upgrade_commands']:
                rule['upgrade_commands'] = upgraded
                compatibility_changed.append(digest)
    assert all(data['configs'][name] == value for name, value in parent['configs'].items() if name != 'archive_daily_items')
    assert all(data['sources'][name] == value for name, value in parent['sources'].items() if name != changed_source)
    for digest, prior in parent.get('compatible_config_hashes', {}).items():
        assert compatibility[digest]['commands'] == prior['commands']
        assert set(compatibility[digest]['upgrade_commands']) - set(prior['upgrade_commands']) <= daily_commands
    packed = canonical(data)
    digest = sha(packed)
    candidate = OUT / 'candidate'
    directory = candidate / 'addon/server/bundles' / digest
    write(directory / 'bundle.json', packed)
    for name, source in data['sources'].items():
        write(directory / name, source.encode())
    bundle = Bundle(directory)
    helper = (ROOT / 'server/archive_backend/daily_unique.py').read_text('utf-8-sig')
    compile(helper, 'candidate/daily_unique.py', 'exec')
    write(candidate / 'backend/archive_backend/daily_unique.py', helper.encode())
    prior_unique = (OUT / 'baseline/backend/archive_backend/unique_points.py').read_text('utf-8-sig')
    unique_helper, lottery_proof = identical_lottery_helper(prior_unique, parent, data, digest)
    write(candidate / 'backend/archive_backend/unique_points.py', unique_helper.encode())
    local_unique = ROOT / 'server/archive_backend/unique_points.py'
    assert local_unique.read_text('utf-8-sig') in (prior_unique, unique_helper), 'local_unique_helper_unrelated_changes'
    if local_unique.read_text('utf-8-sig') != unique_helper:
        local_unique.write_text(unique_helper, encoding='utf-8', newline='\n')
    write(candidate / 'addon' / relative, frozen_csv)
    write(candidate / 'addon/server/bundles/current.json', canonical({'hash': digest, 'protocol': 1}))
    write(candidate / 'addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
        ('-- AUTO-GENERATED by tools/points_daily_unique_20261019/build_release.py\nreturn { protocol = 1, hash = "' + digest + '" }\n').encode())
    configuration = canonical({'configs': data['configs'], 'compatible_config_hashes': compatibility})
    write(OUT / 'configuration.json', configuration)
    constraint = daily_unique.render_constraint_sql(bundle).encode()
    write(OUT / 'daily_constraint.sql', constraint)
    checks = (ROOT / 'server/tests/test_daily_unique_database.py').read_bytes()
    write(OUT / 'daily_database_checks.py', checks)
    lottery_checks = Path(__file__).with_name('lottery_database_checks.py').read_bytes()
    write(OUT / 'lottery_database_checks.py', lottery_checks)
    prefix = 'addon/server/bundles/' + digest + '/'
    approved = {'backend/archive_backend/daily_unique.py', 'backend/archive_backend/unique_points.py', 'addon/' + relative,
        'addon/server/bundles/current.json', 'addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
        prefix + 'bundle.json', *(prefix + name for name in parent['sources'])}
    assert {path.relative_to(candidate).as_posix() for path in candidate.rglob('*') if path.is_file()} == approved
    assert not any(path.is_symlink() for path in candidate.rglob('*'))
    files = {name: sha((candidate / name).read_bytes()) for name in sorted(approved)}
    plan = dict(version=1, kind='daily_unique_archive_repair', status='CANDIDATE_NOT_SEALED',
        archive_baseline=audit['archive_release'], archive_release=RELEASE, payment_release=audit['payment_release'],
        parent_bundle=BASE, bundle=digest, archive_manifest_sha256=audit['archive_manifest_sha256'],
        payment_manifest_sha256=audit['payment_manifest_sha256'], payment_catalog_hash=audit['catalog_hash'],
        archive_files=files, row_changes={'archive_daily_items': changes}, sources_changed=[changed_source],
        compatibility_daily_upgrades=compatibility_changed, old_sync_sha256=audit['functions']['public.archive_sync_config(text,jsonb)']['sha256'],
        identical_lottery_compatibility=lottery_proof,
        configuration_sha256=sha(configuration), daily_constraint_sha256=sha(constraint), daily_checks_sha256=sha(checks), old_config_rows=audit['config_rows'],
        lottery_checks_sha256=sha(lottery_checks),
        local_pointer_sha256={name: sha(value) for name, value in local_pointers.items()},
        migration_approval_scope='affected_account_hash_items_fixed_deltas_and_compensation_v2',
        player_updates_required=True, no_payment_changes=True, production_deployed=False)
    plan['previous_seal_tar_sha256'] = PREVIOUS_TAR
    assert digest == prior_plan['bundle'], 'resume_bundle_scope_changed'
    assert files.keys() == prior_plan['archive_files'].keys(), 'resume_payload_scope_changed'
    assert all(value == prior_plan['archive_files'][name] for name, value in files.items()
               if name != 'backend/archive_backend/daily_unique.py'), 'resume_unrelated_file_changed'
    previous_constraint = (PREVIOUS / 'daily_constraint.sql').read_text('utf-8-sig')
    old_acl = 'REVOKE ALL ON FUNCTION public.archive_unique_points_20261019_valid(jsonb,jsonb) FROM PUBLIC,anon,authenticated;\n' + \
        'GRANT EXECUTE ON FUNCTION public.archive_unique_points_20261019_valid(jsonb,jsonb) TO service_role,goufayu_app;\n'
    new_acl = 'REVOKE ALL ON FUNCTION public.archive_unique_points_20261019_valid(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role,goufayu_app;\n'
    assert previous_constraint.count(old_acl) == 1
    assert constraint.decode() == previous_constraint.replace(old_acl, new_acl, 1), 'resume_database_boundary_changed'
    previous_helper = frozen_candidate_file('backend/archive_backend/daily_unique.py').decode('utf-8-sig')
    assert previous_helper.count(old_acl) == 1
    assert helper == previous_helper.replace(old_acl, new_acl, 1), 'resume_daily_helper_scope_changed'
    plan['constraint_change_scope'] = 'remove_application_direct_execute_keep_owner_security_definer_check'
    if seal:
        reviewed = remote_review(data, helper, configuration)
        rows = reviewed['config_rows']
        assert all(rows.get(name) == value for name, value in audit['config_rows'].items()), 'existing_configuration_changed'
        assert set(rows) - set(audit['config_rows']) <= {digest}, 'unreviewed_additive_configuration'
        if digest in rows:
            assert rows[digest] == sha(configuration), 'existing_candidate_configuration_changed'
        plan['old_config_rows'] = rows
        before = audit['functions']['public.archive_sync_config(text,jsonb)']['definition']
        marker = ' -- Reviewed unique points: exact immutable configuration; no player migration.\n'
        assert before.count(marker) == 1
        addition = " -- Reviewed daily unique points: exact configuration with backed-up inventory repair.\n" + \
            " if p_hash='" + digest + "' then\n" + \
            "  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'" + reviewed['configuration_jsonb_sha256'] + "' then\n" + \
            "   raise exception 'archive_daily_unique_configuration_mismatch';\n  end if;\n" + \
            "  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;\n" + \
            "  select config into v from archive_config_sets where config_hash=p_hash;\n" + \
            "  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;\n" + \
            "  return jsonb_build_object('ok',true);\n end if;\n"
        after = before.replace(marker, addition + marker, 1)
        write(OUT / 'archive_sync_before.sql', before.encode())
        write(OUT / 'archive_sync_candidate.sql', after.encode())
        plan.update(status='SEALED_NOT_DEPLOYED', configuration_jsonb_sha256=reviewed['configuration_jsonb_sha256'],
            migration_plan_digest=reviewed['migration_plan_digest'], migration_summary=reviewed,
            new_sync_sha256=sha(after.encode()), operator_sha256=sha(Path(__file__).with_name('remote_operator.py').read_bytes()))
        payload = {'plan.json': canonical(plan), 'configuration.json': configuration,
            'daily_constraint.sql': constraint, 'daily_database_checks.py': checks,
            'lottery_database_checks.py': lottery_checks,
            'archive_sync_before.sql': before.encode(), 'archive_sync_candidate.sql': after.encode()}
        payload.update({'archive/' + name: (candidate / name).read_bytes() for name in files})
        tar_bytes = io.BytesIO()
        with gzip.GzipFile(fileobj=tar_bytes, mode='wb', mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode='w') as stream:
                for name, value in sorted(payload.items()):
                    entry = tarfile.TarInfo(name)
                    entry.size = len(value)
                    entry.mode = 0o600
                    stream.addfile(entry, io.BytesIO(value))
        write(OUT / 'release.tar.gz', tar_bytes.getvalue())
        plan['tar_sha256'] = sha(tar_bytes.getvalue())
    (OUT / 'plan.json').write_bytes(canonical(plan))
    assert all((ROOT / name).read_bytes() == value for name, value in local_pointers.items())
    print(json.dumps({key: plan[key] for key in ('status', 'bundle', 'archive_release', 'row_changes', 'sources_changed')}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seal', action='store_true', help='Freeze the exact reviewed repair digest and payload; never deploy.')
    main(parser.parse_args().seal)
