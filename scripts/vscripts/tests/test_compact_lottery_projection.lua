package.path="scripts/vscripts/?.lua;"..package.path
local lookup=assert(loadfile("scripts/vscripts/config/generated/ui_static_catalog_lookup.lua"))()
local config=require("config/lottery_config")
local legacy=require("systems/lottery_http_settlement")
local factory=assert(require("ui/compact_lottery_projection").new(lookup))
local F,R=lookup.field_by_name,lookup.by_key
local function copy(v)if type(v)~="table"then return v end local o={}for k,c in pairs(v)do o[k]=copy(c)end return o end
local p={account_id="compact_fixture",mode="standard",match_session_id="test",revision=1,save={content_inventory={lottery_ticket=100,special_lottery_ticket=7},archive={lottery_state={pools={}},commerce={balances={shop_points=123}}},gameplay_stats={map_level=3,starjoy_points=45,starjoy_points_earned=62}}}
for i=1,10000 do p.save.content_inventory["irrelevant_"..i]=i end
p.save.content_inventory.lottery_flame_crystal=1
local s,ops=assert(factory.initialize(p,{pending=false}))
assert(s.inspect().metrics.inventory_entries_scanned==10003)
local initial=copy(ops);local expected=legacy.snapshots(p)
local values={};local function apply(rows)for _,w in ipairs(rows)do values[w.record]=values[w.record]or{};values[w.record][w.field]=w.remove and nil or w.value end end
local function get(key,field)return(values[R[key]]or{})[F[field]]end
apply(ops)
for _,snapshot in ipairs(expected)do
 local pool=snapshot.selected_pool;assert(get("lottery:pool:"..pool.id,"tickets")==pool.tickets)
 assert(get("lottery:pool:"..pool.id,"unlocked")== (pool.unlocked and 1 or 0))
 assert(get("lottery:pool:"..pool.id,"unlock_progress")==pool.unlock_progress)
 for _,item in ipairs(snapshot.items)do assert(get("lottery:item:"..item.id,"owned_count")==item.owned_count,item.id)end
end
for i=1,1000 do local out,m=assert(s.update(p,{},{}));assert(#out==0 and m.inventory_entries_scanned==0 and m.inventory_reads==0 and m.items==0 and m.pools==0)end
local id=config.pools.map.items[1].id
p.revision=2;p.save.content_inventory[id]=1
ops=assert(s.update(p,{inventory={id},headers=true},{}));apply(ops)
assert(s.inspect().metrics.inventory_reads<=2 and s.inspect().metrics.inventory_entries_scanned==0 and s.inspect().metrics.items==1)
local changed=copy(ops);local expected_changed=legacy.snapshots(p)
-- Read acknowledgement uses the actual public HTTP catalogue revisions even
-- when local authoring metadata has newer, unpublished display text.
local manifest=require("config/generated/lottery_catalog_manifest")
local read_profile=copy(p)
for _,pool in ipairs(config.pool_order)do
 local revision=assert(manifest.pool_revisions[pool.id])
 assert(revision~=pool.revision,"fixture must exercise independent production revisions")
 read_profile.save.archive.lottery_state.pools[pool.id]={details_revision=revision,notice_revision=revision}
end
local _,read_ops=assert(factory.initialize(read_profile,{}))
local read_values={};for _,op in ipairs(read_ops)do read_values[op.record]=read_values[op.record]or{};read_values[op.record][op.field]=op.value end
for _,pool in ipairs(config.pool_order)do
 local row=assert(read_values[R["lottery:pool:"..pool.id]])
 assert(row[F.update_unread]==0 and row[F.notice_unread]==0,pool.id)
end
-- Authoritative receipt ownership is pre-grant for a new nonstackable. Keep
-- it separate from the post-commit item ownership; never optimistically add.
local item=config.by_id[id]
local response={ok=true,pool_id="map",count=1,results={{id=id,quality=item.quality,owned_count=0,duplicate=false,converted_points=0}},guarantee_quality="",guarantee_satisfied=true}
assert(s.bind_intent(51,"map",1))
ops=assert(s.receipt(51,response,false));apply(ops)
local receipt=copy(ops)
assert(get("lottery:receipt","success")==0 and get("lottery:receipt","pending")==1)
assert(get("lottery:item:"..id,"owned_count")==1)
ops=assert(s.receipt(51,response,true));apply(ops)
assert(get("lottery:receipt","success")==1 and get("lottery:receipt","terminal")==1)
assert(get("lottery:result:1","owned_count")==0 and get("lottery:item:"..id,"owned_count")==1)
for _,op in ipairs(ops)do receipt[#receipt+1]=copy(op)end
local bad=copy(p);bad.account_id="different";assert(not s.update(bad,{headers=true},{}))
bad=copy(p);bad.revision=0;assert(not s.update(bad,{},{}))
assert(not s.update(p,{mystery=true},{}));assert(not pcall(s.bind_intent,51,"map",1))
local json=require("core/json_encoder");local before=json.encode(s.full_ops("map"));bad=copy(p)
bad.revision=3;bad.save.content_inventory.lottery_ticket=888;bad.save.content_inventory[id]=-1
assert(not s.update(bad,{headers=true,inventory={"lottery_ticket",id}},{}))
assert(json.encode(s.full_ops("map"))==before and s.inspect().revision==p.revision,"rejected K update partially changed model")
assert(s.bind_intent(52,"map",1));ops=assert(s.receipt(52,{ok=false,error="secret backend diagnostic"},false));apply(ops)
assert(get("lottery:receipt","error_code")==1 and get("lottery:receipt","terminal")==1)
local unknown,uops=assert(factory.initialize(nil,{}));assert(#uops==1 and uops[1].value==0 and not unknown.inspect().known)
local high=copy(p);high.save.content_inventory.lottery_ticket=4294967296+3;high.revision=3
ops=assert(s.update(high,{inventory={"lottery_ticket"}},{}));apply(ops)
assert(get("lottery:pool:map","tickets")==3 and get("lottery:pool:map","tickets_hi")==1)
local wire=require("ui/compact_wire");local schema=assert(wire.compile_lookup(lookup,1));local binding={schema=1,schema_sha256=lookup.sha256,session=12000,epoch=200,view=201}
local packets,stats=assert(wire.encode(schema,binding,100000,s.full_ops("map"),{full=true,value_budget=24}))
for _,packet in ipairs(packets)do assert(#packet.d<=24)end
if arg and arg[1]=="emit"then
 print(require("core/json_encoder").encode({initial_ops=initial,initial_expected=expected,changed_ops=changed,changed_expected=expected_changed,read_ops=read_ops,receipt_ops=receipt,receipt_expected=response}))
else print("compact lottery projection: real 4 pools + 105 memberships, initial inventory10003 once; 1000 stable updates0scans/0item/header visits; K1<=2 direct reads; typed receipt/profile mismatch/unknown error/high counters/native24 passed")end
