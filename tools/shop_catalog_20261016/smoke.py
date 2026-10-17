"""Native Lua worker checks with synthetic profiles; never connects to any service."""
from pathlib import Path
import argparse,copy,json,shutil,subprocess

def run_checks(bundle_path,lua_executable):
    bundle_path=Path(bundle_path);data=json.loads((bundle_path/'bundle.json').read_bytes());configs=data['configs']
    products={p['sku']:p for p in configs['commerce_catalog']['rows']}
    defaults={r['field_id']:r['default_value'] for r in configs['player_gameplay_stats']['rows']}
    profile={'schema_version':1,'account_id':'synthetic-no-database','revision':1,'entitlements':{},'save':{
        'gameplay_stats':dict(defaults,starjoy_points=37,starjoy_points_earned=1000000,starjoy_reward_level=24),
        'content_inventory':{},'archive':{'commerce':{'balances':{'shop_points':10000,'shop_gold':1000000,'u_coin':0}}}}}
    checks=[];calls=0
    def run(source,command):
        nonlocal calls
        payload={'configs':configs,'profile':source,'command':command,'has_pass':False,'seed':12345,'server_time':2000000000}
        p=subprocess.run([str(lua_executable),'worker.lua'],cwd=bundle_path,input=json.dumps(payload,ensure_ascii=False).encode(),
            capture_output=True,check=True,timeout=10,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        calls+=1;return json.loads(p.stdout)
    def purchase(source,sku):return run(source,{'id':'shop-smoke:'+sku,'kind':'commerce_purchase','sku':sku,'request_id':'shop-smoke-'+sku})
    def state(source,result):
        assert result.get('ok') is True,result
        p=copy.deepcopy(source);p['save'].update({k:result[k] for k in ['gameplay_stats','content_inventory','archive']});return p
    def snapshot(source):return run(source,{'id':'shop-smoke:catalog','kind':'commerce_catalog'})
    initial=copy.deepcopy(profile);view=snapshot(profile)
    assert view['ok'] and len(view['products'])==121
    indexed={p['sku']:p for p in view['products']}
    assert indexed['video_p140']['enabled'] and indexed['video_p151']['enabled']
    assert indexed['video_p140']['price']==588 and indexed['video_p151']['price']==5000
    assert not any(p.get('currency')=='shop_gold' for p in view['products'])
    assert profile==initial;checks.append('formal catalog121, both new products, gold hidden; source profile unchanged')
    result=purchase(profile,'video_p140');nature=state(profile,result)
    assert nature['save']['gameplay_stats']['wood_per_second']==defaults['wood_per_second']+1
    assert nature['save']['content_inventory']['lottery_nature_spirit']==1
    assert nature['save']['archive']['commerce']['balances']['shop_points']==9412
    assert nature['save']['gameplay_stats']['starjoy_points']==37
    checks.append('nature588 points grants wood/s1 and shares authoritative lottery ownership')
    for owned in [nature,dict(profile,save=dict(profile['save'],content_inventory={'lottery_nature_spirit':1}))]:
        assert purchase(owned,'video_p140')['error']=='already_owned'
        row=next(p for p in snapshot(owned)['products'] if p['sku']=='video_p140')
        assert not row['enabled'] and row['disabled_reason']=='already_owned' and row['owned']==1
    checks.append('existing lottery owner and repeated nature purchase both refused without a second debit')
    result=purchase(profile,'video_p151');sword=state(profile,result);stats=sword['save']['gameplay_stats']
    for field,amount in products['video_p151']['effects'].items():
        assert abs(stats[field]-(profile['save']['gameplay_stats'][field]+amount))<1e-8,(field,stats[field],amount)
    assert stats['starjoy_points_earned']==1000200 and stats['starjoy_reward_level']==24
    assert sword['save']['content_inventory']['commerce_p151']==1
    assert sword['save']['archive']['commerce']['balances']['shop_points']==5000
    assert purchase(sword,'video_p151')['error']=='already_owned'
    checks.append('sword5000 grants all9 static plus existing map-derived effects, earned200, unique ownership')
    assert not any(k in stats for k in ['shadow_bonus','cage_bonus','archive_source_bonus'])
    checks.append('source20percent remains an engine-only mode-projected bonus, not a persisted additive stat')
    for sku,price in [('video_p140',588),('video_p151',5000)]:
        poor=copy.deepcopy(profile);poor['save']['archive']['commerce']['balances']['shop_points']=price-1
        denied=purchase(poor,sku);assert denied.get('ok') is False and denied['error']=='commerce_balance_insufficient',denied
        assert not any(k in denied for k in ['archive','content_inventory','gameplay_stats'])
    checks.append('insufficient points refuse both new products with no partial returned mutation')
    a=state(nature,purchase(nature,'video_p151'));b=state(sword,purchase(sword,'video_p140'))
    for key in ['content_inventory','gameplay_stats']:assert a['save'][key]==b['save'][key]
    assert a['save']['archive']['commerce']['balances']==b['save']['archive']['commerce']['balances']
    assert a['save']['archive']['commerce']['balances']['shop_points']==4412
    checks.append('opposite purchase order produces equal inventory/stats/wallet4412')
    for sku in ['video_p037','video_p038']:assert purchase(profile,sku)['error']=='shop_gold_not_open'
    checks.append('both gold products remain paused for direct purchase commands')
    assert profile==initial
    return {'status':'PASS','cases':len(checks),'checks':checks,'native_worker_calls':calls,'gateway_requests':0,'database_connections':0,'real_player_data':False}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--bundle',required=True,type=Path);ap.add_argument('--lua',default=shutil.which('lua5.1') or 'C:/Program Files/lua/bin/lua5.1.exe');ap.add_argument('--output',type=Path);args=ap.parse_args()
    result=run_checks(args.bundle,args.lua)
    if args.output:args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))
