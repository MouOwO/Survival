"""Build and verify a strictly local candidate; no transport or activation code."""
from __future__ import annotations

import argparse
import ast
import copy
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tmp/benefit_login_20261021/release_candidate'
PARENT='47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e'
PARENT_MANIFEST='39e845fd37a2966bbc57a616e661970a0736a0959ee9b00f2e1caf8ebdbae0fe'
PARENT_ROOT=ROOT/'tmp/benefit_revision_20261021/release_candidate'
SERVICE_PARENT=ROOT/'tmp/benefits_20261021/release_candidate/backend/archive_backend/service.py'
BEFORE=ROOT/'tmp/benefit_login_20261021/backend_before'
REPORT=ROOT/'validation/20261021/benefit_login_candidate.json'
BENEFITS='data/csv/存档系统/archive_benefit_rewards.csv'
LOTTERY='data/csv/抽奖系统/lottery_item_definitions.csv'
LUA='systems/archive_benefit_rewards.lua'
ITEM='lottery_reincarnation_immortal_stele'
NOTE='（苟发育没说上限 但是咱默认个5000次吧）'
PROTECTED=('scripts/vscripts/config/generated/archive_http_bundle.lua','server/bundles/current.json',
           'panorama/src/scripts/custom_game/lottery_catalog_seed.js',
           'scripts/vscripts/config/generated/lottery_catalog_manifest.lua','data/ui/lottery_catalog.json')


def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def sha(value): return hashlib.sha256(value).hexdigest()
def normalized(path): return path.read_bytes().replace(b'\r\n',b'\n')
def need(value,code):
    if not value: raise ValueError(code)


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(value)


def class_methods(source):
    tree=ast.parse(source)
    cls=next(node for node in tree.body if isinstance(node,ast.ClassDef) and node.name=='ArchiveService')
    return tree,cls,{node.name:node for node in cls.body if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef))}


def method_source(source,node):
    first=min([node.lineno]+[decorator.lineno for decorator in node.decorator_list])
    return ''.join(source.splitlines(True)[first-1:node.end_lineno]).rstrip()+'\n'


def service_overlay(baseline):
    deployed=normalized(SERVICE_PARENT).decode('utf-8-sig')
    expected=baseline['manifest']['files']['backend/archive_backend/service.py']
    need(sha(deployed.encode())==expected,'deployed_service_baseline_unverified')
    before=normalized(BEFORE/'server/archive_backend/service.py').decode('utf-8-sig')
    after=normalized(ROOT/'server/archive_backend/service.py').decode('utf-8-sig')
    old_tree,old_cls,old_methods=class_methods(before)
    new_tree,new_cls,new_methods=class_methods(after)
    changed={name for name in old_methods.keys()|new_methods.keys()
             if name not in old_methods or name not in new_methods
             or ast.dump(old_methods[name])!=ast.dump(new_methods[name])}
    need(changed=={'profile','_grant_login_benefits'},'unrelated_local_service_method_changed')
    # All non-method declarations/imports must also remain the local before-state.
    for node in (old_cls,new_cls):
        node.body=[part for part in node.body if not isinstance(part,(ast.FunctionDef,ast.AsyncFunctionDef))]
    need(ast.dump(old_tree)==ast.dump(new_tree),'local_service_declarations_changed')
    _,_,parent_methods=class_methods(deployed)
    need('_grant_login_benefits' not in parent_methods,'parent_already_contains_login_grant')
    profile=parent_methods['profile'];lines=deployed.splitlines(True)
    replacement=method_source(after,new_methods['profile'])+'\n'+method_source(after,new_methods['_grant_login_benefits'])+'\n'
    scoped=''.join(lines[:profile.lineno-1])+replacement+''.join(lines[profile.end_lineno:])
    _,_,scoped_methods=class_methods(scoped)
    need(all(ast.dump(node)==ast.dump(scoped_methods[name]) for name,node in parent_methods.items()
             if name!='profile'),'overlay_changes_non_login_method')
    need(set(scoped_methods)==set(parent_methods)|{'_grant_login_benefits'},'unexpected_overlay_method')
    difference=''.join(difflib.unified_diff(deployed.splitlines(True),scoped.splitlines(True),
        fromfile='parent47/backend/archive_backend/service.py',tofile='candidate/backend/archive_backend/service.py'))
    write(OUT/'overlays/backend/archive_backend/service.py',scoped.encode())
    write(OUT/'service_overlay.diff',difference.encode())
    return dict(path='overlays/backend/archive_backend/service.py',parent_sha256=expected,
                overlay_sha256=sha(scoped.encode()),workspace_before_sha256=sha(before.encode()),
                workspace_current_sha256=sha(after.encode()),methods=sorted(changed),
                preexisting_workspace_changes_excluded=True,diff_sha256=sha(difference.encode()))


def expected_benefits(parent):
    value=copy.deepcopy(parent['configs']['archive_benefit_rewards'])
    rows={row['reward_id']:row for row in value['rows']}
    edits={'daily_time_150':{'pass_counts':['2','2','1','2']},
           'daily_win_3':{'pass_item_ids':['lottery_ticket','special_lottery_ticket'],'pass_counts':['1','1']},
           'daily_win_4':{'pass_item_ids':None,'pass_counts':None}}
    for minutes,count in ((120,2),(240,3),(360,4),(480,5),(600,5),(720,5)):
        edits['weekly_time_'+str(minutes)]={'pass_item_ids':['lottery_ticket'],'pass_counts':[str(count)]}
    need(len(rows)==19 and len(edits)==9,'parent_reward_catalog_changed')
    for identity,fields in edits.items():
        for field,after in fields.items():
            if after is None: rows[identity].pop(field,None)
            else: rows[identity][field]=after
    login=dict(reward_id='daily_time_0',track='daily_time',period='day',metric='minutes',required=0,
               pass_item_ids=['special_lottery_ticket'],pass_counts=['1'],enabled=True,monthly_only=True,auto_claim=True)
    value['rows'].insert(0,login)
    return value


def materialize(data,raw=None):
    raw=canonical(data) if raw is None else raw
    digest=sha(raw);directory=OUT/'bundles'/digest
    write(directory/'bundle.json',raw)
    for name,value in data['sources'].items():
        need(not Path(name).is_absolute() and '..' not in Path(name).parts,'invalid_packaged_source')
        write(directory/name,value.encode())
    return digest,directory


def verify_lua(candidate,parent,lua):
    now=1792962000;day=str((now+10800)//86400)
    defaults={row['field_id']:row['default_value'] for row in candidate['configs']['player_gameplay_stats']['rows']}
    def fixture(seconds=0):
        return dict(account_id='0',revision=1,save=dict(content_inventory={},gameplay_stats=copy.deepcopy(defaults),
            archive=dict(benefits=dict(version=1,days={day:dict(seconds=seconds,wins=0,claimed={})},weeks={}))))
    def run(data,profile,tier,token,pass_=True,at=now):
        directory=OUT/'bundles'/sha(canonical(data))
        command=dict(id=token,kind='benefit_claim',track='daily_time',tier_id=tier,event_at=at)
        payload=dict(configs=data['configs'],profile=profile,command=command,has_pass=pass_,server_time=at,seed=1)
        result=subprocess.run([lua,'worker.lua'],cwd=directory,input=canonical(payload),capture_output=True,timeout=15)
        need(result.returncode==0,'local_lua_worker_failed')
        return json.loads(result.stdout)
    def apply(profile,result):
        if result.get('ok') and not result.get('duplicate'):
            for key in ('archive','gameplay_stats','content_inventory'):
                if key in result:profile['save'][key]=copy.deepcopy(result[key])
    cases=[]
    profile=fixture();free=run(candidate,profile,'daily_time_0','local:free:login',False)
    need(free.get('ok') is False,'free_login_tier_not_rejected');cases.append('non_monthly_login_rejected')
    first=run(candidate,profile,'daily_time_0','local:monthly:login');need(first.get('ok'),'monthly_zero_login_failed')
    apply(profile,first);need(profile['save']['content_inventory']['special_lottery_ticket']==1,'login_reward_amount_wrong')
    cases.append('monthly_zero_minutes_grants_one_gold')
    need(run(candidate,profile,'daily_time_0','local:monthly:login').get('duplicate') is True,'same_receipt_not_deduplicated')
    need(run(candidate,profile,'daily_time_0','local:new:login').get('ok') is False,'daily_login_claim_reopened')
    cases.extend(['same_local_receipt_once','new_receipt_same_day_rejected'])
    next_day=run(candidate,profile,'daily_time_0','local:nextday:login',at=now+86400)
    need(next_day.get('ok') and next_day['content_inventory']['special_lottery_ticket']==2,'next_five_am_reset_failed')
    cases.append('next_beijing_five_am_claim_is_independent')
    ordinary=run(candidate,fixture(9000),'daily_time_30','local:normal:30')
    need(ordinary.get('ok') and ordinary['content_inventory']=={'lottery_ticket':2},'ordinary_thirty_minute_tier_changed')
    cases.append('thirty_minutes_retains_two_ordinary_for_monthly')
    final=run(candidate,fixture(9000),'daily_time_150','local:normal:150')
    need(final.get('ok') and final['content_inventory']==dict(lottery_ticket=4,welfare_zongzi=4,
        lottery_ember_of_legacy=3,special_lottery_ticket=1),'revised_150_minute_tier_changed')
    cases.append('150_minutes_keeps_four_normal_four_zongzi_three_ember_one_gold')
    old=run(parent,fixture(9000),'daily_time_150','local:old:pending')
    need(old.get('ok') and old['content_inventory']['special_lottery_ticket']==2,'parent_pending_reward_changed')
    need(run(parent,fixture(),'daily_time_0','local:old:unsupported').get('ok') is False,'parent_bundle_was_mutated')
    cases.extend(['parent_pending_keeps_old_two_gold','parent_has_no_new_login_tier'])
    return dict(passed=True,cases=cases,network_calls=0,real_account_writes=0)


def verify_receipts(candidate,parent,lua):
    from archive_backend.bundle import Bundle
    path=OUT/'overlays/backend/archive_backend/service.py'
    spec=importlib.util.spec_from_file_location('archive_backend.local_login_candidate_service',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    calls=[]
    class MemoryRPC:
        def rpc(self,name,payload):
            need(name=='archive_commit_lottery','unexpected_memory_rpc')
            calls.append(copy.deepcopy(payload));return dict(ok=True,done=True,response=payload['p_response'])
    app=SimpleNamespace(rpc_client=MemoryRPC(),account_id_pepper='synthetic-local-test-only')
    service=module.ArchiveService(app,Bundle(OUT/'bundles'/sha(canonical(candidate))),lua)
    done=dict(ok=True,done=True,response=dict(rewards=[dict(id='special_lottery_ticket',count=2)]))
    before=copy.deepcopy(done);need(service.finish_prepared('0','local:completed',done) is done and done==before and not calls,
        'completed_receipt_changed')
    now=1792962000;day=str((now+10800)//86400)
    defaults={r['field_id']:r['default_value'] for r in parent['configs']['player_gameplay_stats']['rows']}
    profile=dict(account_id='0',revision=1,save=dict(content_inventory={},gameplay_stats=defaults,
        archive=dict(benefits=dict(version=1,days={day:dict(seconds=9000,wins=0,claimed={})},weeks={}))))
    pending=dict(ok=True,done=False,config_hash=PARENT,has_pass=True,event_at=now,profile=profile,
        command=dict(id='local:historical:pending',kind='benefit_claim',track='daily_time',tier_id='daily_time_150',today=int(day)))
    result=service.finish_prepared('0','local:historical:pending',pending)
    need(result.get('ok') and len(calls)==1 and calls[0]['p_inventory']['special_lottery_ticket']==2,
        'pending_receipt_did_not_use_parent_bundle')
    return dict(completed_receipt_returned_unchanged=True,parent_pending_dispatched_to_original_bundle=True,
                database_connections=0,real_account_writes=0)


def build(lua):
    sys.path.insert(0,str(ROOT/'server'))
    from archive_backend.bundle import read_csv
    protected={name:sha((ROOT/name).read_bytes()) for name in PROTECTED}
    raw_parent=(PARENT_ROOT/'parent_bundle.json').read_bytes();need(sha(raw_parent)==PARENT,'parent_bundle_digest_changed')
    parent=json.loads(raw_parent);baseline=json.loads((PARENT_ROOT/'baseline.json').read_bytes())
    need(baseline['archive_bundle']==PARENT and baseline['archive_manifest_sha256']==PARENT_MANIFEST,'parent_evidence_changed')
    need(not {'content_catalog','tooltip_definition','tooltip_definitions'}&set(parent['configs']),'unexpected_client_only_table')
    candidate=copy.deepcopy(parent)
    benefits=read_csv(ROOT/BENEFITS);need(benefits==expected_benefits(parent),'unapproved_benefit_table_difference')
    candidate['configs']['archive_benefit_rewards']=benefits
    lottery=read_csv(ROOT/LOTTERY);expected=copy.deepcopy(parent['configs']['lottery_item_definitions'])
    row=next(r for r in expected['rows'] if r['item_id']==ITEM)
    need(row['description'].count(NOTE)==1,'stele_note_anchor_changed');row['description']=row['description'].replace(NOTE,'')
    need(lottery==expected,'unapproved_lottery_definition_difference');candidate['configs']['lottery_item_definitions']=lottery
    source=normalized(ROOT/'scripts/vscripts'/LUA).decode('utf-8-sig')
    need(source!=parent['sources'][LUA],'automatic_login_lua_change_missing');candidate['sources'][LUA]=source
    for name in (BENEFITS,LOTTERY):candidate['csv_hashes'][name]=sha(normalized(ROOT/name))
    need(all('benefit_claim' not in policy['commands'] for policy in parent['compatible_config_hashes'].values()),'parent_benefit_alias_exists')
    commands=sorted({kind for policy in parent['compatible_config_hashes'].values() for kind in policy['commands']}-{'benefit_claim'})
    candidate['compatible_config_hashes'][PARENT]=dict(commands=commands,upgrade_commands=[])
    digest,directory=materialize(candidate);materialize(parent,raw_parent)
    disabled=copy.deepcopy(candidate)
    for row in disabled['configs']['archive_benefit_rewards']['rows']:row['enabled']=False
    disabled['compatible_config_hashes'][digest]=dict(commands=commands,upgrade_commands=[])
    rollback,_=materialize(disabled)
    need(candidate['configs']['archive_stackable_items']==parent['configs']['archive_stackable_items']==disabled['configs']['archive_stackable_items'],
         'stackable_rules_changed')
    overlay=service_overlay(baseline)
    lua_result=verify_lua(candidate,parent,lua);receipts=verify_receipts(candidate,parent,lua)
    need(all(sha((ROOT/name).read_bytes())==value for name,value in protected.items()),'active_client_declaration_changed_during_build')
    plan=dict(status='LOCAL_ONLY_PENDING_USER_AUTHORIZATION',candidate_bundle=digest,parent_bundle=PARENT,
        rollback_bundle=rollback,parent_evidence='tmp/benefit_revision_20261021/release_candidate/baseline.json',
        changed_config_tables=['archive_benefit_rewards','lottery_item_definitions'],changed_lua_sources=[LUA],
        service_overlay=overlay,previous_nine_reward_revisions_retained=True,new_monthly_login_tier='daily_time_0',
        new_optional_flags=['monthly_only','auto_claim'],compatibility_excludes=['benefit_claim'],upgrade_commands=[],
        parent_bundle_retained=True,rollback_disables_all_benefits=True,stackable_rules_preserved=True,
        database_migrations=[],credentials_included=False,remote_actions_performed=0,
        active_hash_or_seed_written=False,lua_validation=lua_result,receipt_validation=receipts)
    write(OUT/'candidate_plan.json',canonical(plan))
    write(REPORT,json.dumps(plan,ensure_ascii=False,indent=2).encode()+b'\n')
    print(json.dumps(dict(ok=True,status=plan['status'],bundle=digest,rollback_bundle=rollback,
        lua_cases=len(lua_result['cases']),receipt_cases=2,remote_actions=0),ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua',default='C:/Program Files/lua/bin/lua5.1.exe')
    build(parser.parse_args().lua)
