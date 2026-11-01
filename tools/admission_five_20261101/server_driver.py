"""Explicit pinned-SSH operator for one additional approved Steam account.

audit/plan read live metadata. prepare creates new inactive trees/backups only.
activate additionally requires --apply and a reviewed immutable plan SHA256.
"""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,re,secrets,subprocess,sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OPERATOR='tools/admission_five_20261101/server_operator.py'
SOURCE=('server/archive_backend/test_access.py','server/workshop_test/run_api.py','server/player_web_auth/service.py')
BEFORE={
 SOURCE[0]:'3a21a53ba1a38e50cb946db04f1de78de93256873086e16f6757bbc71b385830',
 SOURCE[1]:'feb7569e2ae3c6b5ffe8dac4f44e70644e919cc00da9ec0853e9f47e843168c3',
 SOURCE[2]:'38b66fa9de7bd1ef3b7d5851d1c6cf928d162efd7360e32228601a2c1d6b5d79'}
ADDED='76561198296534615'
IDS=['76561198424163156','76561198845461206','76561198104787442','76561198974301984',ADDED]


def need(value,code):
 if not value:raise RuntimeError(code)


def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(value):return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()


def blob(revision,name):
 need(re.fullmatch(r'[a-f0-9]{40}',revision) is not None,'immutable_source_revision_required')
 return subprocess.check_output(['git','cat-file','blob',revision+':'+name],cwd=ROOT)


def committed(revision):
 resolved=subprocess.check_output(['git','rev-parse','--verify',revision+'^{commit}'],cwd=ROOT).decode().strip()
 need(re.fullmatch(r'[a-f0-9]{40}',resolved) is not None,'invalid_source_revision')
 operator=blob(resolved,OPERATOR)
 need(operator==(HERE/'server_operator.py').read_bytes().replace(b'\r\n',b'\n'),'operator_changed_since_source_commit')
 overlays={name:blob(resolved,name) for name in SOURCE}
 for name,raw in overlays.items():need(b'\r' not in raw,'committed_lf_required');compile(raw,name,'exec')
 return resolved,operator,overlays


def remote(operator,action,plan=None,overlays=None):
 spec=importlib.util.spec_from_file_location('five_account_pinned_transport',ROOT/'tools/archive_caps_20261020/remote_driver.py')
 transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
 source='OP_ACTION='+repr(action)+'\nOP_PLAN='+repr(plan)+'\nOP_OVERLAYS='+repr(overlays)+'\n'+operator.decode()
 value=json.loads(transport.remote(source,timeout=300))
 need(value.get('ok') is True,'server_operation_did_not_pass');return value


def write_new(path,value):
 path=Path(path);need(path.resolve().is_relative_to((ROOT/'output/admission_five_20261101').resolve()),'report_scope_invalid')
 path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('xb') as stream:stream.write(canonical(value))


def make_plan(revision,operator,overlays,audit):
 live=audit['live']
 roles={'api':('/opt/goufayu-ws4/releases/20261031-redemption-ws4-23e3ab768478',{
   SOURCE[0]:'backend/archive_backend/test_access.py',SOURCE[1]:'backend/workshop_test/run_api.py'}),
  'web':('/opt/goufayu-ws4-web/releases/20261031-game-diagnostics-v2',{SOURCE[2]:'player_web_auth/service.py'})}
 for role,(parent,files) in roles.items():
  need(live['roles'][role]['root']==parent,'unexpected_parent_release')
  for source,name in files.items():need(live['inventories'][role]['files'][name]['sha256']==BEFORE[source],'source_before_changed')
 nonce=secrets.token_hex(6);release='20261101-admission-five-'+nonce
 return {'schema':1,'status':'REVIEWED_SOURCE_LIVE_PLAN_NOT_ACTIVE','source_revision':revision,'operator_sha256':sha(operator),
  'release':release,'stage':'/root/goufayu_upload/admission-five-'+release,'live':live,
  'approved_steamids64':IDS,'added_steamid64':ADDED,'max_players':4,
  'overlay':{name:{'sha256':sha(raw),'bytes':len(raw)} for name,raw in overlays.items()},
  'authorized_scope':'EXACT_ORIGINAL_FOUR_PLUS_ONE_ADMISSION_NO_OAUTH_GRANTS_OR_PAYMENTS',
  'database_policy':'READ_ONLY_DIGESTS_AND_PRIVATE_SQLITE_BACKUP_NO_DATABASE_RESTORE',
  'cost':'Explicit one-shot O(F+B) bounded file inventories/copy; SQL digests sort rows O(R log R). No app timer/scene scan/native call added.'}


def load_reviewed(path,expected):
 raw=Path(path).read_bytes();need(sha(raw)==expected,'explicit_reviewed_plan_sha_required')
 plan=json.loads(raw);need(raw==canonical(plan),'canonical_plan_required')
 need(plan.get('approved_steamids64')==IDS and plan.get('max_players')==4,'exact_five_account_scope_required')
 return plan


def arguments(argv=None):
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('action',choices=('audit','plan','prepare','activate','verify'))
 parser.add_argument('--source-revision')
 parser.add_argument('--plan',type=Path)
 parser.add_argument('--reviewed-plan-sha256')
 parser.add_argument('--apply',action='store_true')
 parser.add_argument('--report',type=Path,required=True)
 args=parser.parse_args(argv)
 if args.action in ('audit','plan'):
  need(args.source_revision and args.plan is None and args.reviewed_plan_sha256 is None and not args.apply,'read_only_arguments_invalid')
 else:
  need(args.plan is not None and re.fullmatch(r'[a-f0-9]{64}',args.reviewed_plan_sha256 or '') is not None and args.source_revision is None,'reviewed_plan_arguments_required')
  need(args.apply==(args.action=='activate'),'apply_only_required_for_activation')
 need(not args.report.exists(),'new_report_required');return args


def main(argv=None):
 args=arguments(argv)
 if args.action in ('audit','plan'):
  revision,operator,overlays=committed(args.source_revision);value=remote(operator,'audit')
  if args.action=='plan':value=make_plan(revision,operator,overlays,value)
 else:
  plan=load_reviewed(args.plan,args.reviewed_plan_sha256)
  revision,operator,overlays=committed(plan['source_revision'])
  need(sha(operator)==plan['operator_sha256'],'sealed_operator_changed')
  need({name:{'sha256':sha(raw),'bytes':len(raw)} for name,raw in overlays.items()}==plan['overlay'],'committed_overlay_changed')
  value=remote(operator,args.action,plan,{name:base64.b64encode(raw).decode() for name,raw in overlays.items()} if args.action=='prepare' else None)
 write_new(args.report,value)
 print(json.dumps({'ok':True,'status':value.get('status'),'report':str(args.report),'report_sha256':sha(args.report.read_bytes()),'live_changed':args.action=='activate','added_steamid64':ADDED},ensure_ascii=False))


if __name__=='__main__':
 try:main()
 except Exception as error:
  print(json.dumps({'ok':False,'status':'FIVE_ACCOUNT_SERVER_ACTION_REFUSED','error':str(error) if isinstance(error,RuntimeError) and re.fullmatch('[a-z0-9_]+',str(error)) else type(error).__name__}));raise SystemExit(1)
