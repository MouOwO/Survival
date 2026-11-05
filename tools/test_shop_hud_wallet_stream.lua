-- Real producer/catalog/evaluator/resource/research chain. Engine calls are
-- isolated, while price, stock, eligibility and purchase admission stay real.
package.path="scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"..package.path
local original_print=print
print=function(...)local line=tostring(select(1,...));if line:find("handler error",1,true)or line:find("task failed",1,true)then error(line)end end
package.loaded["systems/player_context_service"]={is_defeated=function()return false end}
-- Synthetic engine players have no Steam APIs. Admission itself is covered
-- by test_test_access_policy; this fixture admits only its two engine slots.
package.loaded["core/test_access_policy"]={enforce=function(id)return id==0 or id==1 end,allowed=function(id)return id==0 or id==1 end,enabled=function()return false end}
local bus,events=require("core/event_bus"),require("core/events")
local scheduler=require("core/scheduler")
local resource=require("systems/resource_system")
local research=require("bootstrap/research_technology_bootstrap")
local catalog=require("systems/shop_catalog")
local native_build=catalog.build_snapshot
local clock,session,handles,bound,builds,pushes,players_read,progression,shop
local function fixture(funds)
    bus.reset();scheduler.clear();clock=0;session="fixture_session";builds=0;pushes=0;players_read=0
    handles={[0]={},[1]={}};bound={[0]=true,[1]=true};progression={[0]=0,[1]=0}
    package.loaded["systems/match_setup_service"]={get_session_id=function()return session end}
    package.loaded["ui/compact_ui_transport"]={is_bound=function(id)return bound[id]==true end}
    GameRules={GetGameTime=function()return clock end,GetGameModeEntity=function()return{}end}
    Time=function()return clock end;IsServer=function()return true end;IsInToolsMode=function()return false end
    GetMapName=function()return"template_map"end
    PlayerResource={IsValidPlayerID=function(_,id)return id==0 or id==1 end,GetTeam=function()return 2 end,
        GetPlayer=function(_,id)players_read=players_read+1;return handles[id]end}
    CustomNetTables={SetTableValue=function()end}
    local lab={IsNull=function()return false end,entindex=function()return 12 end}
    local buildings={{entindex=12,building_id="building_advanced_research_lab",player_id=0,team=2,unit=lab},
        {entindex=14,building_id="main_city",player_id=0,team=2,level=4}}
    bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()return{ok=true,totals={initial_wood=funds or 1000000,initial_gold=funds or 1000000,initial_population_cap=100}}end)
    bus.handle_request(events.BUILDING_QUERY_REQUEST,function(p)for _,b in ipairs(buildings)do if b.entindex==p.entindex then return b end end end)
    bus.handle_request(events.BUILDING_LIST_REQUEST,function()return{buildings=buildings}end)
    bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST,function(p)return{snapshot={rebirth_level=progression[p.player_id]}}end)
    bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST,function()return{snapshot={hero_summoned=1}}end)
    bus.handle_request(events.PLAYER_ENTITLEMENT_GET_REQUEST,function()return{snapshot={vip=1}}end)
    bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST,function()return{snapshot={counts={}}}end)
    package.loaded["systems/shop_system"]=nil;shop=require("systems/shop_system")
    resource.init();shop.init();research.init()
    for id=0,1 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,team=2})end
    for _,b in ipairs(buildings)do bus.emit(events.BUILDING_CREATED,b)end
    catalog.build_snapshot=function(id,context)builds=builds+1;return native_build(id,context)end
    bus.subscribe(events.SHOP_STATE_CHANGED,function()pushes=pushes+1 end)
end
local function open(mode,modern,id)
    local result,why=bus.request(events.SHOP_OPEN_REQUEST,{player_id=id or 0,mode=mode or"shop",source_entindex=12,hud_wallet=modern and 1 or 0})
    assert(result and result.ok,tostring(why)..":"..tostring(result and result.error));return result.snapshot
end
local function add(id)
    local result=bus.request(events.RESOURCE_ADD_REQUEST,{player_id=id or 0,wood=1,gold=1,reason="lumberjack_hit"})
    assert(result and result.ok,result and result.error)
end
local function tick(t)clock=t;scheduler.think()end
local sizes={}
fixture()
for _,mode in ipairs({"shop","challenge","research"})do
    local snapshot=open(mode,true);assert(snapshot.hud_wallet==1);sizes[mode]=#snapshot.entries
    for _,entry in ipairs(snapshot.entries)do assert(entry.wallet_purchasable==0 or entry.wallet_purchasable==1)end
    local before=builds;local sent=pushes;local read=players_read
    for i=1,1000 do
        clock=clock+0.01;add(0)
        bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0,reason="star_blessing_attributes_per_second",tick=i})
        bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0,rebirth_level=0,reason="attack_all_attribute_growth"})
        scheduler.think()
    end
    tick(clock+0.1);assert(builds==before,"modern wallet/growth ticks cannot rebuild any catalog: "..mode)
    assert(pushes==sent,"modern wallet/growth ticks cannot publish old DTOs: "..mode)
    assert(players_read-read==1000,"one owner identity read per wallet event in isolated fixture")
end
-- The old client still receives authoritative resource patches.
local legacy=open("shop",false);assert(legacy.hud_wallet==nil)
local before=builds;local sent=pushes;add(0);tick(clock+0.1)
assert(builds>before and pushes>sent,"unnegotiated client retains compatibility")
-- Capability cannot be claimed without a live CW binding.
bound[0]=false;assert(open("shop",true).hud_wallet==nil);bound[0]=true
-- Structural dependencies still publish promptly in modern mode.
open("challenge",true);before=builds;sent=pushes
progression[0]=1;bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0,rebirth_level=1,reason="reward_applied"});tick(clock+0.1)
assert(builds==before+1 and pushes>sent,"a real rebirth changes the actual server projection")
-- Private old observers cannot survive player reuse, session replacement or disconnect.
for _,kind in ipairs({"player","session","binding","disconnect"})do
    fixture();open("shop",true);before=builds;sent=pushes
    if kind=="player"then handles[0]={}elseif kind=="session"then session="new_session"
    elseif kind=="binding"then bound[0]=false else bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})end
    add(0);tick(clock+0.1);assert(builds==before and pushes==sent,"stale owner is retired: "..kind)
end
fixture();open("shop",true);bus.reset();shop.init();before=builds;sent=pushes
bus.emit(events.RESOURCE_CHANGED,{player_id=0,wood=100,gold=100});tick(clock+0.1)
assert(builds==before and pushes==sent,"world init retires the old observer")
-- Funding the display does not alter actual server purchase validation.
fixture();local snap=open("shop",true);local target
for _,entry in ipairs(snap.entries)do if entry.purchasable==1 and(entry.wood_cost>0 or entry.gold_cost>0)then target=entry;break end end
assert(target,"real catalog has a purchasable paid item")
local funds=bus.request(events.RESOURCE_GET_REQUEST,{player_id=0})
assert(bus.request(events.RESOURCE_TRY_SPEND_REQUEST,{player_id=0,wood=funds.wood,gold=funds.gold,reason="fixture"}).ok)
local result=bus.request(events.SHOP_PURCHASE_REQUEST,{player_id=0,entry_id=target.purchase_entry_id or target.entry_id,request_id="fixture_denied_purchase"})
assert(result and result.ok==false,"the funded display capability must not grant a purchase")
local after=bus.request(events.RESOURCE_GET_REQUEST,{player_id=0});assert(after.wood==0 and after.gold==0)
-- Independent fully funded legacy snapshots are the oracle for the new
-- non-resource display predicate, including stock/limits/research access.
local projections={}
fixture(0)
for _,mode in ipairs({"shop","challenge","research"})do projections[mode]=open(mode,true)end
fixture(1000000000000)
for _,mode in ipairs({"shop","challenge","research"})do
    local funded=open(mode,false);local by_id={}
    for _,entry in ipairs(funded.entries)do by_id[entry.entry_id]=entry end
    for _,entry in ipairs(projections[mode].entries)do
        local expected=assert(by_id[entry.entry_id]);assert(entry.wallet_purchasable==expected.purchasable)
        assert(entry.wallet_disabled_reason==expected.disabled_reason);assert(entry.wallet_disabled_reason_code==expected.disabled_reason_code)
        for _,key in ipairs({"wood_cost","gold_cost","stock","stock_max","owned_count","purchase_limit","prerequisite_met","completed"})do
            assert(entry[key]==expected[key],"funding display must not modify "..key)
        end
    end
end
catalog.build_snapshot=native_build
original_print("PASS modern_shop_hud_wallet_stream modes=3 hot_wallet_events=3000 growth_events=6000 hot_catalog_builds=0 hot_legacy_sends=0 shop_entries="..sizes.shop.." challenge_entries="..sizes.challenge.." research_entries="..sizes.research)
