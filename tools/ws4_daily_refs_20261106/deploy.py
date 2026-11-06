"""Draft exact one-file WS4 daily-reference update; default plan is local only.

Promotion to the declared tools path, committed source/operator bindings and a
fresh exact-parent audit are required before any remote action. No DB pooling,
configuration registration or SQL change belongs to this candidate.
"""
from pathlib import Path
import argparse
import ast
import base64
import hashlib
import importlib.util
import json
import re
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=next(p for p in HERE.parents if (p/'scripts/vscripts').is_dir() and (p/'tools').is_dir())
TOOL='tools/ws4_daily_refs_20261106/deploy.py'
PROBE='tools/ws4_daily_refs_20261106/probe.py'
PRIOR='tools/public_beta_wire_release_20261106/deploy.py'
PRIOR_SHA='46de619a0c3dcf83689f95efbe419e372c90aa59b5634071dc8b87f736fd6124'
PARENT='20261106-ws4-public-beta-wire-0a8308b20f0e'
MANIFEST='59a245a9eb5ea5da08e90c23d17aaf215e158d785780437f8d258ecbd5f429c7'
BUNDLE='f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42'
PARENT_WIRE='3fc65989fb6fd94fd3e57252d9e685903670318303e11ef42ffd5d27bd503e94'
PARENT_SOURCE='8b27c65977423c35aabf0c192ae31051699ed9e2'
RECIPE='daily-profile-refs-v2'
WIRE_SOURCE='server/archive_backend/http_profile_wire.py'
WIRE_TARGET='backend/archive_backend/http_profile_wire.py'
DECODER='scripts/vscripts/systems/http_profile_wire.lua'
PROVIDER='scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua'
VECTOR='tools/test_http_profile_wire.lua'
OUT=ROOT/'output/ws4_daily_refs_20261106_v02'


def sha(raw):return hashlib.sha256(raw).hexdigest()
def need(ok,code):
    if not ok:raise RuntimeError(code)
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(),str(path),'exec'),module.__dict__)
    return module
def git_blob(revision,path):
    need(bool(re.fullmatch('[a-f0-9]{40}',revision or '')),'immutable_revision_required')
    return subprocess.check_output(['git','--no-replace-objects','-C',str(ROOT),'show',revision+':'+path]).replace(b'\r\n',b'\n')


need(sha((ROOT/PRIOR).read_bytes().replace(b'\r\n',b'\n'))==PRIOR_SHA,'audited_parent_controller_changed')
prior=load('daily_refs_frozen_prior',ROOT/PRIOR)
replace_once=prior.replace_once
replace_function=prior.replace_function


def compose_remote():
    text=prior.REMOTE
    start=text.index("need(old.is_dir() and not old.is_symlink()")
    finish=text.index("control_root=base.parent/'deployment_records'",start)
    text=text[:start]+'''need(old.is_dir() and not old.is_symlink() and sha((old/'release_manifest.json').read_bytes())==expected_manifest,'ws4_parent_manifest_changed')
manifest=json.loads((old/'release_manifest.json').read_bytes())
need(json.loads((old/'addon/server/bundles/current.json').read_bytes())['hash']==PARENT_BUNDLE,'ws4_parent_bundle_changed')
need(sha(safe(old,WIRE_TARGET).read_bytes())==PARENT_WIRE_SHA,'actual_parent_wire_changed')
payloads={name:base64.b64decode(value,validate=True) for name,value in PAYLOADS.items()}
pins={name:sha(raw) for name,raw in payloads.items()}
need(set(payloads)=={WIRE_TARGET} and pins==PAYLOAD_PINS and pins==BINDING['payload_sha256'],'exact_one_wire_file_required')
need(RECIPE=='daily-profile-refs-v2' and BINDING['source_revision']==SOURCE,'daily_source_binding_changed')
need(BINDING['parent_release']==old.name and BINDING['parent_manifest_sha256']==expected_manifest and BINDING['bundle']==bundle_hash,'daily_parent_binding_changed')
need(sha(payloads[WIRE_TARGET])!=PARENT_WIRE_SHA,'daily_wire_change_required')
compile(payloads[WIRE_TARGET],WIRE_TARGET,'exec')
method_binding=BINDING
new=base/('20261106-ws4-daily-refs-'+sha(json.dumps(dict(payload_sha256=pins,recipe=RECIPE,source=SOURCE,operator=OPERATOR),sort_keys=True).encode())[:12])
'''+text[finish:]
    text=replace_once(text,"old=base/'"+prior.recipe.PARENT_RELEASE+"'","old=base/'"+PARENT+"'")
    text=replace_once(text,"expected_manifest='"+prior.recipe.PARENT_MANIFEST+"'","expected_manifest='"+MANIFEST+"'")
    # Both parent and candidate use the exact already-admitted f8 bundle.
    text=replace_function(text,'verify_config_admission','''def verify_config_admission():
 need(bundle_hash==PARENT_BUNDLE and set(pins)=={WIRE_TARGET},'daily_configuration_scope_changed')
 name='addon/server/bundles/'+bundle_hash+'/bundle.json'
 need(sha(safe(old,name).read_bytes())==bundle_hash and sha(safe(new,name).read_bytes())==bundle_hash,'daily_bundle_bytes_changed')
 return dict(configuration_unchanged=True,sql_changes=0)
''')
    text=replace_function(text,'candidate_manifest','''def candidate_manifest(original):
 return {**manifest,'release':new.name,'files':{**original,**pins},
  'daily_refs_v2_parent_manifest_sha256':expected_manifest_digest,
  'daily_refs_v2_source_revision':SOURCE,'daily_refs_v2_operator_revision':OPERATOR,
  'daily_refs_v2_changed_files':sorted(pins),'daily_refs_v2_recipe':RECIPE,
  'daily_refs_v2_source_sha256':SOURCE_PINS,'daily_refs_v2_parent_inventory_sha256':sha(canonical(original)),
  'daily_refs_v2_parent_unit_sha256':UNIT_SHA,'daily_refs_v2_method_binding':method_binding,
  'archive_bundle':'f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42','database_schema_or_config_changed':False,'startup_sync_policy_unchanged':True,
  'candidate_addon_root':str(new/'addon'),'addon_bytes_unchanged':True}
''')
    text=replace_function(text,'validate_probe','''def validate_probe(original):
 value=json.loads(safe(records,'probe.json').read_bytes())
 need(value.get('ok') is True and value.get('status')=='ACTUAL_WS4_PREPARED_DAILY_REFS_V2_PARITY_PASS','exact_candidate_probe_required')
 need(value.get('binding')==control_binding(original),'probe_binding_changed')
 need(value.get('rpc_calls')==0 and value.get('database_writes')==0 and value.get('real_player_data_used') is False,'probe_isolation_changed')
 need(value.get('legacy_unchanged') is True and value.get('real_lua_vectors',0)>=18 and value.get('malformed_vectors',0)>=4,'daily_wire_probe_missing')
 need(value.get('changed_files')==[WIRE_TARGET] and value.get('bundle_unchanged') is True,'daily_probe_scope_changed')
 return value
''')
    text=replace_once(text,"result=namespace['run'](old,new,PARENT_BUNDLE,bundle_hash,LUA_DECODER_SOURCE,LUA_VECTOR_RUNNER)","result=namespace['run'](old,new,bundle_hash,LUA_DECODER_SOURCE,LUA_VECTOR_RUNNER)")
    text=text.replace('PUBLIC_BETA_WIRE','DAILY_REFS_V2').replace('public_beta_wire_','daily_refs_v2_')
    # Existing parent uses normal startup config synchronization. Do not claim
    # zero writes for a service restart; no new SQL is run by this operator.
    text=text.replace('config_registration_expected=True','config_registration_expected=False,startup_sync_policy_unchanged=True')
    text=text.replace("result['config_retained_on_api_rollback']=True","result['config_unchanged_on_api_rollback']=True")
    text=text.replace('config_retained_on_api_rollback=True','config_unchanged_on_api_rollback=True')
    compile(text,'<daily-v2-remote>','exec')
    return text


REMOTE=compose_remote()
# prior import-time composition reads these operator files too; bind all of
# them to avoid inherited-helper drift, without invoking their old deployment.
OPERATOR_FILES=tuple(dict.fromkeys((TOOL,PROBE,PRIOR,VECTOR)+prior.OPERATOR_FILES))


def validate_wire_source(parent,current):
    need(sha(parent)==PARENT_WIRE,'known_parent_wire_required')
    def function(raw,name):
        nodes=[n for n in ast.parse(raw).body if isinstance(n,ast.FunctionDef)and n.name==name]
        need(len(nodes)==1,'wire_function_required')
        node=nodes[0];node.name='same_v1'
        return ast.dump(node,include_attributes=False)
    need(function(parent,'pack')==function(current,'_pack_v1'),'legacy_v1_logic_changed')
    compile(current,WIRE_SOURCE,'exec')
    need(b"CAPABILITY_V2 = 'archive_profile_refs_v2'"in current and b'DAILY_ROWS = 512'in current,'reviewed_v2_capability_required')


def source_inputs(source_revision,operator_revision):
    need(Path(__file__).resolve()==(ROOT/TOOL).resolve(),'promote_reviewed_operator_before_remote')
    operator_pins={}
    for name in OPERATOR_FILES:
        raw=git_blob(operator_revision,name)
        need(raw==(ROOT/name).read_bytes().replace(b'\r\n',b'\n'),'operator_worktree_drift')
        operator_pins[name]=sha(raw)
    need(operator_pins[PRIOR]==PRIOR_SHA,'audited_parent_controller_changed')
    raw=git_blob(source_revision,WIRE_SOURCE)
    validate_wire_source(git_blob(PARENT_SOURCE,WIRE_SOURCE),raw)
    decoder=git_blob(source_revision,DECODER)
    provider=git_blob(source_revision,PROVIDER)
    need(b'capabilities.archive_profile_refs_v2=true'in provider,'new_client_negotiation_required')
    source_pins={name:sha(git_blob(source_revision,name))for name in (WIRE_SOURCE,DECODER,PROVIDER)}
    pins={WIRE_TARGET:sha(raw)}
    binding=dict(recipe=RECIPE,source_revision=source_revision,parent_release=PARENT,parent_manifest_sha256=MANIFEST,
                 parent_wire_sha256=PARENT_WIRE,bundle=BUNDLE,payload_sha256=pins,
                 sql_changes=False,configuration_changes=False,only_one_runtime_file=True,
                 legacy_v1_logic_unchanged=True)
    return {WIRE_TARGET:raw},binding,source_pins,operator_pins,decoder


def plan():
    return dict(status='DAILY_REFS_V2_PLAN_NOT_EXECUTED',parent_release=PARENT,parent_manifest_sha256=MANIFEST,
                bundle_unchanged=BUNDLE,changed_runtime_files=[WIRE_TARGET],remote_actions=0,
                phases=['audit','prepare','probe','activate','verify'],rollback='exact retained parent unit/release with existing drain/watchdog',
                addon='independent full parent copy, exact bytes, own unit EnvironmentFile',
                requirements=['review and promote controller','immutable source/operator commits','fresh exact-parent audit','isolated Python/LinuxLua parity probe','root activation review'])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',nargs='?',default='plan',choices=('plan','audit','prepare','probe','activate','verify','rollback','recover'))
    parser.add_argument('--source-revision');parser.add_argument('--operator-revision')
    args=parser.parse_args()
    if args.mode=='plan':
        result=plan()
        if args.source_revision is not None or args.operator_revision is not None:
            values=source_inputs(args.source_revision,args.operator_revision)
            result.update(binding=values[1],source_sha256=values[2],operator_sha256=values[3])
        print(json.dumps(result,indent=2));return 0
    report=OUT/(args.mode+'.json');need(not report.exists(),'preserve_existing_local_receipt')
    payloads,binding,source_pins,operator_pins,decoder=source_inputs(args.source_revision,args.operator_revision)
    audit={}if args.mode=='audit'else json.loads((OUT/'audit.json').read_bytes())
    if audit:
        need(audit.get('ok')is True and audit.get('source_revision')==args.source_revision
             and audit.get('source_sha256')==source_pins and audit.get('payload_sha256')==binding['payload_sha256']
             and audit.get('operator_file_sha256')==operator_pins and audit.get('method_binding')==binding,'reviewed_audit_binding_changed')
    context=dict(MODE=args.mode,SOURCE=args.source_revision,OPERATOR=args.operator_revision,SOURCE_PINS=source_pins,
                 RECIPE=RECIPE,BINDING=binding,PARENT_BUNDLE=BUNDLE,WIRE_TARGET=WIRE_TARGET,PARENT_WIRE_SHA=PARENT_WIRE,
                 AUDITED_ADDON_ROOT='/opt/goufayu-ws4/releases/'+PARENT+'/addon',
                 PAYLOADS={name:base64.b64encode(raw).decode('ascii')for name,raw in payloads.items()},PAYLOAD_PINS=binding['payload_sha256'],
                 UNIT_SHA=audit.get('unit_sha256'),PARENT_INVENTORY_SHA=audit.get('parent_inventory_sha256'),
                 GATE_SOURCE=git_blob(args.operator_revision,prior.GATE_TOOL).decode('utf8'),
                 GATE_EXECUTABLE=audit.get('gate_environment',{}).get('executable'),
                 GATE_EXECUTABLE_SHA=audit.get('gate_environment',{}).get('executable_sha256'),
                 PROBE_SOURCE=git_blob(args.operator_revision,PROBE).decode('utf8'),LUA_DECODER_SOURCE=decoder.decode('utf8'),
                 LUA_VECTOR_RUNNER=git_blob(args.operator_revision,VECTOR).decode('utf8'))
    recovery='\n'.join(key+'='+repr(value)for key,value in {**context,'MODE':'recover'}.items())+'\n'+REMOTE
    context['WATCHDOG_RECOVERY_SOURCE']=recovery
    remote='\n'.join(key+'='+repr(value)for key,value in context.items())+'\n'+REMOTE
    need(sha(prior.TRANSPORT.read_bytes())==prior.TRANSPORT_SHA,'pinned_transport_changed')
    transport=load('daily_refs_pinned_transport',prior.TRANSPORT)
    result=transport.remote(remote,timeout=240)
    OUT.mkdir(parents=True,exist_ok=True);result['operator_file_sha256']=operator_pins
    with report.open('x',encoding='utf8')as stream:json.dump(result,stream,sort_keys=True,indent=2);stream.write('\n')
    print(json.dumps(result));return 0 if result.get('ok')is True else 2


if __name__=='__main__':raise SystemExit(main())
