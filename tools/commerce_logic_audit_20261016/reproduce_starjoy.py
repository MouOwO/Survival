"""Run the real current archive worker against formal products; no network/game/DB."""
import argparse,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps')]
from payment_backend.test_commerce_bundles import LuaBundleTests
from lupa.lua51 import LuaRuntime
parser=argparse.ArgumentParser();parser.add_argument('--expect-fixed',action='store_true');a=parser.parse_args()
LuaBundleTests.setUpClass();b=LuaBundleTests.base_bundle
stats={r['field_id']:r['default_value'] for r in b.configs['player_gameplay_stats']['rows']}
stats.update(starjoy_points=0,starjoy_points_earned=1000,starjoy_reward_level=1)
p={'revision':1,'save':{'archive':{'commerce':{'balances':{'u_coin':1000000,'shop_points':1000000,'shop_gold':1000000}}},'gameplay_stats':stats,'content_inventory':{}},'entitlements':{}}
def worker(profile,command):
 l=LuaRuntime(unpack_returned_tuples=True);l.globals().INPUT=json.dumps({'configs':b.configs,'profile':profile,'command':command,'has_pass':False,'seed':1234,'server_time':2000000000});l.execute('io={read=function() return INPUT end,write=function(v) OUTPUT=v end}')
 s=(b.directory/'worker.lua').read_text(encoding='utf-8').replace('package.path = "./?.lua"','package.path = '+json.dumps(b.directory.as_posix()+'/?.lua'));l.execute(s);return json.loads(l.globals().OUTPUT)
base=worker(p,{'kind':'starjoy_reconcile','id':'baseline'});p['save']['gameplay_stats']=base['gameplay_stats'];before=dict(p['save']['gameplay_stats'])
after=worker(p,{'kind':'commerce_purchase','id':'repro','request_id':'repro_12345','sku':'video_p004'})
keys=['starjoy_points','starjoy_points_earned','starjoy_reward_level']
result={'ok':after.get('ok'),'bundle_hash':b.hash,'sku':'video_p004','reward':b.tables['commerce_catalog']['video_p004']['effects']['starjoy_points'],'before':{k:before[k] for k in keys},'after':{k:after.get('gameplay_stats',{}).get(k) for k in keys},'expected_earned':1068}
p['save']['gameplay_stats']=after['gameplay_stats'];p['save']['archive']=after['archive'];p['save']['content_inventory']=after['content_inventory']
reconciled=worker(p,{'kind':'starjoy_reconcile','id':'further'})
result['after_followup_reconcile']={k:reconciled.get('gameplay_stats',{}).get(k) for k in keys}
print(json.dumps(result,indent=2))
if a.expect_fixed:assert result['after']['starjoy_points_earned']==1068,result
