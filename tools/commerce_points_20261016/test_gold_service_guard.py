'''Real current Lua reducer checks for disabled gold products and stale catalogs.'''
from pathlib import Path
import sys,json,hashlib
ROOT=Path(__file__).resolve().parents[2];sys.path[:0]=[str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps')]
from lupa.lua51 import LuaRuntime
OUT=ROOT/'design_refs/commerce_points_20261016'
source=(ROOT/'scripts/vscripts/systems/commerce_settlement.lua').read_text(encoding='utf-8')
catalog=json.loads((OUT/'generated/commerce_catalog.json').read_text(encoding='utf-8'))
lua=LuaRuntime(unpack_returned_tuples=True);lua.globals().CATALOG=json.dumps(catalog,ensure_ascii=False)
lua.globals().ROOT_PATH=(ROOT/'scripts/vscripts/?.lua').as_posix()
result=lua.execute(r'''
package.path=ROOT_PATH
local decode=require('core/json_decoder').decode
local encode=require('core/json_encoder').encode
local c=decode(CATALOG);c.by_id={};for _,p in ipairs(c.rows) do c.by_id[p.sku]=p end
package.loaded['config/generated/commerce_catalog']=c
local defs=require('config/generated/player_gameplay_stats')
local reducer=require('systems/commerce_settlement')
local function profile()
 local stats={};for _,r in ipairs(defs.rows) do stats[r.field_id]=r.default_value or 0 end
 return {save={archive={commerce={balances={u_coin=1000000,shop_points=1000000,shop_gold=1000000}}},content_inventory={},gameplay_stats=stats},entitlements={}}
end
local checks={}
local p=profile();local before=encode(p);local snapshot=reducer.snapshot(p)
for _,item in ipairs(snapshot.products) do assert(item.sku~='video_p037' and item.sku~='video_p038','disabled_gold_listed') end
assert(encode(p)==before,'catalog_read_mutated_profile')
checks[#checks+1]='Formal disabled gold products absent from purchase catalog; read remains pure'
for _,sku in ipairs({'video_p037','video_p038'}) do
 local result=reducer.settle(p,{kind='commerce_purchase',sku=sku,request_id='formal_'..sku})
 assert(not result.ok and (result.error=='product_unavailable' or result.error=='shop_gold_not_open'),sku..':formal_disabled_bypass')
 assert(encode(p)==before,'formal_rejection_mutated_profile')
end
checks[#checks+1]='Manual purchase of both disabled SKUs refuses without debit/reward'
for _,sku in ipairs({'video_p037','video_p038'}) do
 c.by_id[sku].enabled=true
 local result=reducer.settle(p,{kind='commerce_purchase',sku=sku,request_id='stale_'..sku,quantity=100,price=0})
 assert(not result.ok and result.error=='shop_gold_not_open',sku..':stale_gold_purchase_not_blocked:'..tostring(result.error))
 assert(encode(p)==before,'stale_rejection_mutated_profile')
end
checks[#checks+1]='Stale enabled catalog cannot bypass gold currency guard even with sufficient balance'
local stale=reducer.snapshot(p)
for _,sku in ipairs({'video_p037','video_p038'}) do
 local found=false
 for _,row in ipairs(stale.products) do if row.sku==sku then found=true;assert(not row.enabled and row.disabled_reason=='shop_gold_not_open') end end
 assert(found,'stale_fixture_row_missing')
end
checks[#checks+1]='Stale visible rows publish disabled reason shop_gold_not_open'
return encode({status='PASS',checks=checks,formal_catalog_count=#snapshot.products,stale_catalog_count=#stale.products,profile_unchanged=encode(p)==before})
''')
report=json.loads(result);report['reducer_sha256']=hashlib.sha256(source.encode()).hexdigest();report['scope']='Real Lua51 commerce_settlement, same-compiler catalog fragments; local fixtures only. No game, HTTP, orders, or persistent writes.'
(OUT/'gold_service_guard_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=True,indent=2))
