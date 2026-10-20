"""Read-only caps-release fingerprint. Never exports credentials or player rows."""
from pathlib import Path, PurePosixPath
import hashlib
import importlib.util
import json
import subprocess
import sys
import urllib.request

sys.dont_write_bytecode = True
OLD = Path('/opt/goufayu/releases/current').resolve(strict=True)
PAY = Path('/opt/goufayu/payments/current').resolve(strict=True)
assert OLD.name == '20261020-archive-caps-v1', 'archive_release_changed'
assert PAY.name == '20261018-checkout-gcoin-v1', 'payment_release_changed'
canonical = lambda v: json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
sha = lambda b: hashlib.sha256(b).hexdigest()


def member(root,name):
    p=PurePosixPath(name)
    assert p.parts and not p.is_absolute() and '..' not in p.parts and '\\' not in name and ':' not in name and p.as_posix()==name, 'unsafe_manifest_path'
    target=root
    for part in p.parts:
        target=target/part
        assert not target.is_symlink(), 'release_member_symlink'
    assert target.is_file(), 'release_member_missing'
    return target


for name,digest in json.loads((PAY/'manifest.json').read_bytes()).items():
    assert sha(member(PAY,name).read_bytes())==digest, 'payment_member_changed'
raw=(OLD/'release_manifest.json').read_bytes()
assert sha(raw)=='30b3400ce2389c150290810097919e648beeae79dc96cbd4bd1ea27bb6310668', 'archive_manifest_changed'
manifest=json.loads(raw)
for name,digest in manifest['files'].items():
    assert sha(member(OLD,name).read_bytes())==digest, 'release_member_digest_changed'
pointer=json.loads((OLD/'addon/server/bundles/current.json').read_bytes())
assert pointer['hash']=='ecf55dd6ba24d0b391a1640f7e25c06c50d79ec1eb37f0bfcdb86c28afde22f7', 'archive_bundle_changed'
spec=importlib.util.spec_from_file_location('mode_caps_readonly_payment_deploy',PAY/'deploy.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
with module.connection() as conn:
    conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
    assert conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test', 'database_scope_changed'
    conn.execute('SET ROLE goufayu_owner')
    ledger=dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations ORDER BY migration_id'))
    assert ledger.get('target/202610200002_archive_match_modes.sql')=='70a8ddb268ea419431630961653d61e4d2404bc7d1772fb7012e9495d25cf817', 'applied_mode002_changed'
    assert ledger.get('target/202610200003_archive_daily_limits.sql')=='522891724d0d1df7e105f5da4f508a87e4cdd53c4ea21768a1022f26895ce9b2', 'applied_daily003_changed'
    assert 'target/202610200004_mode_unlock_chain.sql' not in ledger, 'mode004_already_applied_replan_required'
    configs={key:sha(canonical(value)) for key,value in conn.execute('SELECT config_hash,config FROM public.archive_config_sets ORDER BY config_hash')}
    functions={}
    for signature,definition,owner,acl,security in conn.execute('''SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl::text,p.prosecdef
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
        AND (p.proowner='goufayu_owner'::regrole OR has_function_privilege('goufayu_app',p.oid,'EXECUTE'))
        AND p.prokind='f' ORDER BY 1'''):
        functions['public.'+signature if not signature.startswith('public.') else signature]=dict(definition=definition,sha256=sha(definition.encode()),owner=owner,acl=acl,security_definer=security)
    assert functions['public.archive_sync_config(text,jsonb)']['sha256']=='4b7f47f62b983770f9d02f81a772bda66e8e4433ba305b4fec6b89a8ed834b5d', 'archive_sync_changed'
    constraints={name:definition for name,definition in conn.execute('''SELECT c.conrelid::regclass::text||':'||c.conname,pg_get_constraintdef(c.oid)
        FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='public' ORDER BY 1''')}
    rpc=[r[0] for r in conn.execute("SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND has_function_privilege('goufayu_app',p.oid,'EXECUTE') ORDER BY 1")]
    app=conn.execute("SELECT rolsuper,rolcreaterole,rolcreatedb,rolreplication,rolbypassrls FROM pg_roles WHERE rolname='goufayu_app'").fetchone()
    memberships=[r[0] for r in conn.execute("SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.roleid WHERE m.member='goufayu_app'::regrole ORDER BY 1")]
    table_access=conn.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','payments') AND c.relkind IN ('r','p','v','m','f') AND has_table_privilege('goufayu_app',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')").fetchone()[0]
    schema_create=conn.execute("SELECT has_schema_privilege('goufayu_app','public','CREATE')").fetchone()[0]
    payment_catalog=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
    payment_functions={r[0]:sha(r[1].encode()) for r in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='payments' ORDER BY 1")}
    conn.rollback()
spec=importlib.util.spec_from_file_location('mode_caps_readonly_api_environment',OLD/'deploy/manage.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
token=module.read_environment(Path('/etc/goufayu/api.env'))['FISHING_API_TOKEN']
headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'}
with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8765/ready',headers=headers),timeout=8) as response:
    ready=json.load(response)
    assert response.status==200 and ready.get('ok') is True and ready.get('database')=='ready', 'archive_database_not_ready'
with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8765/v1/archive/config',headers=headers,data=b'{}',method='POST'),timeout=8) as response:
    config=json.load(response)
    assert response.status==200 and config.get('ok') is True and config.get('config_hash')==pointer['hash'], 'archive_loaded_bundle_mismatch'
process=subprocess.run(['systemctl','show','goufayu-api.service','--property=MainPID','--value'],capture_output=True,text=True,timeout=3)
pid=process.stdout.strip()
assert process.returncode==0 and pid.isdigit() and int(pid)>1 and Path('/proc/'+pid+'/cwd').resolve()==OLD, 'archive_running_wrong_release'
with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=8) as response:
    assert response.status==200 and json.load(response).get('ok') is True, 'payment_unhealthy'
print(json.dumps(dict(status='MODE_RELEASE_READONLY_PREFLIGHT_PASS',archive_release=OLD.name,
    archive_manifest_sha256=sha(raw),archive_bundle=pointer['hash'],payment_release=PAY.name,
    payment_manifest_sha256=sha((PAY/'manifest.json').read_bytes()),payment_catalog_hash=payment_catalog,
    payment_function_hashes=payment_functions,ledger=ledger,config_rows=configs,functions=functions,constraints=constraints,
    permissions=dict(rpc=rpc,role_flags=list(app),memberships=memberships,table_access_count=table_access,schema_create=schema_create),
    health=dict(database_ready=True,loaded_bundle=pointer['hash'],running_release_matches=True,payment_healthy=True),
    database_writes=0,orders_created=0,account_rows_exported=0,remote_files_written=0),ensure_ascii=False))
