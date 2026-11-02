"""Explicit WS4-only four-code operator. Default is a static zero-network plan.

Every input/phase is pinned; production apply is a separate explicit action.
No real code generation, live-player redemption, service stop/restart or SQL
migration is implemented. Backup plaintext stays on the server/in local RAM.
"""
from pathlib import Path, PurePosixPath
import argparse
import base64
import hashlib
import importlib.util
import json
import re
import secrets
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'output/redemption_ticket_codes_20261102'


def need(value, reason):
    if not value: raise ValueError(reason)


def sha(raw): return hashlib.sha256(raw).hexdigest()
def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('ascii')


def module(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def new_json(path, value):
    path=Path(path).resolve();need(path.parent==OUT.resolve(), 'new_output_under_operator_root_required')
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as stream:stream.write(canonical(value)+b'\n')
    return path


def read_json(path, digest=None):
    raw=Path(path).read_bytes();need(len(raw)<=2*1024*1024,'bounded_json_required')
    if digest is not None:need(re.fullmatch('[a-f0-9]{64}',digest or '')and sha(raw)==digest,'explicit_input_hash_mismatch')
    def pairs(values):
        result={}
        for key,value in values:
            need(key not in result,'duplicate_json_key');result[key]=value
        return result
    return json.loads(raw,object_pairs_hook=pairs),raw


def remote(source, timeout=120):
    transport=module('ticket_ws4_existing_hostkey_transport',ROOT/'tools/ws4_catalog_sync_20261031/driver.py')
    return transport.remote(source,timeout=timeout)


def operator_source():return (HERE/'ws4_operator.py').read_text(encoding='utf-8')


def inventory(output):
    value=remote(operator_source()+'\nprint(json.dumps(inventory(),sort_keys=True))\n',45)
    need(value.get('status')=='READ_ONLY_WS4_TICKET_INVENTORY'and value.get('server_modified')is False,'inventory_failed')
    path=new_json(output,value)
    return {'status':value['status'],'receipt':str(path),'sha256':sha(path.read_bytes()),
            'definitions':value['definitions'],'server_modified':False}


def create_plan(inventory_path, inventory_sha, registry_path, registry_sha, output):
    observed,raw_inventory=read_json(inventory_path,inventory_sha)
    registry,raw_registry=read_json(registry_path,registry_sha)
    need(observed['status']=='READ_ONLY_WS4_TICKET_INVENTORY'and observed['database']=='goufayu_ws4'
         and observed['connection_port']==15432 and observed['definitions']['count']==128
         and observed.get('bundle_hash')=='d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488',
         'exact_ws4_inventory_required')
    definitions=module('ticket_reviewed_definition_compiler',HERE/'definitions.py')
    hashes={str(quantity):row['code_hash']for quantity,row in zip((10,50,100,200),registry.get('codes',[]))}
    need(canonical(registry)==canonical(definitions.compile_definitions(hashes)),'registry_differs_from_reviewed_four_tiers')
    op=module('ticket_ws4_plan_validation',HERE/'ws4_operator.py');op.validate_registry(registry)
    run='run_'+secrets.token_hex(6)
    files={'operator.py':(HERE/'ws4_operator.py').read_bytes(),'clone_checks.py':(HERE/'clone_checks.py').read_bytes(),
           'registry.json':raw_registry}
    # The target is Linux even when this planner is running on Windows. Never
    # serialize str(WindowsPath('/root/...')) into a remote stage identifier.
    remote_stage=PurePosixPath(op.STAGE_ROOT.as_posix())/run
    need(remote_stage.is_absolute()and '\\'not in str(remote_stage),'posix_remote_stage_required')
    value={'schema':1,'database':'goufayu_ws4','port':15432,'stage':str(remote_stage),
           'inventory':observed,'inventory_sha256':sha(raw_inventory),'registry_path':str(Path(registry_path).resolve()),
           'registry_sha256':sha(raw_registry),'files':{k:sha(v)for k,v in files.items()},
           'local_operator_inputs':{name:sha((HERE/name).read_bytes())for name in
                ('ws4_operator.py','ws4_register.py','clone_checks.py','definitions.py','tiers.json')},
           'scope':'INSERT_EXACT_FOUR_NEW_ROWS_ONLY','production_plaintext_codes_generated':False,
           'existing_definitions_update_allowed':False,'restart_allowed':False}
    path=new_json(output,value)
    return {'status':'SEALED_FOUR_ROW_INSERT_PLAN_NOT_APPLIED','plan':str(path),'sha256':sha(path.read_bytes()),
            'quantities':[10,50,100,200],'existing_definitions':128,'server_modified':False}


def checked_plan(path, digest):
    plan,_=read_json(path,digest)
    need(Path(path).resolve().parent==OUT.resolve(),'operator_plan_location_required')
    need(set(plan['local_operator_inputs'])=={'ws4_operator.py','ws4_register.py','clone_checks.py','definitions.py','tiers.json'},
         'complete_operator_input_set_required')
    for name,pin in plan['local_operator_inputs'].items():
        need(name in {'ws4_operator.py','ws4_register.py','clone_checks.py','definitions.py','tiers.json'}
             and sha((HERE/name).read_bytes())==pin,'operator_source_changed_replan_required')
    _,registry=read_json(plan['registry_path'],plan['registry_sha256'])
    need(sha(registry)==plan['files']['registry.json'],'sealed_registry_changed')
    return plan


def invoke(action, plan_path, digest):
    plan=checked_plan(plan_path,digest)
    if action=='upload':
        files={name:(HERE/file).read_bytes()for name,file in [('operator.py','ws4_operator.py'),('clone_checks.py','clone_checks.py')]}
        files['registry.json']=Path(plan['registry_path']).read_bytes()
        need(all(sha(raw)==plan['files'][name]for name,raw in files.items()),'upload_source_changed')
        code=operator_source()+'\nprint(json.dumps(prepare('+repr(plan)+','+repr(files)+'),sort_keys=True))\n'
    else:
        code='PLAN='+repr(plan)+'\nACTION='+repr(action)+'\n'+'''
from pathlib import Path
import hashlib,json
stage=Path(PLAN['stage']);raw=(stage/'operator.py').read_bytes()
assert hashlib.sha256(raw).hexdigest()==PLAN['files']['operator.py']
scope={};exec(compile(raw,'sealed_ticket_operator','exec'),scope)
print(json.dumps(scope['dispatch'](ACTION,PLAN),sort_keys=True))
'''
    # One request only. Unknown commit/SSH failures never automatically retry.
    intent=OUT/(PurePosixPath(plan['stage']).name+'_'+action+'_local_intent.json')
    if action!='verify':new_json(intent,{'action':action,'plan_sha256':digest,'automatic_retry':False})
    result=remote(code,timeout=600 if action=='clone'else 180)
    receipt=OUT/(PurePosixPath(plan['stage']).name+'_'+action+'_'+secrets.token_hex(4)+'.json')
    new_json(receipt,result)
    return {'status':result.get('status','PHASE_COMPLETED'),'receipt':str(receipt),'sha256':sha(receipt.read_bytes()),
            'automatic_retry':False,'player_redemption_performed':False}


def protect_backup(plan_path,digest):
    plan=checked_plan(plan_path,digest)
    code=operator_source()+'\nPLAN='+repr(plan)+'''
import base64
stage=checked_stage(PLAN);saved=load(stage,'backup');raw=Path(saved['path']).read_bytes()
need(sha(raw)==saved['sha256'],'backup_changed')
print(json.dumps({'data':base64.b64encode(raw).decode(),'sha256':saved['sha256']}))
'''
    value=remote(code,90);raw=base64.b64decode(value['data'],validate=True);need(sha(raw)==value['sha256'],'backup_transport_mismatch')
    crypto=module('ticket_existing_dpapi',ROOT/'tools/onboarding_release_20261025/deploy.py')
    encrypted=crypto.dpapi(raw);need(sha(crypto.dpapi(encrypted,decrypt=True))==value['sha256'],'dpapi_roundtrip_failed')
    folder=OUT/'private/backups';folder.mkdir(parents=True,exist_ok=True);target=folder/(PurePosixPath(plan['stage']).name+'.dump.dpapi')
    with target.open('xb')as stream:stream.write(encrypted)
    ack={'encrypted_roundtrip_verified':True,'sha256':value['sha256'],'ciphertext_sha256':sha(encrypted),'ciphertext_bytes':len(encrypted)}
    result=remote(operator_source()+'\nprint(json.dumps(acknowledge_backup('+repr(plan)+','+repr(ack)+'),sort_keys=True))\n')
    return {'status':'SERVER_FULL_LOCAL_DPAPI_BACKUP_VERIFIED','ciphertext_path':str(target),**ack}


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',nargs='?',default='plan',choices=['inventory','plan','upload','clone','backup','protect-backup','apply','verify'])
    for name in ('inventory','inventory-sha','registry','registry-sha','output','plan','plan-sha'):
        parser.add_argument('--'+name)
    parser.add_argument('--execute',action='store_true');parser.add_argument('--apply',action='store_true')
    args=parser.parse_args(argv)
    if args.action=='plan'and not any(v for k,v in vars(args).items()if k!='action'):
        result={'status':'STATIC_WS4_FOUR_TICKET_CODE_PLAN','quantities':[10,50,100,200],
                'server_connections':0,'files_written':0,'plaintext_codes_generated':False,'production_writes':0}
    elif args.action=='inventory':
        need(args.output,'new_inventory_output_required');result=inventory(args.output)
    elif args.action=='plan':
        need(all((args.inventory,args.inventory_sha,args.registry,args.registry_sha,args.output)),'explicit_plan_inputs_required')
        result=create_plan(args.inventory,args.inventory_sha,args.registry,args.registry_sha,args.output)
    else:
        need(args.plan and args.plan_sha,'explicit_sealed_plan_required')
        if args.action=='apply':need(args.apply,'explicit_production_apply_required')
        elif args.action!='verify':need(args.execute,'explicit_phase_execution_required')
        result=protect_backup(args.plan,args.plan_sha)if args.action=='protect-backup'else invoke(args.action,args.plan,args.plan_sha)
    print(json.dumps(result,sort_keys=True,ensure_ascii=True));return 0


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        text=str(error)
        print(json.dumps({'status':'REFUSED_PRESERVE_PENDING_AND_BACKUPS','error':text if re.fullmatch('[a-z0-9_]{1,100}',text)else type(error).__name__}))
        raise SystemExit(1)
