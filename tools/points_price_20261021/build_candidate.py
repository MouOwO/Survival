"""Build a local points-price candidate; no transport or activation code."""
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

sys.dont_write_bytecode=True

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tmp/points_price_20261021/release_candidate'
PARENT='47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e'
PARENT_MANIFEST='39e845fd37a2966bbc57a616e661970a0736a0959ee9b00f2e1caf8ebdbae0fe'
PARENT_ROOT=ROOT/'tmp/benefit_revision_20261021/release_candidate'
SERVICE_PARENT=ROOT/'tmp/benefits_20261021/release_candidate/backend/archive_backend/service.py'
BEFORE=ROOT/'tmp/benefit_login_20261021/backend_before'
REPORT=ROOT/'validation/20261021/points_price_candidate.json'
BENEFITS='data/csv/存档系统/archive_benefit_rewards.csv'
LOTTERY='data/csv/抽奖系统/lottery_item_definitions.csv'
PRODUCTS='data/csv/商城兑换系统/commerce_products.csv'
LUA='systems/archive_benefit_rewards.lua'
LOTTERY_LUA='systems/lottery_http_settlement.lua'
COMMERCE_LUA='systems/commerce_settlement.lua'
PRICES={'n':200,'r':600,'sr':1500,'ssr':3000,'ur':8000}
PRICE_POLICY='fixed_quality_shop_points_20261021'
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


def service_overlay(baseline):
    deployed=normalized(SERVICE_PARENT).decode('utf-8-sig')
    expected=baseline['manifest']['files']['backend/archive_backend/service.py']
    need(sha(deployed.encode())==expected,'deployed_service_baseline_unverified')
    before=normalized(BEFORE/'server/archive_backend/service.py').decode('utf-8-sig')
    after=normalized(ROOT/'server/archive_backend/service.py').decode('utf-8-sig')
    need('_grant_login_benefits' not in after and '_grant_login_benefits' not in deployed,
         'automatic_login_python_helper_remains')
    def parse(source):
        tree=ast.parse(source)
        cls=next(node for node in tree.body if isinstance(node,ast.ClassDef) and node.name=='ArchiveService')
        method=next(node for node in cls.body if isinstance(node,ast.FunctionDef) and node.name=='finish_prepared')
        assignment=next(node for node in ast.walk(method) if isinstance(node,ast.Assign)
            and any(isinstance(target,ast.Name) and target.id=='legacy_error' for target in node.targets))
        return tree,method,assignment
    before_tree,_,before_assignment=parse(before)
    after_tree,after_method,after_assignment=parse(after)
    need('starjoy_exchange_disabled' in ast.dump(after_assignment),'missing_server_exchange_disable_guard')
    guards=[node for node in ast.walk(after_method) if isinstance(node,ast.If)
            and any(isinstance(part,ast.Constant) and part.value=='commerce_price_changed'
                    for statement in node.body for part in ast.walk(statement))]
    need(len(guards)==1,'missing_or_duplicate_server_price_guard')
    price_guard=guards[0]
    loop=next(node for node in after_method.body if isinstance(node,ast.For))
    product_index=next(index for index,node in enumerate(loop.body) if isinstance(node,ast.Assign)
        and any(isinstance(target,ast.Name) and target.id=='product' for target in node.targets))
    check_index=next(index for index,node in enumerate(loop.body) if isinstance(node,ast.If)
        and isinstance(node.test,ast.Name) and node.test.id=='legacy_error')
    recorded_nodes=loop.body[product_index+1:check_index]
    need(len(recorded_nodes)==2 and isinstance(recorded_nodes[0],ast.Assign)
         and isinstance(recorded_nodes[1],ast.If)
         and any(isinstance(target,ast.Name) and target.id=='recorded_price' for target in recorded_nodes[0].targets)
         and 'price_bundle' in ast.dump(recorded_nodes[1]),'unexpected_recorded_price_guard')
    del loop.body[product_index+1:check_index]
    # Prove the workspace contribution consists of exactly these two guards.
    class Restore(ast.NodeTransformer):
        def visit_Assign(self,node):
            return copy.deepcopy(before_assignment) if node is after_assignment else self.generic_visit(node)
        def visit_If(self,node):
            if node is price_guard:
                return [self.visit(child) for child in node.orelse]
            return self.generic_visit(node)
    restored=Restore().visit(after_tree)
    need(ast.dump(restored)==ast.dump(before_tree),'unrelated_workspace_service_change')
    lines=after.splitlines(True)
    assignment=''.join(lines[after_assignment.lineno-1:after_assignment.end_lineno])
    guard=''.join(lines[price_guard.lineno-1:price_guard.body[-1].end_lineno])
    recorded=''.join(lines[recorded_nodes[0].lineno-1:recorded_nodes[-1].end_lineno])
    need(guard.lstrip().startswith('elif '),'unexpected_price_guard_syntax')
    _,_,original_assignment=parse(deployed)
    parent_lines=deployed.splitlines(True)
    scoped=''.join(parent_lines[:original_assignment.lineno-1])+assignment+''.join(parent_lines[original_assignment.end_lineno:])
    recorded_anchor="            if legacy_error:\n"
    need(scoped.count(recorded_anchor)==1,'parent_legacy_check_anchor_changed')
    scoped=scoped.replace(recorded_anchor,recorded+recorded_anchor)
    anchor="            elif (command['kind'] == 'commerce_purchase' and reducer is not self\n"
    need(scoped.count(anchor)==1,'parent_commerce_guard_anchor_changed')
    scoped=scoped.replace(anchor,guard+anchor)
    need(scoped!=deployed,'missing_scoped_server_changes')
    parse(scoped)
    difference=''.join(difflib.unified_diff(deployed.splitlines(True),scoped.splitlines(True),
        fromfile='parent47/backend/archive_backend/service.py',tofile='candidate/backend/archive_backend/service.py'))
    write(OUT/'overlays/backend/archive_backend/service.py',scoped.encode())
    write(OUT/'service_overlay.diff',difference.encode())
    return dict(path='overlays/backend/archive_backend/service.py',parent_sha256=expected,
                overlay_sha256=sha(scoped.encode()),workspace_before_sha256=sha(before.encode()),
                workspace_current_sha256=sha(after.encode()),methods=['finish_prepared'],
                guards=['starjoy_exchange_disabled','commerce_price_changed'],
                automatic_login_helper_absent=True,preexisting_workspace_changes_excluded=True,
                diff_sha256=sha(difference.encode()))


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
               pass_item_ids=['special_lottery_ticket'],pass_counts=['1'],enabled=True,monthly_only=True,auto_claim=False)
    value['rows'].insert(0,login)
    return value


def points_catalog(parent,read_csv):
    products=read_csv(ROOT/PRODUCTS)
    expected=copy.deepcopy(parent['configs']['commerce_products'])
    definitions={row['item_id']:row for row in parent['configs']['lottery_item_definitions']['rows']}
    resources=json.loads((ROOT/'data/ui/item_resources.json').read_bytes())['items']
    aliases={identity:entry['id'] for entry in resources for identity in [entry['id']]+entry.get('aliases',[])}
    qualities={};counts={quality:0 for quality in PRICES}
    for row in expected['rows']:
        if row.get('currency')!='shop_points':continue
        definition=next((definitions[value] for value in (aliases.get(row['sku']),
            aliases.get(row.get('source_id')),aliases.get(row.get('ownership_id'))) if value in definitions),None)
        quality=definition['quality'] if definition else {'video_p147':'ur','video_p151':'ur'}.get(row['sku'])
        need(quality in PRICES,'unreviewed_shop_points_quality:'+row['sku'])
        row.update(price=PRICES[quality],point_quality=quality,price_policy=PRICE_POLICY)
        qualities[row['sku']]=quality;counts[quality]+=1
    need(len(qualities)==86 and counts=={'n':10,'r':4,'sr':5,'ssr':35,'ur':32},'shop_points_scope_changed')
    need(products==expected,'unapproved_commerce_products_difference')
    from archive_backend.commerce_catalog import build_catalog
    compiled=build_catalog(ROOT)['products']
    generated={row['sku']:row for row in compiled}
    catalog=copy.deepcopy(parent['configs']['commerce_catalog'])
    need(set(generated)=={row['sku'] for row in catalog['rows']},'compiler_product_identity_changed')
    excluded=[]
    price_fields={'price','point_quality','price_policy','original_price'}
    for row in catalog['rows']:
        current=generated[row['sku']]
        if row['sku'] in qualities:
            quality=qualities[row['sku']]
            need(current.get('price')==PRICES[quality] and current.get('point_quality')==quality
                 and current.get('price_policy')==PRICE_POLICY,'compiler_fixed_points_price_mismatch:'+row['sku'])
            need('original_price' not in current,'compiler_fixed_price_fake_discount:'+row['sku'])
            for field in price_fields:
                if field in current:row[field]=copy.deepcopy(current[field])
                else:row.pop(field,None)
        ignored=[field for field in sorted(row.keys()|current.keys()) if row.get(field)!=current.get(field)]
        if ignored:excluded.append(dict(sku=row['sku'],fields=ignored))
    return products,catalog,dict(target_products=86,quality_counts=counts,prices=PRICES,price_policy=PRICE_POLICY,
        missing_qualities_confirmed_ur=['video_p147','video_p151'],
        compiler_non_price_differences_excluded=excluded,compiled_projection_fields=sorted(price_fields))


def commerce_snapshot_source(parent):
    anchor="                original_price=p.original_price,required_vip_level=p.grants.required_vip_level}\n"
    addition="            products[#products].price_policy=p.price_policy\n            products[#products].point_quality=p.point_quality\n"
    before=normalized(ROOT/'tmp/points_price_20261021/backend_before/scripts/vscripts'/COMMERCE_LUA).decode('utf-8-sig')
    current=normalized(ROOT/'scripts/vscripts'/COMMERCE_LUA).decode('utf-8-sig')
    source=parent['sources'][COMMERCE_LUA]
    need(source.count(anchor)==1 and before.count(anchor)==1,'commerce_snapshot_metadata_anchor_changed')
    need(current==before.replace(anchor,anchor+addition),'unapproved_local_commerce_settlement_difference')
    return source.replace(anchor,anchor+addition)


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
    def snapshot(profile,pass_):
        script='''package.path="./?.lua"
local decoder=require("core/json_decoder")
local encoder=require("core/json_encoder")
local input=decoder.decode(io.read("*a"))
for name,config in pairs(input.configs) do
    local module={rows=config.rows,by_id={}}
    for _,row in ipairs(config.rows) do module.by_id[row[config.key]]=row end
    package.loaded["config/generated/"..name]=module
end
require("systems/archive_calendar").set_clock(function() return input.timestamp end)
local result=require("systems/archive_benefit_rewards").snapshot(input.profile,input.has_pass,input.timestamp)
io.write(encoder.encode({snapshot=result,profile=input.profile}))
'''
        payload=dict(configs=candidate['configs'],profile=profile,has_pass=pass_,timestamp=now)
        result=subprocess.run([lua,'-e',script],cwd=OUT/'bundles'/sha(canonical(candidate)),
            input=canonical(payload),capture_output=True,timeout=15)
        need(result.returncode==0,'local_lua_snapshot_failed')
        value=json.loads(result.stdout)
        def maps(v):
            if v==[]:return {}
            if isinstance(v,dict):return {key:maps(item) for key,item in v.items()}
            if isinstance(v,list):return [maps(item) for item in v]
            return v
        need(maps(value['profile'])==profile,'snapshot_modified_profile')
        return next(row for row in value['snapshot']['daily_time']['rows'] if row['id']=='daily_time_0')
    cases=[]
    initial=fixture();shown=snapshot(initial,True)
    need(shown['can_claim']==1 and shown['auto_claim']==0 and shown['monthly_only']==1
         and shown['status']=='claimable','manual_login_button_not_claimable')
    need(snapshot(initial,False)['can_claim']==0,'free_login_button_not_locked')
    cases.extend(['monthly_zero_minutes_manual_button_claimable','non_monthly_manual_button_locked',
                  'benefit_snapshot_preserves_inventory_and_claims'])
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
    spec=importlib.util.spec_from_file_location('archive_backend.local_points_candidate_service',
        OUT/'overlays/backend/archive_backend/service.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    calls=[];reads=[]
    now=1792962000;day=str((now+10800)//86400)
    defaults={r['field_id']:r['default_value'] for r in parent['configs']['player_gameplay_stats']['rows']}
    profile=dict(account_id='0',revision=1,entitlements=dict(archive_pass=dict(active=True,expires_at=now+86400)),
        save=dict(content_inventory={},gameplay_stats=defaults,
        archive=dict(benefits=dict(version=1,days={day:dict(seconds=9000,wins=0,claimed={})},weeks={}))))
    class MemoryRPC:
        def rpc(self,name,payload):
            if name in {'archive_online_pending','archive_pending'}:
                reads.append(name);return []
            if name=='get_fishing_profile':
                reads.append(name);return copy.deepcopy(profile)
            need(name=='archive_commit_lottery','unexpected_memory_rpc')
            calls.append(copy.deepcopy(payload));return dict(ok=True,done=True,response=payload['p_response'])
    app=SimpleNamespace(rpc_client=MemoryRPC(),account_id_pepper='synthetic-local-test-only',
        profile=lambda payload:copy.deepcopy(profile),_database_account_id=lambda account:account,
        _public_response=lambda value,database_account,account:copy.deepcopy(value))
    service=module.ArchiveService(app,Bundle(OUT/'bundles'/sha(canonical(candidate))),lua)
    prior=copy.deepcopy(profile);loaded=service.profile({'account_id':'0'})
    need(loaded==prior and profile==prior and not calls
         and reads==['archive_online_pending','archive_pending','get_fishing_profile'],
         'profile_read_automatically_granted_login_reward')
    explicit=service.settle(loaded,dict(id='local:explicit:manual',kind='benefit_claim',track='daily_time',
        tier_id='daily_time_0',event_at=now),True)
    need(explicit.get('ok') and explicit['content_inventory']=={'special_lottery_ticket':1},
         'explicit_service_manual_claim_failed')
    need(loaded==prior and profile==prior and not calls,'explicit_local_reducer_mutated_input_profile')
    done=dict(ok=True,done=True,response=dict(rewards=[dict(id='special_lottery_ticket',count=2)]))
    before=copy.deepcopy(done);need(service.finish_prepared('0','local:completed',done) is done and done==before and not calls,
        'completed_receipt_changed')
    pending=dict(ok=True,done=False,config_hash=PARENT,has_pass=True,event_at=now,profile=profile,
        command=dict(id='local:historical:pending',kind='benefit_claim',track='daily_time',tier_id='daily_time_150',today=int(day)))
    result=service.finish_prepared('0','local:historical:pending',pending)
    need(result.get('ok') and len(calls)==1 and calls[0]['p_inventory']['special_lottery_ticket']==2,
        'pending_receipt_did_not_use_parent_bundle')
    return dict(profile_read_does_not_grant=True,explicit_manual_claim_grants_one_gold=True,
                completed_receipt_returned_unchanged=True,parent_pending_dispatched_to_original_bundle=True,
                database_connections=0,real_account_writes=0)


def verify_points(candidate,disabled,lua):
    from archive_backend.bundle import Bundle
    spec=importlib.util.spec_from_file_location('archive_backend.local_points_policy_service',
        OUT/'overlays/backend/archive_backend/service.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    calls=[]
    class MemoryRPC:
        def rpc(self,name,payload):
            need(name=='archive_commit_lottery','unexpected_points_memory_rpc')
            calls.append(copy.deepcopy(payload))
            return dict(ok=payload.get('p_error') is None,done=True,terminal=True,
                        error=payload.get('p_error'),response=payload['p_response'])
    app=SimpleNamespace(rpc_client=MemoryRPC(),account_id_pepper='synthetic-local-test-only')
    service=module.ArchiveService(app,Bundle(OUT/'bundles'/sha(canonical(candidate))),lua)
    safe=module.ArchiveService(app,Bundle(OUT/'bundles'/sha(canonical(disabled))),lua)
    defaults={r['field_id']:r['default_value'] for r in candidate['configs']['player_gameplay_stats']['rows']}
    def fixture(balance=10000):
        stats=copy.deepcopy(defaults);stats.update(starjoy_points=500,starjoy_points_earned=1000)
        return dict(account_id='0',revision=1,save=dict(content_inventory={},gameplay_stats=stats,
            archive=dict(commerce=dict(balances=dict(shop_points=balance)))))
    rows=candidate['configs']['commerce_catalog']['rows'];cases=[]
    actual_catalog=service.settle(fixture(),dict(id='local:commerce:snapshot',kind='commerce_catalog'),False)
    expected_visible={row['sku']:row for row in rows if row.get('currency')=='shop_points' and row.get('enabled')}
    visible=[row for row in actual_catalog.get('products',[]) if row.get('currency')=='shop_points']
    need(actual_catalog.get('ok') and {row['sku'] for row in visible}==set(expected_visible),
         'actual_commerce_worker_snapshot_points_products_missing')
    for row in visible:
        expected=expected_visible[row['sku']]
        need(row.get('price_policy')==PRICE_POLICY and row.get('point_quality')==expected['point_quality']
             and row.get('price')==PRICES[row['point_quality']] and 'original_price' not in row,
             'actual_commerce_worker_snapshot_fixed_price_metadata_missing:'+row['sku'])
    cases.append('actual_commerce_worker_snapshot_carries_fixed_policy_quality_without_fake_original_price')
    javascript='''const fs=require("node:fs");
const model=require(process.argv[1]);
const catalog=JSON.parse(fs.readFileSync(0,"utf8"));
const points=catalog.products.filter(item=>item.currency==="shop_points");
model.SetPresentation({groups:{promotions:points.map(item=>item.sku)}});
for(const item of points){
    if(model.ReferencePrice(item)!==null)throw new Error("fixed_snapshot_shows_fake_reference_price:"+item.sku);
}
process.stdout.write(JSON.stringify({ok:true,checked:points.length}));'''
    ui=subprocess.run(['node','-e',javascript,str(ROOT/'panorama/src/scripts/custom_game/black_lion_market_model.js')],
        input=canonical(actual_catalog),capture_output=True,timeout=15)
    need(ui.returncode==0 and json.loads(ui.stdout).get('checked')==len(visible),
         'actual_worker_snapshot_ui_reference_price_fallback_not_disabled')
    cases.append('actual_worker_snapshot_prevents_ui_one_point_five_fake_discount')
    for quality,price in PRICES.items():
        product=next(r for r in rows if r.get('point_quality')==quality and r.get('enabled'))
        command=dict(id='local:points:'+quality,kind='commerce_purchase',sku=product['sku'])
        profile=fixture();before=copy.deepcopy(profile)
        result=service.settle(profile,command,False)
        need(result.get('ok') and result['response']['price']==price
             and result['archive']['commerce']['balances']['shop_points']==10000-price,
             'fixed_quality_purchase_price_failed:'+quality)
        need(result['gameplay_stats']['starjoy_points']>=500 and profile==before,
             'purchase_debited_starjoy_or_mutated_input:'+quality)
        poor=fixture(price-1);before_poor=copy.deepcopy(poor)
        denied=service.settle(poor,command,False)
        need(denied.get('ok') is False and poor==before_poor,'insufficient_points_not_safe:'+quality)
        need(safe.settle(profile,command,False).get('ok') is False,'safe_rollback_points_purchase_open:'+quality)
        cases.append(quality+'_fixed_price_wallet_debit_insufficient_and_safe_disabled')
    profile=fixture();before=copy.deepcopy(profile)
    exchange=dict(id='local:exchange:disabled',kind='lottery_exchange',pool_id='map',item_id='lottery_seed_of_life')
    result=service.settle(profile,exchange,False)
    need(result.get('ok') is False and result.get('terminal') is True
         and result.get('error')=='starjoy_exchange_disabled' and profile==before,'current_exchange_not_early_rejected')
    cases.append('new_exchange_rejected_before_any_debit')
    snapshot=service.settle(profile,dict(id='local:lottery:read',kind='lottery_snapshot'),False)
    need(snapshot.get('ok') and all(row['starjoy_points']==1000 for row in snapshot['snapshots']),
         'snapshot_does_not_show_cumulative_starjoy')
    need(all(item['exchange_enabled'] is False and item['exchange_points']==0
         for row in snapshot['snapshots'] for item in row['items']),'snapshot_exchange_not_disabled')
    cases.append('snapshot_cumulative_starjoy_and_no_exchange_prices')
    product=next(r for r in rows if r.get('point_quality')=='n' and r.get('enabled'))
    for command,error in ((exchange,'starjoy_exchange_disabled'),
            (dict(id='local:old:points',kind='commerce_purchase',sku=product['sku']),'commerce_price_changed')):
        count=len(calls)
        pending=dict(ok=True,done=False,config_hash=PARENT,has_pass=False,event_at=1792962000,
                     profile=profile,command=command)
        result=service.finish_prepared('0',command['id'],pending)
        need(result.get('terminal') is True and result.get('error')==error and len(calls)==count+1,
             'old_pending_policy_not_terminal:'+error)
        need(calls[-1]['p_deltas']=={} and calls[-1]['p_inventory']=={} and calls[-1]['p_error']==error
             and profile==before,'old_pending_policy_debited_account:'+error)
        cases.append('old_pending_'+error+'_commits_only_terminal_error')
        if command['kind']=='commerce_purchase':
            policy=service.bundle.compatible_config_hashes[PARENT]
            prior_upgrades=policy['upgrade_commands']
            policy['upgrade_commands']=frozenset({'commerce_purchase'})
            try:
                count=len(calls)
                upgraded=service.finish_prepared('0',command['id'],pending)
                need(upgraded.get('error')=='commerce_price_changed' and upgraded.get('terminal') is True
                     and len(calls)==count+1 and calls[-1]['p_deltas']=={} and calls[-1]['p_inventory']=={},
                     'upgraded_old_confirmation_silently_charged_new_price')
                cases.append('upgraded_old_purchase_still_requires_new_confirmation')
            finally:
                policy['upgrade_commands']=prior_upgrades
        completed=dict(ok=True,done=True,response=dict(cost=188,kind=command['kind']))
        count=len(calls);prior=copy.deepcopy(completed)
        need(service.finish_prepared('0',command['id'],completed) is completed and completed==prior
             and len(calls)==count,'completed_receipt_was_changed:'+error)
        cases.append('completed_'+command['kind']+'_receipt_retained')
    return dict(passed=True,cases=cases,database_connections=0,real_account_writes=0)


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
    for row in expected['rows']:row.update(exchange_points=0,exchange_enabled=False)
    need(lottery==expected,'unapproved_lottery_definition_difference');candidate['configs']['lottery_item_definitions']=lottery
    products,catalog,pricing=points_catalog(parent,read_csv)
    candidate['configs']['commerce_products']=products;candidate['configs']['commerce_catalog']=catalog
    for name in (LUA,LOTTERY_LUA):
        source=normalized(ROOT/'scripts/vscripts'/name).decode('utf-8-sig')
        need(source!=parent['sources'][name],'required_lua_change_missing:'+name);candidate['sources'][name]=source
    candidate['sources'][COMMERCE_LUA]=commerce_snapshot_source(parent)
    for name in (BENEFITS,LOTTERY,PRODUCTS):candidate['csv_hashes'][name]=sha(normalized(ROOT/name))
    need(all('benefit_claim' not in policy['commands'] for policy in parent['compatible_config_hashes'].values()),'parent_benefit_alias_exists')
    commands=sorted({kind for policy in parent['compatible_config_hashes'].values() for kind in policy['commands']}-{'benefit_claim'})
    candidate['compatible_config_hashes'][PARENT]=dict(commands=commands,upgrade_commands=[])
    digest,directory=materialize(candidate);materialize(parent,raw_parent)
    disabled=copy.deepcopy(candidate)
    for row in disabled['configs']['archive_benefit_rewards']['rows']:row['enabled']=False
    for name in ('commerce_products','commerce_catalog'):
        for row in disabled['configs'][name]['rows']:
            if row.get('currency')=='shop_points':row['enabled']=False
    disabled['compatible_config_hashes'][digest]=dict(commands=commands,upgrade_commands=[])
    rollback,_=materialize(disabled)
    need(candidate['configs']['archive_stackable_items']==parent['configs']['archive_stackable_items']==disabled['configs']['archive_stackable_items'],
         'stackable_rules_changed')
    overlay=service_overlay(baseline)
    lua_result=verify_lua(candidate,parent,lua);receipts=verify_receipts(candidate,parent,lua)
    point_tests=verify_points(candidate,disabled,lua)
    need(all(sha((ROOT/name).read_bytes())==value for name,value in protected.items()),'active_client_declaration_changed_during_build')
    plan=dict(status='LOCAL_ONLY_PENDING_USER_AUTHORIZATION',candidate_bundle=digest,parent_bundle=PARENT,
        rollback_bundle=rollback,parent_evidence='tmp/benefit_revision_20261021/release_candidate/baseline.json',
        changed_config_tables=['archive_benefit_rewards','lottery_item_definitions','commerce_products','commerce_catalog'],
        changed_lua_sources=[LUA,LOTTERY_LUA,COMMERCE_LUA],service_overlay=overlay,pricing=pricing,
        commerce_snapshot_source_parent_only_two_metadata_assignments=True,
        superseded_local_candidate_bundle='234f0a873a4f4ff0868f1abcbe1690ba1f5e8d8611bbf51d673f7d611bd50a0c',
        previous_nine_reward_revisions_retained=True,new_monthly_login_tier='daily_time_0',
        login_reward_requires_explicit_click=True,login_reward_auto_claim=False,
        new_optional_flags=['monthly_only','auto_claim'],compatibility_excludes=['benefit_claim'],upgrade_commands=[],
        parent_bundle_retained=True,rollback_disables_all_benefits=True,rollback_disables_points_products=86,
        starjoy_exchange_disabled=True,completed_receipts_retained=True,
        old_changed_price_purchase_requires_new_confirmation=True,stackable_rules_preserved=True,
        payment_service_changed=False,payment_products_preserved=True,
        database_migrations=[],credentials_included=False,remote_actions_performed=0,
        active_hash_or_seed_written=False,lua_validation=lua_result,receipt_validation=receipts,points_validation=point_tests)
    write(OUT/'candidate_plan.json',canonical(plan))
    write(REPORT,json.dumps(plan,ensure_ascii=False,indent=2).encode()+b'\n')
    print(json.dumps(dict(ok=True,status=plan['status'],bundle=digest,rollback_bundle=rollback,
        lua_cases=len(lua_result['cases']),profile_and_receipt_cases=4,points_cases=len(point_tests['cases']),
        remote_actions=0),ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua',default='C:/Program Files/lua/bin/lua5.1.exe')
    build(parser.parse_args().lua)
