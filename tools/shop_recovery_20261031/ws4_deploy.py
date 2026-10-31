"""Explicit WS4 redemption phases; schema-only synthetic validation and DPAPI backup."""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,re,secrets,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/shop_recovery_20261031/ws4'
HERE=Path(__file__).resolve().parent
SHA=lambda raw:hashlib.sha256(raw).hexdigest()
canonical=lambda value:json.dumps(value,sort_keys=True,separators=(',',':')).encode()


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


driver=module('ws4_redemption_transport',ROOT/'tools/ws4_catalog_sync_20261031/driver.py')


def files():
    result={'operator.py':(HERE/'ws4_operator.py').read_bytes(),'patcher.py':(ROOT/'tools/redemption_codes/patch_backend.py').read_bytes(),
        'migration.sql':driver.ws4_sql((ROOT/'server/aliyun/database/target/202610290002_redemption_codes.sql').read_bytes().replace(b'\r\n',b'\n')),
        'codes.json':(ROOT/'output/redemption_codes_20261029/private/server_codes_ready.json').read_bytes()}
    for name in ('redemption_codes.py','redemption_worker.lua','redemption_settlement.lua'):
        result['overlay/backend/archive_backend/'+name]=(ROOT/'server/archive_backend'/name).read_bytes()
    raw=(ROOT/'tools/redemption_codes/database_checks.py').read_bytes().replace(b'\r\n',b'\n')
    for old,new in [(b'goufayu_redeem_clone_',b'goufayu_ws4_redeem_'),(b'port=5432',b'port=15432'),
                    (b'/etc/goufayu/app-password',b'/etc/goufayu-ws4/app-password')]:
        assert raw.count(old)==1,'frozen_test_adapter_anchor_changed';raw=raw.replace(old,new)
    result['database_checks.py']=raw
    return result


def plan():
    OUT.mkdir(parents=True,exist_ok=True);target=OUT/'plan.json';assert not target.exists()
    approved=json.loads((ROOT/'output/shop_recovery_20261031/backend_plan.json').read_bytes())
    payload=files();registry=json.loads(payload['codes.json'])['codes']
    assert len(registry)==128 and SHA(payload['codes.json'])==approved['registry']['sha256']
    assert all('code' not in row and 'raw_code' not in row for row in registry)
    nonce=secrets.token_hex(6);release='20261031-redemption-ws4-'+nonce;stage='/root/goufayu_upload/ws4-redemption-20261031-'+nonce
    protected=['goufayu-api.service','goufayu-payment.service','goufayu-db.service','goufayu-ws4-web.service','goufayu-ws4-payment.service','goufayu-ws4-db.service','nginx.service']
    preliminary={'release':release,'retained_services':protected}
    wrapper_pins=json.loads((ROOT/'output/shop_online_20261031/sync_plan.json').read_bytes())['ws4_wrappers']
    source='STAGE_PATH='+repr(stage)+'\nPLAN_DATA='+repr(preliminary)+'\nWRAPPERS='+repr(wrapper_pins)+'\nOP='+repr(base64.b64encode(payload['operator.py']).decode())+'\n'+r'''
from pathlib import Path
import base64,hashlib,json,subprocess
scope={'STAGE_PATH':STAGE_PATH,'PLAN_DATA':PLAN_DATA};exec(compile(base64.b64decode(OP,validate=True),'ws4_plan_definitions','exec'),scope)
root=scope['OLD'];pid=scope['command'](['systemctl','show','goufayu-ws4.service','--property=MainPID','--value']).decode().strip()
assert Path('/proc/'+pid+'/cwd').resolve()==root/'backend'
manifest=json.loads((root/'release_manifest.json').read_bytes());source_files=dict(manifest['files'])
for path in (root/'backend').rglob('*'):
 if path.is_file() and path.suffix in ('.py','.lua') and '__pycache__' not in path.parts:
  assert not path.is_symlink() and path.resolve().is_relative_to(root)
  name=path.relative_to(root).as_posix();digest=hashlib.sha256(path.read_bytes()).hexdigest()
  if name in source_files:assert source_files[name]==digest
  else:assert name in WRAPPERS and WRAPPERS[name]==digest;source_files[name]=digest
assert all(source_files.get(name)==digest for name,digest in WRAPPERS.items())
for name,digest in source_files.items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest
with scope['connect']() as conn:
 conn.execute('SET TRANSACTION READ ONLY');scope['pending'](conn);database=scope['state'](conn)
result={'parent_manifest_sha256':scope['sha']((root/'release_manifest.json').read_bytes()),'unit_sha256':scope['sha'](scope['UNIT'].read_bytes()),'env_sha256':scope['sha'](scope['ENV'].read_bytes()),'source_files':source_files,'database_state':database,'retained_services':scope['services']()}
print(json.dumps(result))
'''
    observed=driver.remote(source,timeout=60)
    assert observed['parent_manifest_sha256']==approved['observed']['parent_manifest_sha256']
    for name,pin in approved['observed']['patches'].items():assert observed['source_files'][name]==pin['before']
    overlay={name.removeprefix('overlay/'):SHA(raw) for name,raw in payload.items() if name.startswith('overlay/')}
    overlay.update({name:pin['after'] for name,pin in approved['observed']['patches'].items()})
    pins={name:SHA(raw) for name,raw in payload.items()};pins.update({'overlay/'+name:digest for name,digest in overlay.items()})
    value={**observed,'stage':stage,'release':release,'registry_count':128,'overlay':overlay,'files':pins,
        'approved_patch_pins':approved['observed']['patches'],'authorized_scope':'WS4_3_TABLES_2_RPCS_EXISTING_128_DEFINITIONS',
        'backup_policy':'SERVER_FULL_LOCAL_DPAPI_ONLY','test_policy':'SCHEMA_ONLY_AND_SYNTHETIC_ROWS'}
    target.write_bytes(canonical(value));print(json.dumps({'status':'SEALED_WS4_PLAN','files':len(value['source_files']),'codes':128,'server_modified':False}))


def upload():
    value=json.loads((OUT/'plan.json').read_bytes());payload=files()
    assert all(SHA(raw)==value['files'][name] for name,raw in payload.items())
    source='PLAN='+repr(value)+'\nFILES='+repr({name:base64.b64encode(raw).decode() for name,raw in payload.items()})+'\n'+r'''
from pathlib import Path
import base64,hashlib,json,importlib.util
root=Path(PLAN['stage']);assert root.parent==Path('/root/goufayu_upload') and not root.exists();root.mkdir(mode=0o700)
for name,encoded in FILES.items():
 path=root/name;assert '..' not in Path(name).parts and path.is_relative_to(root)
 raw=base64.b64decode(encoded,validate=True);assert hashlib.sha256(raw).hexdigest()==PLAN['files'][name]
 path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
 with path.open('xb') as stream:stream.write(raw)
 path.chmod(0o600)
spec=importlib.util.spec_from_file_location('sealed_redemption_patcher',root/'patcher.py');patcher=importlib.util.module_from_spec(spec);spec.loader.exec_module(patcher)
old=Path('/opt/goufayu-ws4/releases/20261031-catalog-d573588b64d2')
for name,kind in [('backend/archive_backend/service.py','service'),('backend/fishing_api/postgres.py','rpc')]:
 raw=(old/name).read_bytes();assert hashlib.sha256(raw).hexdigest()==PLAN['approved_patch_pins'][name]['before']
 changed=patcher.patch(raw,kind);assert hashlib.sha256(changed).hexdigest()==PLAN['overlay'][name]
 path=root/'overlay'/name;path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
 with path.open('xb') as stream:stream.write(changed)
 path.chmod(0o600)
(root/'plan.json').write_bytes(json.dumps(PLAN,sort_keys=True,separators=(',',':')).encode());(root/'plan.json').chmod(0o600)
print(json.dumps({'status':'SEALED_STAGE_UPLOADED','live_changed':False}))
'''
    result=driver.remote(source,timeout=90);(OUT/'uploaded.json').write_bytes(canonical(result));print(json.dumps(result))


def invoke(action):
    value=json.loads((OUT/'plan.json').read_bytes())
    source='STAGE_PATH='+repr(value['stage'])+'\nPLAN_DATA='+repr(value)+'\nACTION='+repr(action)+'\n'+r'''
from pathlib import Path
import hashlib,json,re,traceback
root=Path(STAGE_PATH);assert hashlib.sha256((root/'plan.json').read_bytes()).hexdigest()==hashlib.sha256(json.dumps(PLAN_DATA,sort_keys=True,separators=(',',':')).encode()).hexdigest()
raw=(root/'operator.py').read_bytes();assert hashlib.sha256(raw).hexdigest()==PLAN_DATA['files']['operator.py']
scope={'STAGE_PATH':STAGE_PATH,'PLAN_DATA':PLAN_DATA};exec(compile(raw,'sealed_ws4_redemption','exec'),scope)
try:result=scope['run'](ACTION)
except Exception as error:
 code=str(error);result={'ok':False,'error':code if re.fullmatch('[a-z0-9_]{1,100}',code) else type(error).__name__,'sqlstate':getattr(error,'sqlstate',None),'line':next((frame.lineno for frame in reversed(traceback.extract_tb(error.__traceback__)) if frame.filename=='sealed_ws4_redemption'),None)}
print(json.dumps(result))
'''
    result=driver.remote(source,timeout=240);name=action+('.failed.'+secrets.token_hex(5) if result.get('ok') is False else '')+'.json'
    target=OUT/name;assert not target.exists();target.write_bytes(canonical(result))
    summary={key:result[key] for key in ('ok','status','error','sqlstate','line','codes','codes_registered','release','old_business_tables_unchanged') if key in result}
    print(json.dumps(summary))
    if result.get('ok') is False:raise SystemExit(1)
    return result


def protect_backup():
    value=json.loads((OUT/'plan.json').read_bytes());backup=json.loads((OUT/'quiesce.json').read_bytes())
    source='STAGE='+repr(value['stage'])+'\nBACKUP='+repr(backup)+'\n'+r'''
from pathlib import Path
import base64,hashlib,json
path=Path(BACKUP['path']);assert path.parent==Path(STAGE) and not path.is_symlink()
raw=path.read_bytes();assert len(raw)==BACKUP['bytes'] and hashlib.sha256(raw).hexdigest()==BACKUP['sha256']
print(json.dumps({'data':base64.b64encode(raw).decode()}))
'''
    raw=base64.b64decode(driver.remote(source,timeout=60)['data'],validate=True);assert SHA(raw)==backup['sha256']
    crypto=module('ws4_redemption_dpapi',ROOT/'tools/onboarding_release_20261025/deploy.py')
    encrypted=crypto.dpapi(raw);assert SHA(crypto.dpapi(encrypted,decrypt=True))==backup['sha256']
    target=OUT/('ws4-redemption-'+backup['sha256'][:16]+'.dump.dpapi');assert not target.exists();target.write_bytes(encrypted)
    ack={'encrypted_verified':True,'sha256':backup['sha256'],'encrypted_sha256':SHA(encrypted),'bytes':len(encrypted)}
    source='STAGE='+repr(value['stage'])+'\nACK='+repr(ack)+'\n'+r'''
from pathlib import Path
import json
root=Path(STAGE);backup=json.loads((root/'final_backup.json').read_bytes());assert backup['sha256']==ACK['sha256']
with (root/'offsite_ack.json').open('x') as stream:json.dump(ACK,stream)
(root/'offsite_ack.json').chmod(0o600)
print(json.dumps({'status':'DPAPI_BACKUP_VERIFIED'}))
'''
    result=driver.remote(source);(OUT/'protected_backup.json').write_bytes(canonical(ack));print(json.dumps(result))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['plan','upload','prepare','clone','quiesce','protect-backup','activate','resume','verify']);parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    if args.action in ('quiesce','protect-backup','activate','resume') and not args.apply:raise SystemExit('explicit_apply_required')
    if args.action=='plan':plan()
    elif args.action=='upload':upload()
    elif args.action=='protect-backup':
        try:protect_backup()
        except Exception:invoke('resume');raise
    else:invoke(args.action)
