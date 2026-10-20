"""Freeze a minimal archive overlay on the verified 9d27 baseline; never move pointers."""
from pathlib import Path
import argparse
import ast
import base64
import contextlib
import copy
import difflib
import gzip
import hashlib
import importlib.util
import io
import json
import sys
import tarfile

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/points_goods_unique_20261018/release'
BASE = '9d27f6174b24e922d831837ec7a971c3726dc7a95b894c536b191ad5227406fb'
RELEASE = '20261018-points-unique-v1'
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle, read_csv
from archive_backend.commerce_catalog import build_catalog


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


def method(source, name):
    tree = ast.parse(source)
    node = next(node for cls in tree.body if isinstance(cls, ast.ClassDef) and cls.name == 'ArchiveService'
                for node in cls.body if isinstance(node, ast.FunctionDef) and node.name == name)
    return ''.join(source.splitlines(keepends=True)[node.lineno - 1:node.end_lineno])


def minimal_service(before, local):
    result = before
    old = '            version=prepared.get("config_hash",self.bundle.hash)\n'
    new = old + "            from .unique_points import legacy_lottery_error\n            legacy_error=legacy_lottery_error(self.bundle.hash,version,command.get('kind'))\n"
    assert result.count(old) == 1
    result = result.replace(old, new, 1)
    old = '            if version!=self.bundle.hash and not upgrades(self.bundle, version, command.get("kind")):\n'
    assert result.count(old) == 1
    result = result.replace(old, '            if version!=self.bundle.hash and not legacy_error and not upgrades(self.bundle, version, command.get("kind")):\n', 1)
    old = "            if command['kind'] == 'commerce_purchase' and product.get('currency') == 'shop_gold':\n"
    assert result.count(old) == 1
    result = result.replace(old, "            if legacy_error:\n                result={'ok':False,'error':legacy_error}\n" +
        "            elif command['kind'] == 'commerce_purchase' and product.get('currency') == 'shop_gold':\n", 1)
    old = "                result = {'ok': False, 'error': 'shop_gold_not_open'}\n            else:\n"
    assert result.count(old) == 1
    result = result.replace(old, "                result = {'ok': False, 'error': 'shop_gold_not_open'}\n" +
        "            elif (command['kind'] == 'commerce_purchase' and reducer is not self\n" +
        "                  and (unique_block := self.commerce_unique_block(profile, product))):\n" +
        "                result = {'ok': False, 'error': unique_block}\n            else:\n", 1)
    anchor = '    def drain_online(self,database_account):\n'
    assert result.count(anchor) == 1
    result = result.replace(anchor, method(local, 'commerce_unique_block') + '\n\n' + anchor, 1)
    old = '        projected=reducer.settle(profile,{"id":"lottery_snapshot","kind":"lottery_snapshot"},False)\n'
    assert result.count(old) == 1
    result = result.replace(old, old + '        from .unique_points import limit_snapshot_ownership\n        projected=limit_snapshot_ownership(projected,self.bundle)\n', 1)
    compile(result, 'candidate/service.py', 'exec')
    assert '.match_modes' not in result and 'shared_challenge_roll' not in result
    return result


def changed_fields(old, new):
    return {key for key in old.keys() | new.keys() if old.get(key) != new.get(key)}


def replace_rows(parent, name, fresh, allowed):
    old = parent['configs'][name]
    assert fresh['key'] == old['key']
    key = old['key']
    a = {row[key]: row for row in old['rows']}
    b = {row[key]: row for row in fresh['rows']}
    assert a.keys() == b.keys(), 'catalog_id_scope_changed:' + name
    changes = {identity: sorted(changed_fields(a[identity], b[identity])) for identity in a if a[identity] != b[identity]}
    assert set(changes) <= set(allowed), 'catalog_row_scope_changed:' + name
    for identity, fields in changes.items():
        assert set(fields) <= allowed[identity], 'catalog_field_scope_changed:' + name + ':' + identity
    return changes


def jsonb_hash(configuration):
    spec = importlib.util.spec_from_file_location('points_hash_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    transport.OUT = OUT / 'remote'
    source = "RAW=" + repr(base64.b64encode(configuration).decode()) + "\n" + r'''
from pathlib import Path
import base64,json,sys
assert Path('/opt/goufayu/releases/current').resolve().name=='20261017-monthly-58-v1','archive_baseline_changed'
assert Path('/opt/goufayu/payments/current').resolve().name=='20261018-checkout-gcoin-v1','payment_baseline_changed'
sys.path.insert(0,'/opt/goufayu/payments/current')
from deploy import connection
with connection() as conn:
 conn.execute('SET TRANSACTION READ ONLY')
 digest=conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(base64.b64decode(RAW).decode(),)).fetchone()[0]
 conn.rollback()
print(json.dumps(dict(status='READONLY_CONFIGURATION_HASH_PASS',jsonb_sha256=digest,database_writes=0)))
'''
    with contextlib.redirect_stdout(io.StringIO()):
        report = transport.execute(source, 'configuration_hash', timeout=90)
    return report['records'][0]['jsonb_sha256']


def main(seal=False):
    audit = json.loads((OUT / 'remote/preflight.json').read_bytes())['records'][0]
    assert audit['archive_bundle'] == BASE and audit['archive_release'] == '20261017-monthly-58-v1'
    assert audit['payment_release'] == '20261018-checkout-gcoin-v1'
    pointer_names = ['server/bundles/current.json', 'scripts/vscripts/config/generated/archive_http_bundle.lua']
    pointers = {name:(ROOT / name).read_bytes() for name in pointer_names}
    assert json.loads(pointers[pointer_names[0]])['hash'] == BASE
    assert BASE.encode() in pointers[pointer_names[1]]
    raw = (OUT / 'baseline/addon/server/bundles' / BASE / 'bundle.json').read_bytes()
    assert sha(raw) == BASE and (ROOT / 'server/bundles' / BASE / 'bundle.json').read_bytes() == raw
    parent = json.loads(raw)
    data = copy.deepcopy(parent)
    row_changes = {}
    source_csv = []
    definitions = {
        'commerce_products': ('商城兑换系统', {'video_p089':{'enabled'}, 'video_p103':{'purchase_limit','description'}}),
        'commerce_import_status': ('商城兑换系统', {'P089':{'notes'}, 'P103':{'notes'}}),
        'lottery_item_definitions': ('抽奖系统', {'lottery_ember_of_legacy':{'description','notes'}}),
    }
    for name, (folder, allowed) in definitions.items():
        relative = 'data/csv/' + folder + '/' + name + '.csv'
        fresh = read_csv(ROOT / relative)
        changes = replace_rows(parent, name, fresh, allowed)
        if changes:
            data['configs'][name] = fresh
            data['csv_hashes'][relative] = sha((ROOT / relative).read_bytes().replace(b'\r\n', b'\n'))
            row_changes[name] = changes
            source_csv.append(relative)
    compiled = {row['sku']:row for row in build_catalog(ROOT)['products']}
    old_products = {row['sku']:row for row in parent['configs']['commerce_catalog']['rows']}
    assert compiled.keys() == old_products.keys()
    changes = {}
    for row in data['configs']['commerce_catalog']['rows']:
        sku = row['sku']
        if sku not in {'video_p089','video_p103'}:
            continue
        changes[sku] = sorted(changed_fields(row, compiled[sku]))
        assert set(changes[sku]) <= ({'enabled'} if sku == 'video_p089' else {'purchase_limit','description'})
        for field in ('price','currency','ownership_quantity','effects','grants'):
            assert row[field] == compiled[sku][field], 'purchase_terms_changed:' + sku + ':' + field
        row.clear();row.update(copy.deepcopy(compiled[sku]))
    assert compiled['video_p089']['enabled'] is False and compiled['video_p103']['purchase_limit'] == 1
    assert old_products['video_p089']['price'] == 2500 and old_products['video_p103']['price'] == 29
    row_changes['commerce_catalog'] = changes
    sources_changed = ['systems/lottery_http_settlement.lua', 'systems/commerce_settlement.lua']
    for name in sources_changed:
        text = (ROOT / 'scripts/vscripts' / name).read_text('utf-8-sig')
        if name.endswith('commerce_settlement.lua'):
            # Currency renaming is a separate change; retain this baseline label.
            assert text.count("u_coin='G币'") == 1 and parent['sources'][name].count("u_coin='U币'") == 1
            text = text.replace("u_coin='G币'", "u_coin='U币'", 1)
        data['sources'][name] = text
    before_service = (OUT / 'baseline/backend/archive_backend/service.py').read_text('utf-8-sig')
    service = minimal_service(before_service, (ROOT / 'server/archive_backend/service.py').read_text('utf-8-sig'))
    fields = next(node.value for node in ast.parse(before_service).body if isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == 'FIELDS' for target in node.targets))
    commands = sorted(set(ast.literal_eval(fields)) | {'lottery_snapshot'})
    compatibility = data.setdefault('compatible_config_hashes', {})
    assert BASE not in compatibility
    compatibility[BASE] = {'commands': commands, 'upgrade_commands': []}
    assert all(data['configs'][name] == value for name,value in parent['configs'].items() if name not in row_changes)
    assert all(data['sources'][name] == value for name,value in parent['sources'].items() if name not in sources_changed)
    assert all(compatibility[name] == value for name,value in parent.get('compatible_config_hashes', {}).items())
    packed = canonical(data)
    digest = sha(packed)
    candidate = OUT / 'candidate'
    directory = candidate / 'addon/server/bundles' / digest
    write(directory / 'bundle.json', packed)
    for name,text in data['sources'].items():
        write(directory / name, text.encode('utf-8'))
    Bundle(directory)
    write(candidate / 'backend/archive_backend/service.py', service.encode('utf-8'))
    write(candidate / 'backend/archive_backend/unique_points.py', (ROOT / 'server/archive_backend/unique_points.py').read_text('utf-8-sig').encode())
    write(candidate / 'addon/server/bundles/current.json', canonical({'hash':digest,'protocol':1}))
    write(candidate / 'addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
        ('-- AUTO-GENERATED by tools/points_goods_unique_20261018/build_release.py\nreturn { protocol = 1, hash = "'+digest+'" }\n').encode())
    for name in source_csv:
        write(candidate / 'addon' / name, (ROOT / name).read_bytes())
    configuration = canonical({'configs':data['configs'], 'compatible_config_hashes':compatibility})
    write(OUT / 'configuration.json', configuration)
    (OUT / 'service_minimal.diff').write_text(''.join(difflib.unified_diff(before_service.splitlines(True), service.splitlines(True),
        fromfile='online/service.py',tofile='candidate/service.py')), encoding='utf-8')
    ignored = sorted(sku for sku in compiled if sku not in {'video_p089','video_p103'} and compiled[sku] != old_products[sku])
    approved_csv = {'data/csv/商城兑换系统/commerce_products.csv', 'data/csv/抽奖系统/lottery_item_definitions.csv'}
    assert set(source_csv) == approved_csv, 'candidate_csv_file_scope_changed'
    bundle_prefix = 'addon/server/bundles/' + digest + '/'
    approved_files = {
        'backend/archive_backend/service.py', 'backend/archive_backend/unique_points.py',
        'addon/server/bundles/current.json', 'addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
        *('addon/' + name for name in approved_csv),
        bundle_prefix + 'bundle.json', *(bundle_prefix + name for name in parent['sources']),
    }
    actual_files = {path.relative_to(candidate).as_posix() for path in candidate.rglob('*') if path.is_file()}
    assert actual_files == approved_files, 'candidate_file_whitelist_mismatch:' + repr(sorted(actual_files ^ approved_files))
    assert not any(path.is_symlink() for path in candidate.rglob('*')), 'candidate_symlink_refused'
    archive_files = {name:sha((candidate/name).read_bytes()) for name in sorted(approved_files)}
    plan = dict(version=1,kind='unique_points_archive_only',status='CANDIDATE_NOT_SEALED',
        archive_baseline=audit['archive_release'],archive_release=RELEASE,payment_release=audit['payment_release'],parent_bundle=BASE,bundle=digest,
        archive_manifest_sha256=audit['archive_manifest_sha256'],payment_manifest_sha256=audit['payment_manifest_sha256'],
        payment_catalog_hash=audit['catalog_hash'],archive_files=archive_files,row_changes=row_changes,sources_changed=sources_changed,
        old_sync_sha256=audit['functions']['public.archive_sync_config(text,jsonb)']['sha256'],
        configuration_sha256=sha(configuration),old_config_rows=audit['config_rows'],
        ignored_unrelated_compiled_skus=ignored,local_pointer_sha256={name:sha(raw) for name,raw in pointers.items()},
        no_inventory_migration=True,no_player_updates=True,no_payment_changes=True,production_deployed=False)
    if seal:
        digest_jsonb = jsonb_hash(configuration)
        before = audit['functions']['public.archive_sync_config(text,jsonb)']['definition']
        marker = ' -- Reviewed 58-yuan monthly pass: one exact configuration, unchanged reward rules.\n'
        assert before.count(marker) == 1
        insert = " -- Reviewed unique points: exact immutable configuration; no player migration.\n" + \
            " if p_hash='"+digest+"' then\n" + \
            "  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'"+digest_jsonb+"' then\n" + \
            "   raise exception 'archive_unique_points_configuration_mismatch';\n  end if;\n" + \
            "  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;\n" + \
            "  select config into v from archive_config_sets where config_hash=p_hash;\n" + \
            "  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;\n" + \
            "  return jsonb_build_object('ok',true);\n end if;\n"
        after = before.replace(marker, insert + marker, 1)
        write(OUT / 'archive_sync_before.sql', before.encode())
        write(OUT / 'archive_sync_candidate.sql', after.encode())
        plan.update(status='SEALED_NOT_DEPLOYED',configuration_jsonb_sha256=digest_jsonb,new_sync_sha256=sha(after.encode()),
            operator_sha256=sha(Path(__file__).with_name('remote_operator.py').read_bytes()))
        payload = {'plan.json':canonical(plan),'configuration.json':configuration,'archive_sync_before.sql':before.encode(),'archive_sync_candidate.sql':after.encode()}
        payload.update({'archive/'+name:(candidate/name).read_bytes() for name in archive_files})
        packed_tar = io.BytesIO()
        with gzip.GzipFile(fileobj=packed_tar,mode='wb',mtime=0) as zipped:
            with tarfile.open(fileobj=zipped,mode='w') as archive:
                for name,raw in sorted(payload.items()):
                    info=tarfile.TarInfo(name);info.size=len(raw);info.mode=0o600;archive.addfile(info,io.BytesIO(raw))
        write(OUT / 'release.tar.gz', packed_tar.getvalue())
        plan['tar_sha256'] = sha(packed_tar.getvalue())
    (OUT / 'plan.json').write_bytes(canonical(plan))
    assert all((ROOT/name).read_bytes()==raw for name,raw in pointers.items()), 'local_pointer_changed'
    print(json.dumps({key:plan[key] for key in ('status','bundle','archive_release','row_changes','sources_changed','ignored_unrelated_compiled_skus')},ensure_ascii=False))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seal',action='store_true',help='Compute a read-only server jsonb hash and seal the reviewed payload; never deploy.')
    main(parser.parse_args().seal)
