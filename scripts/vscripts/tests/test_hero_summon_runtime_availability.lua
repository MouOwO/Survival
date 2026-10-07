package.path = "scripts/vscripts/?.lua;" .. package.path
local bus=require("core/event_bus")
local events=require("core/events")
local entitlements=require("systems/player_entitlement_service")
local projection=require("systems/hero_summon_projection")
local builder=require("ui/ability_runtime_builder")
bus.reset();entitlements.init()
local ready=false
local summoned={}
local altar={IsNull=function() return false end}
bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST,function(p)
    if not ready then return nil end
    return {ok=true,snapshot=projection.build(p.player_id,altar,3,summoned[p.player_id])}
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
print("HERO_SUMMON_RUNTIME_AVAILABILITY_PASS: first snapshot, denied, entitled, isolated, already summoned, revoked and free")
