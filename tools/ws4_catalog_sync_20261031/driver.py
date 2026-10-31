"""Pinned operator for the isolated WS4 catalog mismatch; no order operations."""
from pathlib import Path
import argparse, base64, hashlib, importlib.util, json, secrets, sys
import re
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/shop_online_20261031'
HERE = Path(__file__).resolve().parent
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def ws4_sql(raw):
    # This isolated cluster has no Supabase anonymous/authenticated roles.
    # Keep PUBLIC/service_role/app revocations; do not create global roles.
    def clause(match):
        roles = [part.strip() for part in match[2].split(b',')]
        if not all(re.fullmatch(rb'[A-Za-z_][A-Za-z0-9_]*', role) for role in roles):
            raise ValueError('unexpected_migration_role_clause')
        kept = [role for role in roles if role.lower() not in (b'anon', b'authenticated')]
        return match[0] if len(kept) == len(roles) else match[1] + b','.join(kept) + match[3]
    return re.sub(rb'(?ims)(^\s*(?:REVOKE|GRANT)\b[^;]*?\b(?:FROM|TO)\s+)([^;]+)(;)', clause, raw)


def ws4_runtime_probe(raw):
    needle = b"NOT has_function_privilege('anon',%s,'EXECUTE')"
    replacement = b"NOT EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=to_regprocedure(%s) AND a.grantee=0 AND a.privilege_type='EXECUTE')"
    assert raw.count(needle) == 1, 'frozen_acl_probe_anchor_changed'
    return raw.replace(needle, replacement)


def transport():
    spec = importlib.util.spec_from_file_location('ws4_catalog_ssh', ROOT / 'tools/archive_caps_20261020/remote_driver.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def remote(source, timeout=90):
    return json.loads(transport().remote(source, timeout=timeout))


def plan():
    target = OUT / 'sync_plan.json'
    assert not target.exists()
    audit = json.loads((OUT / 'ws4_audit.json').read_text('utf8'))
    assert audit['old_release'] == '20261023-auth-v1' and audit['old_bundle'].startswith('47accd81')
    old_plan = json.loads((ROOT / 'output/release_archive_20261029/server_plan/candidate_v3/plan.json').read_text('utf8'))
    files = {'operator.py': (HERE / 'remote_operator.py').read_bytes()}
    migration_files = [
        ('target/202610250001_onboarding.sql', ROOT / 'server/aliyun/database/target/202610250001_onboarding.sql', old_plan['ledger']['target/202610250001_onboarding.sql']),
        ('security/harden_onboarding.sql', ROOT / 'server/aliyun/database/harden_onboarding.sql', old_plan['ledger']['security/harden_onboarding.sql'])]
    for item in old_plan['migrations']:
        migration_files.append((item['id'], ROOT / 'output/release_archive_20261029/server_plan/candidate_v3/overlay' / item['path'], item['sha256']))
    migrations = []
    for identity, path, digest in migration_files:
        raw = path.read_bytes().replace(b'\r\n', b'\n'); assert SHA(raw) == digest, identity
        name = 'migrations/' + path.name; effective = ws4_sql(raw); files[name] = effective
        migrations.append(dict(id='ws4/catalog_20261031/' + path.name, path=name,
                               sha256=SHA(effective), published_source_id=identity, published_source_sha256=digest))
    probe = ROOT / 'output/release_archive_20261029/server_plan/candidate_v3/overlay/validation/runtime_probe.py'
    original_probe = probe.read_bytes()
    assert SHA(original_probe) == old_plan['overlay']['validation/runtime_probe.py']
    files['runtime_probe_ws4.py'] = ws4_runtime_probe(original_probe)
    snapshot = remote(r'''
from pathlib import Path
import subprocess,json,hashlib,psycopg
sha=lambda raw:hashlib.sha256(raw).hexdigest()
source=Path('/opt/goufayu/releases/20261029-archive-d573588b64d2');old=Path('/opt/goufayu-ws4/releases/20261023-auth-v1')
result={'source_manifest_sha256':sha((source/'release_manifest.json').read_bytes()),'unit_sha256':sha(Path('/etc/systemd/system/goufayu-ws4.service').read_bytes()),'env_sha256':sha(Path('/etc/goufayu-ws4/api.env').read_bytes()),'ws4_wrappers':{p.relative_to(old).as_posix():sha(p.read_bytes()) for p in (old/'backend/workshop_test').glob('*.py')}}
names=['goufayu-api.service','goufayu-payment.service','goufayu-db.service','goufayu-ws4-web.service','goufayu-ws4-payment.service','goufayu-ws4-db.service','nginx.service']
result['retained_services']={name:subprocess.check_output(['systemctl','show',name,'--property=MainPID','--value'],text=True).strip() for name in names}
with psycopg.connect(host='127.0.0.1',port=15432,dbname='goufayu_ws4',user='postgres',password=Path('/etc/goufayu-ws4/admin-password').read_text().strip()) as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 result['database_state']={'functions':{name:sha(body.encode()) for name,body in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')")},'ledger':dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations')),'configs':dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM public.archive_config_sets"))}
 result['absent_roles']=[name for name in ['anon','authenticated'] if not conn.execute('SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=%s)',(name,)).fetchone()[0]]
 conn.rollback()
print(json.dumps(result))
''')
    assert snapshot['unit_sha256'] == audit['unit_sha256'] and snapshot['env_sha256'] == audit['env_sha256']
    assert snapshot['absent_roles'] == ['anon', 'authenticated']
    snapshot.update(schema=1, stage='/root/goufayu_upload/ws4-catalog-20261031-' + secrets.token_hex(8),
                    old_bundle=audit['old_bundle'], app_rpcs=audit['app_rpcs'], migrations=migrations,
                    files={name: SHA(raw) for name, raw in files.items()}, runtime_probe_file='runtime_probe_ws4.py',
                    scope='goufayu_ws4 database /15432 and goufayu-ws4.service /18765 only',
                    protected_services_changed=False, payment_orders_created=0)
    target.write_text(json.dumps(snapshot, indent=2) + '\n', encoding='utf8')
    payload = OUT / 'sealed_inputs'; payload.mkdir()
    for name, raw in files.items():
        path = payload / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
    print(json.dumps(dict(status='READ_ONLY_PLAN_READY', migrations=len(migrations), scope=snapshot['scope'])))


def upload():
    plan = json.loads((OUT / 'sync_plan.json').read_text('utf8'))
    files = {name: (OUT / 'sealed_inputs' / name).read_bytes() for name in plan['files']}
    assert all(SHA(raw) == plan['files'][name] for name, raw in files.items())
    source = 'PLAN=' + repr(plan) + '\nFILES=' + repr({name: base64.b64encode(raw).decode() for name, raw in files.items()}) + '\n' + r'''
from pathlib import Path
import json,base64,hashlib
root=Path(PLAN['stage']);assert root.parent==Path('/root/goufayu_upload') and not root.exists()
root.mkdir(mode=0o700)
for name,encoded in FILES.items():
 path=root/name;assert path.is_relative_to(root) and '..' not in Path(name).parts
 raw=base64.b64decode(encoded,validate=True);assert hashlib.sha256(raw).hexdigest()==PLAN['files'][name]
 path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
 with path.open('xb') as stream:stream.write(raw)
 path.chmod(0o600)
(root/'plan.json').write_text(json.dumps(PLAN));(root/'plan.json').chmod(0o600)
print(json.dumps({'status':'NEW_SEALED_STAGE_UPLOADED','active_services_changed':False}))
'''
    print(json.dumps(remote(source)))


def invoke(action):
    plan = json.loads((OUT / 'sync_plan.json').read_text('utf8'))
    source = 'STAGE_PATH=' + repr(plan['stage']) + '\nPLAN_DATA=' + repr(plan) + '\nACTION=' + repr(action) + '\n' + r'''
from pathlib import Path
import hashlib,json,re,traceback
root=Path(STAGE_PATH);filename=PLAN_DATA.get('operator_file','operator.py')
assert re.fullmatch(r'operator(?:_v[0-9]+)?\.py',filename)
raw=(root/filename).read_bytes()
assert hashlib.sha256(raw).hexdigest()==PLAN_DATA['files'][filename]
scope={'STAGE_PATH':STAGE_PATH,'PLAN_DATA':PLAN_DATA};exec(compile(raw,'sealed_ws4_operator','exec'),scope)
try:result=scope['run'](ACTION)
except Exception as error:
 code=str(error);result={'ok':False,'error':code if re.fullmatch('[a-z0-9_]{1,100}',code) else type(error).__name__,
 'sqlstate':getattr(error,'sqlstate',None),'line':next((f.lineno for f in reversed(traceback.extract_tb(error.__traceback__)) if f.filename=='sealed_ws4_operator'),None)}
 primary=getattr(getattr(error,'diag',None),'message_primary','') or ''
 if primary:result['sql_error_class']=re.sub(r'"[^"]*"|\x27[^\x27]*\x27','<identifier>',primary)[:160]
print(json.dumps(result))
'''
    result = remote(source, timeout=240)
    record = OUT / (action + ('.failed.' + secrets.token_hex(5) + '.json' if result.get('ok') is False else '.json')); assert not record.exists()
    record.write_text(json.dumps(result, indent=2), encoding='utf8')
    print(json.dumps(result))
    if result.get('ok') is False:
        raise SystemExit(1)
    return result


def protect_backup():
    plan = json.loads((OUT / 'sync_plan.json').read_text('utf8'))
    backup = json.loads((OUT / 'quiesce.json').read_text('utf8'))
    source = 'STAGE=' + repr(plan['stage']) + '\nEXPECTED=' + repr(backup) + '\n' + r'''
from pathlib import Path
import json,base64,hashlib
path=Path(EXPECTED['path']);assert path.parent==Path(STAGE) and not path.is_symlink()
raw=path.read_bytes();assert len(raw)==EXPECTED['bytes'] and hashlib.sha256(raw).hexdigest()==EXPECTED['sha256']
print(json.dumps({'data':base64.b64encode(raw).decode()}))
'''
    raw = base64.b64decode(remote(source)['data'], validate=True); assert SHA(raw) == backup['sha256']
    spec = importlib.util.spec_from_file_location('ws4_backup_dpapi', ROOT / 'tools/onboarding_release_20261025/deploy.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    encrypted = module.dpapi(raw); assert SHA(module.dpapi(encrypted, decrypt=True)) == backup['sha256']
    target = OUT / ('ws4-' + backup['sha256'][:16] + '.dump.dpapi'); assert not target.exists(); target.write_bytes(encrypted)
    ack = dict(encrypted_verified=True, sha256=backup['sha256'], encrypted_sha256=SHA(encrypted), bytes=len(encrypted))
    source = 'STAGE=' + repr(plan['stage']) + '\nACK=' + repr(ack) + '\n' + r'''
from pathlib import Path
import json
root=Path(STAGE);backup=json.loads((root/'final_backup.json').read_bytes());assert ACK['sha256']==backup['sha256']
with (root/'offsite_ack.json').open('x') as stream:json.dump(ACK,stream)
(root/'offsite_ack.json').chmod(0o600)
print(json.dumps({'status':'ENCRYPTED_OFFSITE_BACKUP_VERIFIED'}))
'''
    print(json.dumps(remote(source)))
    (OUT / 'protected_backup.json').write_text(json.dumps(ack, indent=2), encoding='utf8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['plan', 'upload', 'prepare', 'clone', 'quiesce', 'protect-backup', 'activate', 'resume'])
    parser.add_argument('--apply', action='store_true', help='Explicitly authorized live API maintenance or encrypted backup transfer')
    args = parser.parse_args(); action = args.action
    if action in ('quiesce', 'protect-backup', 'activate') and not args.apply:
        raise SystemExit('explicit_apply_required_for_live_changes')
    if action == 'plan': plan()
    elif action == 'upload': upload()
    elif action == 'protect-backup': protect_backup()
    else: invoke(action)
