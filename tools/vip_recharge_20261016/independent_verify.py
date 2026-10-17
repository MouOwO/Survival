"""Independent read-only post-publication VIP checks; no profile/payment actions."""
from pathlib import Path
import importlib.util, json

ROOT=Path(__file__).resolve().parents[2]
plan=json.loads((ROOT/'design_refs/vip_recharge_20261016/release/release_plan.json').read_text(encoding='utf-8'))
old=json.loads((ROOT/'design_refs/vip_recharge_20261016/deployment/readonly_versions.json').read_text(encoding='utf-8'))
spec=importlib.util.spec_from_file_location('vip_audit_transport',Path(__file__).with_name('payment_audit.py'))
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
mod.OUT=ROOT/'design_refs/vip_recharge_20261016/deployment'
CODE=r'''
from pathlib import Path
from types import SimpleNamespace
import ast,hashlib,json,subprocess,sys,urllib.request
sys.dont_write_bytecode=True
checks=[]
def need(value,name):
 assert value,name
 checks.append(name)
def digest(raw):return hashlib.sha256(raw).hexdigest()
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
need(str(archive)==PLAN['target_release'],'expected_new_archive_release')
need(str(payment)==PLAN['old_payment'],'payment_release_unchanged')
need(digest((payment/'manifest.json').read_bytes())==OLD['payment_manifest_sha256'],'payment_manifest_unchanged')
manifest=json.loads((archive/'release_manifest.json').read_text())
source_hashes={}
for name,expected in PLAN['files'].items():
 if not name.startswith('backend/'):continue
 raw=(archive/name).read_bytes();source_hashes[name]=digest(raw)
 need(source_hashes[name]==expected,'published_source_matches_plan:'+name)
 need(manifest['files'][name]==expected,'source_manifest_matches_plan:'+name)
need(len(source_hashes)==3,'exactly_three_reviewed_backend_sources')
pointer=json.loads((archive/'addon/server/bundles/current.json').read_text())
need(pointer['hash']==PLAN['bundle'],'archive_bundle_unchanged')
# Static integration check plus installing the published hook on a read-only
# in-memory stub. No profile loader, login, command, or server RPC is invoked.
sys.path.insert(0,str(archive/'backend'))
from archive_backend.bundle import Bundle
from archive_backend import vip_progression
source=(archive/'backend/archive_backend/service.py').read_text()
parsed=ast.parse(source)
install_node=next(node for node in parsed.body if isinstance(node,ast.FunctionDef) and node.name=='install')
need(any(isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=='install_vip_progression' for node in ast.walk(install_node)), 'published_archive_install_calls_vip_hook')
need('vip_progression' in {alias.name for node in ast.walk(install_node) if isinstance(node,ast.ImportFrom) and node.module=='vip_progression' for alias in node.names} or any(isinstance(node,ast.ImportFrom) and node.module=='vip_progression' for node in ast.walk(install_node)), 'published_archive_imports_vip_hook')
def forbidden(*args,**kwargs):raise AssertionError('profile_or_command_must_not_run')
stub=SimpleNamespace(bundle=Bundle(archive/'addon/server/bundles'/pointer['hash']),profile=forbidden,command=forbidden)
need(vip_progression.install(stub) is stub and stub._vip_progression.service is stub,'published_hook_installs_without_io')
need(stub.profile is not forbidden and stub.profile.__closure__ is not None,'profile_callable_wrapped_by_vip_hook')
need(vip_progression.install(stub) is stub,'hook_install_idempotent')
processes={}
for unit in ['goufayu-api.service','goufayu-payment.service']:
 pid=int(subprocess.check_output(['systemctl','show',unit,'--property=MainPID','--value'],text=True).strip())
 cwd=str(Path('/proc')/str(pid)/'cwd')
 current=Path(cwd).resolve(strict=True)
 expected=archive if unit=='goufayu-api.service' else payment
 need(current==expected,'running_process_current_release:'+unit)
 processes[unit]={'pid':pid,'cwd':str(current)}
sys.path.insert(0,str(payment));from deploy import connection
function_hashes={}
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 need(c.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','expected_database')
 cash=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 need(cash==PLAN['cash_hash'],'cash_catalog_unchanged')
 row=c.execute("SELECT pg_get_userbyid(proowner),prosecdef,proconfig,proacl::text,pg_get_functiondef(oid) FROM pg_proc WHERE oid='public.archive_endless_leaderboard()'::regprocedure").fetchone()
 owner,security_definer,config,acl,definition=row
 need(owner=='goufayu_owner' and security_definer is True,'ranking_owner_and_security_definer')
 need(config==['search_path=pg_catalog, public, extensions, pg_temp'],'ranking_search_path_exact')
 need(digest(definition.encode())=='50f2f3679aaaa78ee6f03f99d58f9fa9ed8dff9d8140bb5842f02a75c3d07ef7','new_ranking_definition_exact')
 for role in ['anon','authenticated','service_role','goufayu_payment']:
  need(not c.execute("SELECT has_function_privilege(%s,'public.archive_endless_leaderboard()','EXECUTE')",(role,)).fetchone()[0],'ranking_execution_denied:'+role)
 need(c.execute("SELECT has_function_privilege('goufayu_app','public.archive_endless_leaderboard()','EXECUTE')").fetchone()[0],'app_ranking_execution_granted')
 need(c.execute("SELECT has_table_privilege(%s,'payments.vip_recharge_levels','SELECT')",(owner,)).fetchone()[0],'ranking_owner_threshold_table_access')
 ranking=c.execute('SELECT public.archive_endless_leaderboard()').fetchone()[0]
 need(ranking.get('ok') is True and isinstance(ranking.get('entries'),list) and len(ranking['entries'])<=100,'live_ranking_response_and_limit')
 for item in ranking['entries']:
  need(type(item.get('vip_level')) is int and 0<=item['vip_level']<=12,'ranking_vip_level_range')
  need(type(item.get('vip_medal_level')) is int and 0<=item['vip_medal_level']<=10,'ranking_medal_range')
  need(set(item)=={'entry_id','steam_id','best_floor','endless_score','vip_level','vip_medal_level'},'ranking_public_fields_no_recharge_amount')
 for signature,expected in [('payments.credit_vip_recharge()',OLD['vip_recharge_trigger_sha256']),
                            ('payments.apply_effects(text,jsonb,boolean)',PLAN['apply_sha']),
                            ('public.archive_sync_config(text,jsonb)',PLAN['sync_sha'])]:
  value=c.execute('SELECT pg_get_functiondef(%s::regprocedure)',(signature,)).fetchone()[0]
  function_hashes[signature]=digest(value.encode())
  need(function_hashes[signature]==expected,'unchanged_function:'+signature)
 c.rollback()
health={}
for name,port in [('archive',8765),('payment',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:
  body=json.load(response)
  need(response.status==200 and body.get('ok') is True,'health:'+name)
  health[name]={'ok':True,'service':body.get('service')}
print(json.dumps({'status':'PASS','checks':checks,'check_count':len(checks),
 'archive_release':str(archive),'payment_release':str(payment),'source_sha256':source_hashes,
 'bundle':pointer['hash'],'cash_catalog_hash':cash,'payment_manifest_sha256':OLD['payment_manifest_sha256'],
 'ranking_definition_sha256':digest(definition.encode()),'ranking_owner':owner,'ranking_acl':acl,'ranking_config':config,
 'ranking_entries_checked':len(ranking['entries']),'ranking_private_data_returned':False,
 'function_sha256':function_hashes,'published_hook_static_and_install_check':True,
 'live_profile_hook_invoked':False,'processes':processes,'health':health,
 'database_writes':0,'profile_calls':0,'login_calls':0,'gateway_requests':0,
 'purchase_actions':0,'individual_player_orders_read':False},ensure_ascii=False))
'''
if __name__=='__main__':
    mod.remote('independent_verify','PLAN='+repr(plan)+'\nOLD='+repr(old)+'\n'+CODE)
