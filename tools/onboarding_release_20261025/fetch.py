"""Fetch a new read-only pinned deployment baseline without credentials or account rows."""
from pathlib import Path
import importlib.util,json,hashlib,base64
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('onboarding_pinned_transport',ROOT/'tools/archive_caps_20261020/remote_driver.py')
transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
OUT=ROOT/'tmp/onboarding_rollout_20261025'
assert not (OUT/'baseline.json').exists(), 'baseline_already_exists'
OUT.mkdir(parents=True,exist_ok=True)
SOURCE=r'''
from pathlib import Path
import json,hashlib,base64,sys,subprocess
sha=lambda raw:hashlib.sha256(raw).hexdigest()
root=Path('/opt/goufayu/releases/current').resolve(strict=True)
assert root.parent==Path('/opt/goufayu/releases')
manifest=(root/'release_manifest.json').read_bytes();data=json.loads(manifest)
for name,digest in data['files'].items():
 p=root/name
 assert p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root) and sha(p.read_bytes())==digest
pay=Path('/opt/goufayu/payments/current').resolve(strict=True)
assert pay.parent==Path('/opt/goufayu/payments')
sys.path.insert(0,str(pay))
from deploy import connection
sources={}
for name in ('backend/archive_backend/service.py','backend/fishing_api/postgres.py','backend/archive_backend/onboarding.py'):
 p=root/name
 if p.exists():sources[name]=base64.b64encode(p.read_bytes()).decode()
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.info.dbname=='goufayu_test'
 ledger=dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations ORDER BY 1'))
 functions={signature:sha(definition.encode()) for signature,definition in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY 1")}
 definitions={signature:definition for signature,definition in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('match_profile_login','ensure_player_gameplay_stats') ORDER BY 1")}
 tables=[r[0]+'.'+r[1] for r in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2")]
 columns=list(conn.execute("SELECT table_name,column_name,data_type,column_default,is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('survival_players','match_profile_sessions','_goufayu_migrations') ORDER BY table_name,ordinal_position"))
 conn.rollback()
services={}
for service in ('goufayu-api.service','goufayu-payment.service'):
 services[service]={key:subprocess.check_output(['systemctl','show','--property='+key,'--value',service],text=True).strip() for key in ('MainPID','ActiveState')}
bundle=json.loads((root/'addon/server/bundles/current.json').read_bytes())
result=dict(ok=True,release=root.name,manifest_sha256=sha(manifest),manifest=data,payment_release=pay.name,payment_manifest_sha256=sha((pay/'manifest.json').read_bytes()),services=services,bundle=bundle,ledger=ledger,functions=functions,definitions=definitions,tables=tables,columns=columns,sources=sources,all_backend_hashes={p.relative_to(root).as_posix():sha(p.read_bytes()) for p in (root/'backend').rglob('*.py')})
print(json.dumps(result))
'''
result=json.loads(transport.remote(SOURCE,timeout=60).strip().splitlines()[-1])
assert result.pop('ok')
for name,encoded in result.pop('sources').items():
 p=OUT/'baseline'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(base64.b64decode(encoded,validate=True))
(OUT/'baseline.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(ok=True,phase='READ_ONLY_BASELINE',release=result['release'],bundle=result['bundle'],payment_release=result['payment_release'],services=result['services'],ledger_entries=len(result['ledger']),table_count=len(result['tables']),function_count=len(result['functions']),onboarding_already_present=any('onboarding' in k for k in result['functions']))))
