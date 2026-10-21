"""Read-only live HTTP/database proof after sealed activation; no player reads."""
from pathlib import Path
import hashlib
import importlib.util
import json

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tmp/benefits_20261021/release_candidate'
spec=importlib.util.spec_from_file_location('benefits_transport',ROOT/'tools/archive_caps_20261020/remote_driver.py')
transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
seal=json.loads((OUT/'seal.json').read_bytes())
source='STAGE='+repr(seal['stage'])+'\nPLAN_SHA='+repr(seal['plan_sha256'])+'\n'
source+='''
from pathlib import Path
import hashlib,json,sys,subprocess,urllib.request
sha=lambda raw:hashlib.sha256(raw).hexdigest()
stage=Path(STAGE)
assert sha((stage/'plan.json').read_bytes())==PLAN_SHA
plan=json.loads((stage/'plan.json').read_bytes())
release=Path('/opt/goufayu/releases/current').resolve(strict=True)
assert release.name==plan['new_release']
manifest_raw=(release/'release_manifest.json').read_bytes();manifest=json.loads(manifest_raw)
assert manifest['archive_bundle']==plan['bundle']
for name,digest in manifest['files'].items():assert sha((release/name).read_bytes())==digest
assert Path('/opt/goufayu/payments/current').resolve().name==plan['payment_release']
pay=Path('/opt/goufayu/payments/current').resolve()
assert sha((pay/'manifest.json').read_bytes())==plan['payment_manifest_sha256']
pid=subprocess.check_output(['systemctl','show','--property=MainPID','--value','goufayu-payment.service'],text=True).strip()
assert pid==plan['payment_pid']=='5427'
config=json.loads(Path('/etc/goufayu-payment/config.json').read_bytes())
request=urllib.request.Request('http://127.0.0.1:8765/v1/lottery/catalog',data=b'{"md5":""}',method='POST',headers={'Content-Type':'application/json','Authorization':'Bearer '+config['game_token']})
with urllib.request.urlopen(request,timeout=20) as response:catalog=json.load(response)
assert catalog.get('ok') is True and catalog['config_hash']==plan['bundle']
assert len(catalog['catalog_md5'])==32
sys.path.insert(0,str(pay))
from deploy import connection
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.info.dbname=='goufayu_test'
 ledger=dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations'))
 assert ledger=={**plan['audit']['ledger'],**{item['id']:item['sha256'] for item in plan['migrations']}}
 configs=dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM archive_config_sets"))
 assert all(configs.get(key)==value for key,value in plan['audit']['configs'].items())
 assert set(configs)==set(plan['audit']['configs'])|{plan['bundle'],plan['rollback_bundle']}
 functions={}
 for signature,definition in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'"):
  signature=signature if signature.startswith('public.') else 'public.'+signature
  functions[signature]=sha(definition.encode())
 changed=sorted(key.split('(')[0].split('.')[-1] for key,value in plan['audit']['functions'].items() if functions.get(key)!=value['sha256'])
 expected=['archive_capture_online','archive_commit_lottery','archive_fishing_daily_limit','archive_online_pending','archive_prepare','archive_resume','archive_sync_config','archive_unique_points_20261019_valid']
 assert changed==expected
 assert set(functions)-set(plan['audit']['functions'])=={'public.archive_stackable_items_20261021_valid(jsonb)'}
 constraints=dict(conn.execute("SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.player_archive_state'::regclass"))
 assert all(constraints.get(key)==value for key,value in plan['audit']['constraints'].items())
 assert set(constraints)-set(plan['audit']['constraints'])=={'archive_stackable_items_20261021_check'}
 conn.rollback()
for port in (8765,8766):
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:assert json.load(response)['ok'] is True
backup=json.loads((stage/'private_backup.json').read_bytes())
assert backup['includes_game_and_payments'] is True
dump=Path(backup['local_backup'])
assert str(dump.parent)=='/var/backups/goufayu-payment' and not dump.is_symlink() and dump.is_file()
assert dump.stat().st_size>0 and dump.stat().st_mode & 0o077==0
with dump.open('rb') as stream:assert stream.read(5)==b'PGDMP'
backup_proof=dict(verified=True,includes_game_and_payments=True,custom_format=True,size=dump.stat().st_size,sha256=sha(dump.read_bytes()),downloaded=False,record=str(stage/'private_backup.json'))
result=dict(ok=True,phase='LIVE_HTTP_DATABASE_VERIFIED',release=release.name,bundle=plan['bundle'],rollback_release=plan['rollback_release'],rollback_bundle=plan['rollback_bundle'],manifest_sha256=sha(manifest_raw),catalog_md5=catalog['catalog_md5'],payment_pid=pid,payment_untouched=True,ledger_entries=len(ledger),ledger_additions=len(plan['migrations']),new_configurations=2,functions_changed=changed,new_function='archive_stackable_items_20261021_valid',new_constraint='archive_stackable_items_20261021_check',existing_ledger_configurations_preserved=True,backup=backup_proof,real_player_reads=0,real_player_writes=0,database_writes=0)
print(json.dumps(result))
'''
result=json.loads(transport.remote(source,timeout=110).strip().splitlines()[-1])
assert result['ok']
(OUT/'live_verified.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
