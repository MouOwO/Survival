package.path = "scripts/vscripts/?.lua;" .. package.path
local bus=require("core/event_bus")
local events=require("core/events")
local entitlements=require("systems/player_entitlement_service")
local projection=require("systems/hero_summon_projection")
local builder=require("ui/ability_runtime_builder")
local effects=require("systems/rogue_effect_state_service")
bus.reset();entitlements.init()
effects.reset()
local ready=false
local summoned={}
local altar={IsNull=function() return false end, IsAlive=function() return true end}
local city_level=3
bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST,function(p)
    if not ready then return nil end
    return {ok=true,snapshot=projection.build(p.player_id,altar,city_level,summoned[p.player_id])}
end)
local function runtime(name,id)
 local response=bus.request(events.HERO_SUMMON_SNAPSHOT_REQUEST,{player_id=id})
 return builder.build(name,{player_id=id,building_id="hero_altar",hero_summon_snapshot=response and response.snapshot},{})
end
for _,name in ipairs({"ability_summon_monkey_king","ability_summon_blademaster"}) do
 ready=false
 assert(runtime(name,0).available==0,"no snapshot is locked")
 ready=true
 assert(runtime(name,0).available==0,"default entitlement is locked")
 assert(runtime(name,0).status_text~="" and runtime(name,0).status_text~="英雄权限同步中","loaded denial must explain the missing entitlement")
 entitlements.replace_all(1,{vip=true},"test")
 assert(runtime(name,0).available==0,"another player cannot unlock")
 assert(runtime(name,1).available==1,"verified entitlement enables")
 summoned[1]={hero_id="hero_doom",unit_name="npc_dota_hero_doom_bringer"}
 assert(runtime(name,1).available==0,"one hero limit still enforced")
 summoned[1]=nil
 entitlements.replace_all(1,{vip=false},"test")
 assert(runtime(name,1).available==0,"revoked entitlement disables")
end
assert(runtime("ability_summon_doom",0).available==1,"free hero enabled")
city_level=0
assert(runtime("ability_summon_doom",0).available==1,"completed early altar stays summonable without city level three")
altar=nil
assert(runtime("ability_summon_doom",0).available==0,"no altar unlock remains locked")
effects.add_numeric(0,"builder_free_hero_altar",1)
assert(runtime("ability_summon_doom",0).available==1,"rogue build unlock permits summoning before construction")
assert(runtime("ability_summon_doom",1).available==0,"teammate cannot use the owner's early unlock")
assert(runtime("ability_summon_monkey_king",0).available==0,"early stage does not grant paid/VIP access")
effects.consume_numeric(0,"builder_free_hero_altar",1)
assert(runtime("ability_summon_doom",0).available==0,"consumed grant without a completed altar locks again")
city_level=3
assert(runtime("ability_summon_doom",0).available==1,"normal build unlock permits pre-altar summoning")
summoned[0]={hero_id="hero_doom"}
assert(runtime("ability_summon_doom",0).available==0,"normal unlock preserves the one hero limit")
print("HERO_SUMMON_RUNTIME_AVAILABILITY_PASS: first snapshot, early/normal unlocks, entitlement, player isolation, consumed grants and one hero limit")
