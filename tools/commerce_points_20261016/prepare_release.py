"""Prepare one scope-locked, offline-only archive candidate; never activate it."""
from __future__ import annotations
import argparse, ast, copy, difflib, gzip, hashlib, importlib.util, io, json, os, shutil, subprocess, sys, tarfile, tempfile
from pathlib import Path
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/commerce_points_20261016/release'
BASE='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
SOURCES=('systems/commerce_settlement.lua','systems/lottery_http_settlement.lua')
CSV_PATHS={'commerce_products':'商城兑换系统/commerce_products.csv','lottery_item_definitions':'抽奖系统/lottery_item_definitions.csv'}
CONFIGS=set(CSV_PATHS)|{'commerce_catalog'}
CHECKPOINT=ROOT/'design_refs/commerce_logic_audit_20261016/release/archive-starjoy-d113ebb8ff88/manifest.json'
LOCAL_BASELINE=ROOT/'design_refs/commerce_logic_audit_20261016/baseline/server/archive_backend/service.py'
SERVICE=ROOT/'server/archive_backend/service.py'
POINTER=ROOT/'server/bundles/current.json'
GAME=ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua'
ANCHOR="        database_id=self.app._database_account_id(account)\n        self.app._ensure_gameplay_stats(database_id)\n"
INSERT="""        if command['kind'] == 'starjoy_reconcile':
            # Cash grants can cross several tiers during one match. Derive a
            # stable receipt from saved progress, never a client-supplied score.
            # profile() also resolves earlier pending operations before reading.
            trusted = self.profile({'account_id': account})
            stats = trusted.get('save', {}).get('gameplay_stats', {})
            score = max(0, *(int(stats.get(key) or 0) for key in
                            ('starjoy_points_earned', 'starjoy_points')))
            command['id'] += ':earned:' + str(score)
"""
FOLLOW='        fingerprint=hashlib.sha256(json.dumps(command,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()\n'
OLD=ANCHOR+FOLLOW
NEW=ANCHOR+INSERT+FOLLOW

def sha(raw): return hashlib.sha256(raw).hexdigest()
def canonical(value): return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def put(path,raw):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(raw)
def write_json(path,data): put(path,canonical(data)+b'\n')
def norm(raw): return raw.decode('utf-8-sig').replace('\r\n','\n')

EXPECTED_SOURCE_HASHES={
 'scripts/vscripts/systems/commerce_settlement.lua':'ceb0d938846d0edae89d39f5def5df2abb3b9c4e471636605d9b119aba373bef',
 'scripts/vscripts/systems/lottery_http_settlement.lua':'be22bd50afd0aa86a43040ea295256ef9932b945c606546568b0d1f6b3722532',
 'server/archive_backend/service.py':'ceb6201ac4454fc7f0482535fcf45b59937a8f53339e3ad5929833a3d4ad01f0',
 'design_refs/commerce_logic_audit_20261016/baseline/server/archive_backend/service.py':'58aca31fdf98bcd796cefb84594091cddd22363300055cd2a930cba9536a806e'}
GOLD_OLD='            if version == self.bundle.hash or command["kind"] != "challenge":\n                result=reducer.settle(profile,command,prepared["has_pass"])\n'
GOLD_NEW="""            product = self.bundle.tables.get('commerce_catalog', {}).get(command.get('sku'), {})
            if command['kind'] == 'commerce_purchase' and product.get('currency') == 'shop_gold':
                # A currency pause applies to uncommitted older-client intents too.
                # Completed receipts already returned above and remain immutable.
                result = {'ok': False, 'error': 'shop_gold_not_open'}
            elif version == self.bundle.hash or command["kind"] != "challenge":
                result=reducer.settle(profile,command,prepared["has_pass"])
"""

def load_module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def field_diff(old,new,key):
    a={r[key]:r for r in old['rows']};b={r[key]:r for r in new['rows']}
    assert a.keys()==b.keys(),'row_identity_changed:'+key
    return [{'id':identity,'field':field,'old':a[identity].get(field),'new':b[identity].get(field)}
        for identity in sorted(a) for field in sorted(a[identity].keys()|b[identity].keys())
        if a[identity].get(field)!=b[identity].get(field)]

def compile_configs(base):
    from archive_backend.bundle import read_csv
    from payment_backend.csv_catalog import SOURCES as REFERENCE_SOURCES
    from payment_backend.commerce_bundles import compile_commerce,MEMBER_TABLE,EMPTY_MEMBERS
    from payment_backend.ucoin_catalog import COMMERCE_TABLES
    csvroot=ROOT/'data/csv'
    result={name:read_csv(csvroot/path) for name,path in CSV_PATHS.items()}
    refs={name:(csvroot/name).read_text(encoding='utf-8-sig') for name in REFERENCE_SOURCES}
    deployed=base['configs']['player_gameplay_stats'];formal=read_csv(csvroot/'玩家档案系统/player_gameplay_stats.csv')
    drift=field_diff(deployed,formal,'field_id')
    # Match the deployed overlay's reference note; exclude unrelated workspace documentation drift.
    assert drift==[{'id':'lumberjack_attack_growth','field':'notes','old':'伐木工每次攻击后的攻击力成长量。','new':'默认无固定攻击成长；实际获得的每次攻击成长仅增加攻击者自身攻击力。'}],drift
    statsref='玩家档案系统/player_gameplay_stats.csv';assert refs[statsref].count(drift[0]['new'])==1
    refs[statsref]=refs[statsref].replace(drift[0]['new'],drift[0]['old'],1)
    tables={name:((csvroot/'商城兑换系统'/(name+'.csv')).read_text(encoding='utf-8-sig')
        if (csvroot/'商城兑换系统'/(name+'.csv')).is_file() else EMPTY_MEMBERS if name==MEMBER_TABLE else '') for name in COMMERCE_TABLES}
    commerce=compile_commerce(tables,refs,(csvroot/'商城支付系统/payment_categories.csv').read_text(encoding='utf-8-sig'))
    for product in commerce['products']:
        assert (ROOT/'panorama/src/images'/product['icon']).is_file(),'commerce_icon_missing:'+product['sku']
    result['commerce_catalog']={'key':'sku','rows':commerce['products']}
    expected=[{'id':sku,'field':'enabled','old':True,'new':False} for sku in ('video_p037','video_p038')]
    for name in ('commerce_products','commerce_catalog'):
        assert field_diff(base['configs'][name],result[name],'sku')==expected,name+':unexpected_changes'
    rates=[{'id':'lottery_recovery_spirit','field':'duplicate_points','old':5,'new':25},
           {'id':'lottery_supreme_fishing_rod','field':'duplicate_points','old':1000,'new':400}]
    assert field_diff(base['configs']['lottery_item_definitions'],result['lottery_item_definitions'],'item_id')==rates
    quality_rates={'n':5,'r':25,'sr':100,'ssr':400,'ur':1000}
    for row in result['lottery_item_definitions']['rows']:assert row['duplicate_points']==quality_rates[row['quality']],row['item_id']
    return result,{'official_compiler':'payment_backend.commerce_bundles.compile_commerce',
        'formal_csv_parser':'archive_backend.bundle.read_csv','non_task_reference_note_preserved':drift,
        'reference_override_sha256':sha(refs[statsref].encode()),'quality_duplicate_points':quality_rates}

def snapshot_inputs(basefile):
    from payment_backend.csv_catalog import SOURCES as REFERENCE_SOURCES
    from payment_backend.ucoin_catalog import COMMERCE_TABLES
    files={basefile,POINTER,GAME,SERVICE,LOCAL_BASELINE,CHECKPOINT,ROOT/'server/archive_backend/config_compatibility.py',
           ROOT/'server/archive_backend/bundle.py',ROOT/'server/archive_backend/commerce_catalog.py'}
    files|={ROOT/'scripts/vscripts'/name for name in SOURCES}
    files|={ROOT/'data/csv'/name for name in REFERENCE_SOURCES}
    files|={ROOT/'data/csv/商城兑换系统'/(name+'.csv') for name in COMMERCE_TABLES}
    files.add(ROOT/'data/csv/商城支付系统/payment_categories.csv')
    files|=set((ROOT/'server/payment_backend').glob('*.py'))
    return {p.relative_to(ROOT).as_posix():sha(p.read_bytes()) for p in sorted(files)}

SNAPSHOT_OLD='        projected=self.settle(profile,{"id":"lottery_snapshot","kind":"lottery_snapshot"},False)\n'
SNAPSHOT_NEW='        reducer=self\n        if requested_hash != self.bundle.hash:\n            # Advertise the same currency/rates that this client\'s recorded\n            # draw reducer uses, until the game joins the new bundle version.\n            reducer=ArchiveService(self.app,Bundle(self.bundle.directory.parent/requested_hash),self.lua)\n        projected=reducer.settle(profile,{"id":"lottery_snapshot","kind":"lottery_snapshot"},False)\n'
PATCH_TOOL='"""Atomic context-guarded three-hunk offline patch. Separate output only; no deploy."""\nfrom pathlib import Path\nimport argparse,hashlib,json\n\ndef transform(raw,spec,reverse=False):\n    if b\'\\r\' in raw.replace(b\'\\r\\n\',b\'\'):raise ValueError(\'unsupported_line_endings\')\n    newline=b\'\\r\\n\' if b\'\\r\\n\' in raw else b\'\\n\'\n    if newline==b\'\\r\\n\' and b\'\\n\' in raw.replace(b\'\\r\\n\',b\'\'):raise ValueError(\'mixed_line_endings\')\n    result=raw\n    for hunk in reversed(spec[\'hunks\']) if reverse else spec[\'hunks\']:\n        old=hunk[\'new_exact\'] if reverse else hunk[\'old_exact\']\n        new=hunk[\'old_exact\'] if reverse else hunk[\'new_exact\']\n        original=old.encode().replace(b\'\\n\',newline);replacement=new.encode().replace(b\'\\n\',newline)\n        if result.count(original)!=1:raise ValueError(\'patch_context_not_exactly_once:\'+hunk[\'id\'])\n        result=result.replace(original,replacement,1)\n    if result==raw:raise ValueError(\'patch_changed_nothing\')\n    return result\n\nif __name__==\'__main__\':\n    ap=argparse.ArgumentParser(description=\'Read and review actual online source first. No network, in-place write or activation.\')\n    ap.add_argument(\'--source\',required=True,type=Path);ap.add_argument(\'--output\',type=Path);ap.add_argument(\'--reverse\',action=\'store_true\');a=ap.parse_args()\n    spec=json.loads(Path(__file__).with_name(\'archive_service_patch.json\').read_text(\'utf-8\'))\n    raw=a.source.read_bytes();result=transform(raw,spec,a.reverse)\n    if a.output:\n        if a.output.resolve()==a.source.resolve():raise ValueError(\'in_place_write_refused\')\n        if a.output.exists():raise ValueError(\'output_already_exists\')\n        with a.output.open(\'xb\') as handle:handle.write(result)\n    print(json.dumps({\'status\':\'PASS\',\'reverse\':a.reverse,\'source_sha256\':hashlib.sha256(raw).hexdigest(),\n        \'output_sha256\':hashlib.sha256(result).hexdigest(),\'written\':str(a.output) if a.output else None,\'production_deployed\':False}))\n'


def smoke(candidate,old,lua):
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    from archive_backend.config_compatibility import accepts,upgrades
    from tests.test_archive_backend import Database,App
    new_bundle=Bundle(candidate);old_bundle=Bundle(old)
    historical=load_module(LOCAL_BASELINE,'archive_backend._commerce_points_baseline_service').ArchiveService
    catalog=new_bundle.tables['commerce_catalog']
    db=Database(new_bundle);app=App(db);service=ArchiveService(app,new_bundle,lua)
    def profile(account='100',all_owned=False):
        p=db.profile(app._database_account_id(account));p['save']['content_inventory']={}
        p['save']['archive']['commerce']={'balances':{'u_coin':10**9,'shop_points':100,'shop_gold':10**9},'sentinel':'preserve'}
        p['save']['gameplay_stats'].update(starjoy_points=0,starjoy_points_earned=1000,starjoy_reward_level=5)
        if all_owned:
            p['save']['content_inventory']={r['item_id']:r['max_owned'] for r in new_bundle.configs['lottery_item_definitions']['rows']}
            p['save']['content_inventory'].update(lottery_ticket=1000,special_lottery_ticket=1000)
            p['save']['gameplay_stats'].update(starjoy_points=0,starjoy_points_earned=0,starjoy_reward_level=0)
        return p
    def payload(kind='commerce_purchase',digest=None,account='100',token='points-audit-purchase',**kw):
        c={'id':'points-audit-match:'+token,'kind':kind,**kw}
        if kind=='commerce_purchase':c.update(sku=kw.get('sku','video_p004'),request_id=token)
        if kind.startswith('lottery_'):c.update(pool_id=kw.get('pool_id','map'),request_id=token)
        return {'account_id':account,'config_hash':digest or new_bundle.hash,'command':c}
    def send(*args,**kw):return service.command(payload(*args,**kw))
    calls=[];real_run=subprocess.run
    def run(*args,**kwargs):
        calls.append({'hash':Path(kwargs['cwd']).name,'command':json.loads(kwargs['input'])['command']['kind']})
        return real_run(*args,**kwargs)
    checks=[]
    for kind in new_bundle.compatible_config_hashes[BASE]['commands']:
        assert accepts(new_bundle,BASE,kind) and not upgrades(new_bundle,BASE,kind)
    checks.append({'name':'old_dee_22_commands_accepted_financial_rules_not_upgraded','status':'PASS'})
    with patch('archive_backend.service.subprocess.run',side_effect=run):
        p=profile();full=service.settle(p,{'id':'catalog-before','kind':'commerce_catalog'},False)
        old_full=historical(app,old_bundle,lua).settle(p,{'id':'catalog-before','kind':'commerce_catalog'},False)
        assert len(catalog)==123 and len(full['products'])==119 and len(old_full['products'])==121
        assert not any(r['sku'] in ('video_p037','video_p038') for r in full['products'])
        old_rows={r['sku']:r for r in old_full['products']}
        for row in full['products']:assert row==old_rows[row['sku']],row['sku']
        assert full['balances']==old_full['balances']
        checks.append({'name':'catalog_123_definitions_only_two_gold_products_hidden_prices_balances_unchanged','status':'PASS','enabled':119})
        before=copy.deepcopy(p);r=send();assert r['ok'],r
        s=p['save']['gameplay_stats'];assert s['starjoy_points']==68 and s['starjoy_points_earned']==1068
        assert p['save']['archive']['commerce']['balances']['u_coin']==before['save']['archive']['commerce']['balances']['u_coin']-catalog['video_p004']['price']
        assert calls[-1]['hash']==new_bundle.hash
        after=copy.deepcopy(p);count=len(calls);assert send()['ok'];assert p==after and len(calls)==count
        checks.append({'name':'new_hash_spent_starjoy_purchase_updates_earned_done_receipt_no_replay','status':'PASS','earned':1068,'retry_worker_calls':0})
        p=profile('101');p['save']['gameplay_stats'].update(starjoy_points_earned=1450,starjoy_reward_level=5)
        assert send(account='101',token='points-new-cross-tier')['ok']
        s=p['save']['gameplay_stats'];assert s['starjoy_points_earned']==1518 and s['starjoy_reward_level']==6 and s['tower_critical_chance_pct']==3
        assert send(account='101',token='points-second-product',sku='video_p011')['ok']
        s=p['save']['gameplay_stats'];assert s['starjoy_points_earned']==1586 and s['starjoy_reward_level']==6 and s['tower_critical_chance_pct']==3
        checks.append({'name':'new_hash_tier_crossing_then_second_purchase_no_duplicate_tier','status':'PASS','earned':1586,'tier':6})
        p=profile('102');assert send(digest=BASE,account='102',token='points-old-ucoin-purchase')['ok']
        assert p['save']['gameplay_stats']['starjoy_points_earned']==1000 and calls[-1]['hash']==BASE
        checks.append({'name':'old_hash_ucoin_purchase_still_uses_recorded_dee_reducer','status':'PASS'})
        for digest,account in ((BASE,'105'),(new_bundle.hash,'106')):
            p=profile(account);before=copy.deepcopy(p);count=len(calls)
            for sku in ('video_p037','video_p038'):
                r=send(digest=digest,account=account,token='points-gold-'+sku,sku=sku)
                assert not r['ok'] and r['error']=='shop_gold_not_open',r
                assert p==before and len(calls)==count
        checks.append({'name':'gold_pause_new_and_old_hash_new_orders_no_debit_no_worker','status':'PASS'})
        p=profile('107');old_service=historical(app,old_bundle,lua)
        request=payload(digest=BASE,account='107',token='points-old-prepared-gold',sku='video_p037')
        before=copy.deepcopy(p);count=len(calls)
        with patch.object(old_service,'finish_prepared',return_value={'ok':True,'done':False}):assert old_service.command(request)['ok']
        assert p==before and len(calls)==count
        r=service.command(request);assert not r['ok'] and r['error']=='shop_gold_not_open' and p==before and len(calls)==count
        checks.append({'name':'prepared_uncommitted_dee_gold_receipt_rejected_on_resume','status':'PASS'})
        p=profile('108');old_service=historical(app,old_bundle,lua)
        request=payload(digest=BASE,account='108',token='points-historical-done-gold',sku='video_p037')
        db.lose_reply=True
        try:old_service.command(request);raise AssertionError('expected_lost_reply')
        except TimeoutError:pass
        assert p['save']['content_inventory'].get(catalog['video_p037']['item_id'])==1
        after=copy.deepcopy(p);count=len(calls);r=service.command(request)
        assert r['ok'] and p==after and len(calls)==count
        assert db.ops[(app._database_account_id('108'),'commerce:points-historical-done-gold')]['hash']==BASE
        checks.append({'name':'historically_done_dee_gold_receipt_returns_original_without_replay','status':'PASS','retry_worker_calls':0})
        p=profile('104');p['save']['gameplay_stats'].update(starjoy_points_earned=1450,starjoy_reward_level=5)
        assert send('starjoy_reconcile',account='104',token='same-match-progress')['ok']
        s=p['save']['gameplay_stats'];s['starjoy_points']+=68;s['starjoy_points_earned']+=68;p['revision']+=1
        assert send('starjoy_reconcile',account='104',token='same-match-progress')['ok']
        s=p['save']['gameplay_stats'];assert s['starjoy_reward_level']==6 and s['tower_critical_chance_pct']==3
        old_state=copy.deepcopy(s);assert send('starjoy_reconcile',account='104',token='same-match-progress')['ok'];assert p['save']['gameplay_stats']==old_state
        s=p['save']['gameplay_stats'];s['starjoy_points']+=600;s['starjoy_points_earned']+=600;p['revision']+=1
        assert send('starjoy_reconcile',account='104',token='same-match-progress')['ok'];assert p['save']['gameplay_stats']['starjoy_reward_level']==7
        checks.append({'name':'guarded_progress_key_same_match_later_crossings_and_retry','status':'PASS'})

        p=profile('201',True);starjoy_before={k:p['save']['gameplay_stats'][k] for k in ('starjoy_points','starjoy_points_earned','starjoy_reward_level')}
        stranger=profile('999',True);stranger_before=copy.deepcopy(stranger)
        rates={'n':5,'r':25,'sr':100,'ssr':400,'ur':1000};seen=set();draw_examples=[]
        for index in range(40):
            pool='map' if index%2==0 else 'dragon_knight'
            token='points-rates-'+str(index);before=copy.deepcopy(p);request=payload('lottery_draw',account='201',token=token,pool_id=pool,count=10)
            r=service.command(request);assert r['ok'],r;res=r['response'];assert res['count']==10 and res['guarantee_satisfied']
            expected=0
            for item in res['results']:
                assert item['duplicate'] and item['converted_currency']=='shop_points'
                assert item['converted_points']==rates[item['quality']],item
                seen.add(item['quality']);expected+=rates[item['quality']]
            wallet=p['save']['archive']['commerce']['balances'];before_wallet=before['save']['archive']['commerce']['balances']
            assert wallet['shop_points']==before_wallet['shop_points']+expected and wallet['u_coin']==before_wallet['u_coin'] and wallet['shop_gold']==before_wallet['shop_gold']
            ticket='lottery_ticket' if pool=='map' else 'special_lottery_ticket'
            assert p['save']['content_inventory'][ticket]==before['save']['content_inventory'][ticket]-10
            assert {k:p['save']['gameplay_stats'][k] for k in starjoy_before}==starjoy_before
            assert p['save']['archive']['commerce']['sentinel']=='preserve' and stranger==stranger_before
            assert res['shop_points']==wallet['shop_points'] and calls[-1]['hash']==new_bundle.hash
            after=copy.deepcopy(p);count=len(calls);assert service.command(request)['ok'] and p==after and len(calls)==count
            draw_examples.append({'pool':pool,'delta':expected,'qualities':[x['quality'] for x in res['results']]})
            if seen==set(rates):break
        assert seen==set(rates),seen
        checks.append({'name':'real_worker_new_hash_all_five_quality_rates_shop_wallet_starjoy_unchanged_tickets_and_retries','status':'PASS','rates':rates,'draw_batches':draw_examples,'other_account_unchanged':True})
        p=profile('202',True);before=copy.deepcopy(p)
        request=payload('lottery_draw',account='202',digest=BASE,token='points-old-draw',pool_id='map',count=10)
        r=service.command(request);assert r['ok'],r
        assert calls[-1]['hash']==BASE
        total=sum(item['converted_points'] for item in r['response']['results'])
        assert total>0 and p['save']['archive']['commerce']['balances']==before['save']['archive']['commerce']['balances']
        assert p['save']['gameplay_stats']['starjoy_points']==total and 'shop_points' not in r['response']
        after=copy.deepcopy(p);count=len(calls);assert service.command(request)['ok'] and p==after and len(calls)==count
        checks.append({'name':'old_dee_draw_keeps_original_starjoy_rule_and_done_retry','status':'PASS','old_starjoy_award':total})
        p=profile('203',True);request=payload('lottery_draw',account='203',token='points-lost-reply-draw',pool_id='map',count=10)
        db.lose_reply=True
        try:service.command(request);raise AssertionError('expected_lost_reply')
        except TimeoutError:pass
        after=copy.deepcopy(p);count=len(calls);assert service.command(request)['ok'] and p==after and len(calls)==count
        checks.append({'name':'new_shop_points_draw_lost_reply_commit_retry_no_double_award','status':'PASS'})
        snapshots=service.lottery_snapshot({'account_id':'201','config_hash':new_bundle.hash})['snapshots']
        assert len(snapshots)==4
        for snap in snapshots:
            assert snap['shop_points']==db.profile(app._database_account_id('201'))['save']['archive']['commerce']['balances']['shop_points']
            assert snap['starjoy_points']==0 and all(x['converted_currency']=='shop_points' for x in snap['items'])
        checks.append({'name':'snapshot_four_pools_authoritative_shop_points_and_item_currency_marker','status':'PASS'})
        old_snapshots=service.lottery_snapshot({'account_id':'202','config_hash':BASE})['snapshots']
        assert calls[-1]['hash']==BASE and len(old_snapshots)==4
        for snap in old_snapshots:
            assert 'shop_points' not in snap and snap['starjoy_points']==total
            assert all('converted_currency' not in item for item in snap['items'])
        checks.append({'name':'old_dee_snapshot_and_draw_both_keep_original_starjoy_currency_no_new_marker','status':'PASS'})

    return {'status':'PASS','checks':checks,'real_worker_calls':len(calls),'worker_executable':str(lua),
        'worker':'actual unchanged packaged Lua 5.1 worker subprocess','external_requests':0,'real_account_data':False,
        'scope':'temporary local Database/App receipt fixture; not live PostgreSQL, network, deployed server or game'}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--lua',default='C:/Program Files/lua/bin/lua5.1.exe');args=ap.parse_args()
    lua=Path(args.lua);assert lua.is_file(),'lua51_executable_missing'
    sys.path[:0]=[str(ROOT/'server'),str(ROOT)]
    OUT.mkdir(parents=True,exist_ok=True)
    basefile=ROOT/'server/bundles'/BASE/'bundle.json';raw=basefile.read_bytes();assert sha(raw)==BASE
    baseline=json.loads(raw);inputs=snapshot_inputs(basefile)
    for name,expected in EXPECTED_SOURCE_HASHES.items():assert inputs[name]==expected,'frozen_source_changed:'+name
    lock=OUT/'SOURCE_LOCK.json'
    if lock.exists():assert json.loads(lock.read_text('utf8'))['inputs']==inputs,'source_lock_changed_refuse_rebuild'
    else:write_json(lock,{'base':BASE,'inputs':inputs,'policy':'Any source/config/compiler/pointer drift refuses rebuild; review as a new candidate instead of overwriting.'})
    active={p.relative_to(ROOT).as_posix():p.read_bytes() for p in (POINTER,GAME)}
    assert json.loads(POINTER.read_text('utf8'))['hash']==BASE and BASE in norm(GAME.read_bytes()),'active_baseline_changed'
    checkpoint=CHECKPOINT.read_bytes()
    configs,compile_report=compile_configs(baseline);data=copy.deepcopy(baseline)
    data['configs'].update(configs)
    for name in SOURCES:data['sources'][name]=norm((ROOT/'scripts/vscripts'/name).read_bytes())
    for name,path in CSV_PATHS.items():data['csv_hashes']['data/csv/'+path]=sha((ROOT/'data/csv'/path).read_bytes().replace(b'\r\n',b'\n'))
    aliases=data['compatible_config_hashes'];assert BASE not in aliases
    commands=sorted(set().union(*(set(rule['commands']) for rule in aliases.values())));assert len(commands)==22
    aliases[BASE]={'commands':commands,'upgrade_commands':[]}
    for key,rule in baseline['compatible_config_hashes'].items():assert aliases[key]==rule
    changed_sources=sorted(k for k in data['sources'] if data['sources'][k]!=baseline['sources'][k]);assert changed_sources==sorted(SOURCES)
    changed_configs=sorted(k for k in data['configs'] if data['configs'][k]!=baseline['configs'][k]);assert set(changed_configs)==CONFIGS
    changed_csv=sorted(k for k in data['csv_hashes'] if data['csv_hashes'][k]!=baseline['csv_hashes'][k]);assert set(changed_csv)=={'data/csv/'+x for x in CSV_PATHS.values()}
    assert data.keys()==baseline.keys() and data['sources'].keys()==baseline['sources'].keys() and data['configs'].keys()==baseline['configs'].keys() and data['csv_hashes'].keys()==baseline['csv_hashes'].keys()
    assert data['sources']['worker.lua']==baseline['sources']['worker.lua']
    body=canonical(data);digest=sha(body);dest=OUT/('archive-commerce-points-'+digest[:12]);assert not dest.exists(),'candidate_exists_refuse_overwrite'
    with tempfile.TemporaryDirectory(prefix='.preparing-',dir=OUT) as temporary:
        stage=Path(temporary);candidate=stage/'candidate/addon/server/bundles'/digest
        for name,text in data['sources'].items():put(candidate/name,text.encode())
        put(candidate/'bundle.json',body)
        write_json(stage/'candidate/addon/server/bundles/current.json',{'hash':digest,'protocol':1})
        put(stage/'candidate/addon/scripts/vscripts/config/generated/archive_http_bundle.lua',('-- Prepared candidate only; not activated. Reopen map after reviewed deployment.\nreturn { protocol = 1, hash = "'+digest+'" }\n').encode())
        put(stage/'rollback/bundle.json',raw)
        for name,text in active.items():put(stage/('rollback/server_current.json' if name.endswith('current.json') else 'rollback/archive_http_bundle.lua'),text)
        for name in SOURCES:put(stage/'rollback'/name,baseline['sources'][name].encode())
        original=LOCAL_BASELINE.read_bytes();current=SERVICE.read_bytes()
        hunks=[{'id':'starjoy_progress_receipt_key','old_exact':OLD,'new_exact':NEW},
               {'id':'pause_uncommitted_shop_gold','old_exact':GOLD_OLD,'new_exact':GOLD_NEW},
               {'id':'snapshot_matches_recorded_lottery_currency','old_exact':SNAPSHOT_OLD,'new_exact':SNAPSHOT_NEW}]
        spec={'version':3,'hunks':hunks,'local_original_baseline':LOCAL_BASELINE.relative_to(ROOT).as_posix(),
            'local_original_baseline_sha256':sha(original),'local_current_sha256':sha(current),'online_source_verified':False,
            'requirement':'Read and review online source first; apply all three exact-context hunks to a separate output only. Do not replace entire online service.py with an unverified local file.'}
        for hunk in hunks:
            hunk['old_context_sha256']=sha(hunk['old_exact'].encode());hunk['new_context_sha256']=sha(hunk['new_exact'].encode())
        write_json(stage/'candidate/guarded_patches/archive_service_patch.json',spec)
        patchfile=stage/'candidate/guarded_patches/apply_archive_service.py';put(patchfile,PATCH_TOOL.encode());ast.parse(PATCH_TOOL)
        guarded=load_module(patchfile,'commerce_points_guarded_patch')
        applied=guarded.transform(original,spec);assert norm(applied)==norm(current),'unexpected_service_change_outside_three_hunks'
        assert guarded.transform(applied,spec,True)==original
        for bad in (applied,original.replace(b'_ensure_gameplay_stats(database_id)',b'_unexpected_schema(database_id)'),guarded.transform(original,{'hunks':[hunks[1]]})):
            try:guarded.transform(bad,spec)
            except ValueError:pass
            else:raise AssertionError('guard_accepted_unexpected_or_partial_source')
        ast.parse(norm(applied));put(stage/'prepare_release.py',Path(__file__).read_bytes())
        with tempfile.TemporaryDirectory(prefix='commerce-points-worker-') as runtime:
            runtime=Path(runtime);old=runtime/BASE;new=runtime/digest
            shutil.copytree(ROOT/'server/bundles'/BASE,old);shutil.copytree(candidate,new)
            result=smoke(new,old,lua)
        write_json(stage/'smoke.json',result)
        detail={'base':BASE,'candidate':digest,'changed_sources':changed_sources,'changed_configs':changed_configs,'changed_csv_hashes':changed_csv,
            'other_sources_configs_csv_identical':True,'worker_identical':True,'existing_compatibility_identical':True,'added_compatibility':{BASE:aliases[BASE]},
            'config_differences':{name:field_diff(baseline['configs'][name],data['configs'][name],data['configs'][name]['key']) for name in changed_configs},
            'source_unified_diffs':{name:''.join(difflib.unified_diff(baseline['sources'][name].splitlines(True),data['sources'][name].splitlines(True),fromfile=BASE+'/'+name,tofile=digest+'/'+name)) for name in SOURCES},
            'official_compilation':compile_report,'service_exact_three_hunks_match_local_original_baseline':True,'service_reverse_restores_exact_original_bytes':True,
            'guard_refuses_applied_partial_unexpected_context':True,'online_python_source_verified':False,'active_pointers_modified':False}
        write_json(stage/'exact_diff.json',detail)
        plan={'status':'PREPARED_NOT_DEPLOYED','base':BASE,'candidate':digest,'production_deployed':False,'external_requests':0,
            'requires_new_game_hash_and_map_restart':True,'old_dee_clients':'Recorded original commerce/lottery reducers retained; no financial upgrade allowlist change. Uncommitted shop_gold intents are refused by separately reviewed Python guard.',
            'done_receipts':'Return original done response without worker or reward replay, including formerly completed gold purchases.',
            'service_delivery':'Three context-guarded patches only; online whole service.py has not been read or verified. Deployment must first back up and inspect actual online source.',
            'rollback':'Exact deployed bundle and local active pointer bytes plus both old Lua sources. Reverse guarded patch restores local baseline bytes; deployment must separately back up actual online Python.',
            'previous_checkpoint':{'path':CHECKPOINT.relative_to(ROOT).as_posix(),'manifest_sha256':sha(checkpoint),'preserved':True},
            'input_hashes':inputs,'candidate_directory':dest.relative_to(ROOT).as_posix(),'new_bundle_sha256':digest,
            'payment_or_sql_files_included':False,'financial_upgrade_allowlist_modified':False}
        write_json(stage/'release_plan.json',plan)

        readme="""# 商城积分：离线发布候选（未部署）

基线是已部署 dee53fe2e9fb...。只替换 commerce_settlement.lua、lottery_http_settlement.lua；只更新 commerce_products、commerce_catalog、lottery_item_definitions 三份配置与两份正式 CSV 哈希。123 条商品与原价格保留，商城金币商品 P037/P038 暂停后实际目录 119 条。重复道具进入 archive.commerce.balances.shop_points：N5、R25、SR100、SSR400，UR 沿原配置 1000。星悦积分保持独立。

三个配置来自正式 CSV 与正式 compiler。唯一非本次 player_gameplay_stats 注释漂移通过 release-local reference override 恢复已部署文字；未修改原 CSV。exact_diff.json 严格限定两条 enabled 与两条重复积分值变化。其余 source、config、CSV 哈希、worker 和已有兼容规则逐项一致。

candidate 下的服务和游戏指针仅为候选；工作区当前指针不变。部署并更新游戏 hash、重新开图后，新局抽奖才使用商城积分。dee 旧局继续其已记录的原抽奖与购买规则，未扩大金融 upgrade allowlist。Python guard 另外暂停所有尚未提交的 shop_gold 购买，包括旧 hash；历史 done 回执始终返回原结果，绝不重放奖励。

Python 只携带三处必须精确匹配上下文的 guarded patch：九行星悦 earned 进度幂等键、shop_gold 暂停，以及旧 hash 快照沿用原币种/规则。没有打包整份未核线上 service.py。部署前必须读取、备份、审核线上实际源码并比对；工具默认只校验。显式独立输出路径才写入，拒绝同路径、已存在输出、上下文不符、已应用或部分应用。三处补丁在内存全部成功后才输出；--reverse 逐一反向恢复。例：

py -3 -B candidate/guarded_patches/apply_archive_service.py --source <已读取并审核的线上副本>

本候选无外网、无账号、无订单创建、无部署操作。smoke.json 使用真实 Lua5.1 可执行文件与未改 worker 子进程，回执数据库仅本地替身；覆盖新旧 hash、5 品质钱包奖励、星悦不变、扣券、重试、丢响应、资源暂停、新旧 done 回执。它不等于线上 PostgreSQL 或游戏实机验收。rollback 保留精确旧 bundle、旧指针和两份 source；线上 Python 完整备份必须在正式部署阶段另做。

SOURCE_LOCK.json 固定本轮所有输入。任何 source/config/compiler/pointer 改变都拒绝重新构建；已存在候选目录拒绝覆盖。前一份星悦候选作为 checkpoint 完整保留。manifest.json 与 tar.gz 校验全部审查资料；发布状态为 PREPARED_NOT_DEPLOYED。
"""
        put(stage/'README.md',readme.encode())
        assert snapshot_inputs(basefile)==inputs,'inputs_changed_during_prepare_refuse_publish'
        assert CHECKPOINT.read_bytes()==checkpoint
        for name,value in active.items():assert (ROOT/name).read_bytes()==value
        files={p.relative_to(stage).as_posix():sha(p.read_bytes()) for p in stage.rglob('*') if p.is_file()}
        expected={f'candidate/addon/server/bundles/{digest}/'+name for name in list(data['sources'])+['bundle.json']}
        expected|={'candidate/addon/server/bundles/current.json','candidate/addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
            'candidate/guarded_patches/archive_service_patch.json','candidate/guarded_patches/apply_archive_service.py',
            'rollback/bundle.json','rollback/server_current.json','rollback/archive_http_bundle.lua',
            *('rollback/'+name for name in SOURCES),'README.md','release_plan.json','exact_diff.json','smoke.json','prepare_release.py'}
        assert set(files)==expected,{'unexpected':sorted(set(files)-expected),'missing':sorted(expected-set(files))}
        assert not any(Path(name).name in ('service.py','config_compatibility.py') or name.endswith('.sql') or 'payment_backend' in name or '__pycache__' in name for name in files)
        write_json(stage/'manifest.json',{'format':1,'status':'PREPARED_NOT_DEPLOYED','base':BASE,'candidate':digest,'files':files})
        archive=stage/'archive_patch.tar.gz'
        with archive.open('wb') as target:
            with gzip.GzipFile(filename='',mode='wb',fileobj=target,mtime=0) as zipped:
                with tarfile.open(fileobj=zipped,mode='w') as tar:
                    for name in sorted(set(files)|{'manifest.json'}):
                        raw_file=(stage/name).read_bytes();entry=tarfile.TarInfo(name);entry.size=len(raw_file);entry.mtime=0;entry.mode=0o644
                        tar.addfile(entry,io.BytesIO(raw_file))
        with tarfile.open(archive,'r:gz') as tar:
            assert set(tar.getnames())==set(files)|{'manifest.json'}
            for entry in tar.getmembers():
                assert entry.isfile() and not entry.name.startswith('/') and '..' not in Path(entry.name).parts
                assert tar.extractfile(entry).read()==(stage/entry.name).read_bytes()
        archive_sha=sha(archive.read_bytes());put(stage/'archive_patch.tar.gz.sha256',(archive_sha+'  archive_patch.tar.gz\n').encode())
        assert snapshot_inputs(basefile)==inputs,'inputs_changed_before_final_rename'
        stage.rename(dest)
    write_json(OUT/'LATEST_PREPARED.json',{'status':'PREPARED_NOT_DEPLOYED','directory':dest.relative_to(ROOT).as_posix(),'candidate':digest,'archive_sha256':archive_sha,'production_deployed':False})
    print(json.dumps({'status':'PREPARED_NOT_DEPLOYED','candidate':digest,'directory':dest.relative_to(ROOT).as_posix(),
        'smoke_checks':len(result['checks']),'archive_sha256':archive_sha,'active_pointers_unchanged':True},ensure_ascii=False))
if __name__=='__main__':main()
