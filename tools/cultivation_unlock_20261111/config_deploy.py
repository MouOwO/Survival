"""Prepare, roll back a synthetic PG probe, then register one exact config.

No player row or service is modified by this database admission operator.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json

ROOT=Path(__file__).resolve().parents[2]
TOOL='tools/cultivation_unlock_20261111/config_deploy.py'
RECIPE_FILE='tools/cultivation_unlock_20261111/config_recipe.py'
SOURCE_VALIDATOR='tools/cultivation_unlock_20261111/deploy.py'
PRIOR='tools/public_beta_config_20261106/deploy.py'
PRIOR_SHA='b9e6dde535d2945443b0378a6556ccef89a86b7ac6dbcbc56d755ed215e5fb9f'
OUT=Path('D:/Survival_本地工具/runs/20261111_cultivation_unlock01/db_config')


def sha(raw):return hashlib.sha256(raw).hexdigest()
def need(ok,code):
    if not ok:raise RuntimeError(code)


def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(),str(path),'exec'),module.__dict__)
    return module


need(sha((ROOT/PRIOR).read_bytes().replace(b'\r\n',b'\n'))==PRIOR_SHA,'audited_db_operator_changed')
previous=load('ur50_frozen_db_operator',ROOT/PRIOR)
recipe=load('ur50_exact_db_recipe',ROOT/RECIPE_FILE)
source=load('ur50_candidate_validator',ROOT/SOURCE_VALIDATOR)
OPERATOR_FILES=tuple(dict.fromkeys((TOOL,RECIPE_FILE,PRIOR,recipe.PRIOR,recipe.previous.PRIOR)+source.OPERATOR_FILES))


def compose_remote():
    text=previous.REMOTE
    for before,after in (
        ('20261106-public-beta-config-[a-f0-9]{12}','20261111-ur1-fifty-config-[a-f0-9]{12}'),
        ('public-beta-exact-config-v1',recipe.RECIPE),
        ('f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42',recipe.NEW_BUNDLE),
        ('PUBLIC_BETA_CONFIG_PREPARED_NOT_REGISTERED','GOLD_UR1_FIFTY_CONFIG_PREPARED_NOT_REGISTERED'),
        ('PUBLIC_BETA_EXACT_CONFIG_PG_PROBE_PASS','GOLD_UR1_FIFTY_CONFIG_PG_PROBE_PASS'),
        ('PUBLIC_BETA_EXACT_CONFIG_REGISTERED','GOLD_UR1_FIFTY_CONFIG_REGISTERED'),
        ('PUBLIC_BETA_CONFIG_ACTIVE_VERIFIED','GOLD_UR1_FIFTY_CONFIG_ACTIVE_VERIFIED')):
        need(before in text,'audited_db_anchor_changed');text=text.replace(before,after)
    compile(text,'<ur50-pinned-db-operator>','exec')
    return text


REMOTE=compose_remote()


def inputs(source_revision,operator_revision):
    pins={}
    for name in OPERATOR_FILES:
        raw=source.git_blob(operator_revision,name)
        need(raw==(ROOT/name).read_bytes().replace(b'\r\n',b'\n'),'operator_worktree_drift')
        pins[name]=sha(raw)
    _,_,source_pins,_=source.source_inputs(source_revision,operator_revision)
    values,binding=recipe.artifacts((source.ARTIFACT/'bundle.json').read_bytes(),source_revision,source_pins,source.RECEIPT_SHA)
    binding['operator_revision']=operator_revision;binding['operator_files']=pins
    binding['record_name']='20261111-ur1-fifty-config-'+sha(recipe.base.canonical(binding))[:12]
    return values,binding,pins


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',nargs='?',default='plan',choices=('plan','prepare','probe','activate','verify'))
    parser.add_argument('--source-revision');parser.add_argument('--operator-revision');args=parser.parse_args()
    if args.mode=='plan':
        print(json.dumps(dict(status='GOLD_UR1_FIFTY_DB_PLAN_NOT_EXECUTED',bundle=recipe.NEW_BUNDLE,
                             candidate_function_sha256=sha(recipe.derive_function(recipe.parent_function())),remote_actions=0)))
        return 0
    report=OUT/(args.mode+'.json');need(not report.exists(),'preserve_existing_db_receipt')
    values,binding,pins=inputs(args.source_revision,args.operator_revision)
    if args.mode!='prepare':need(json.loads((OUT/'prepare.json').read_bytes())['binding']==binding,'prepared_db_binding_changed')
    if args.mode in ('activate','verify'):
        probe=json.loads((OUT/'probe.json').read_bytes())
        need(probe.get('binding')==binding and probe.get('status')=='GOLD_UR1_FIFTY_CONFIG_PG_PROBE_PASS'
             and probe.get('transaction_rollback_verified') is True,'exact_pg_probe_required')
    context=dict(MODE=args.mode,BINDING=binding,ARTIFACTS={name:base64.b64encode(raw).decode('ascii') for name,raw in values.items()},
                 PARENT_GUARD=recipe.base.guard_sql(recipe.PARENT_FUNCTION,False))
    remote='\n'.join(key+'='+repr(value) for key,value in context.items())+'\n'+REMOTE
    need(sha(previous.TRANSPORT.read_bytes())==previous.TRANSPORT_SHA,'audited_transport_changed')
    transport=load('ur50_pinned_db_transport',previous.TRANSPORT)
    result=transport.remote(remote,timeout=180);result['operator_file_sha256']=pins
    OUT.mkdir(parents=True,exist_ok=True)
    with report.open('x',encoding='utf8') as stream:json.dump(result,stream,sort_keys=True,indent=2);stream.write('\n')
    print(json.dumps(result));return 0 if result.get('ok') is True else 2


if __name__=='__main__':raise SystemExit(main())
