package.path = "scripts/vscripts/?.lua;" .. package.path
local bus,events=require("core/event_bus"),require("core/events")
for _,module in ipairs({"core/scheduler","systems/building_system","ui/weapon_synthesis_snapshot_service",
    "ui/combat_stat_projection","config/asset_catalog","systems/building_batch_upgrade_service",
    "systems/gold_mine_batch_upgrade_service","config/tree_config"}) do package.loaded[module]={} end
package.loaded["systems/hero_summon_projection"]={hero_id_for_summon_ability=function() return nil end}
package.loaded["ui/stat_push_coalescer"]={new=function() return {} end}
local router=require("ui/ui_request_router")
local listener,responses,dispatches=nil,{},{}
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end,GetPlayer=function(_,id) return id end}
CustomGameEventManager={RegisterListener=function(_,name,fn) assert(name=="ui_ability_cast_request");listener=fn end,
    Send_ServerToPlayer=function(_,player,name,payload) responses[#responses+1]=payload end}
DOTA_ABILITY_BEHAVIOR_POINT=16
bit={band=function() return 0 end}
for index=1,100 do
    local name,value=debug.getupvalue(router.init,index)
    if not name then break end
    if name=="register_ability_cast_request" then value();break end
end
assert(listener)
local unit={survival_worker_type="lumberjack",survival_player_id=0}
local ability={name="ability_fuse_lumberjack_03",active=true}
function unit:IsNull() return false end
function unit:FindAbilityByName() return ability end
function unit:CastAbilityNoTarget() error("fusion must reach the authoritative service directly") end
function ability:IsNull() return false end
function ability:GetAbilityName() return self.name end
function ability:GetCaster() return unit end
function ability:IsPassive() return false end
function ability:GetBehaviorInt() return 4 end
function ability:GetLevel() return 1 end
function ability:GetCooldownTimeRemaining() return 0 end
function ability:IsFullyCastable() return true end
function ability:IsActivated() return self.active end
function ability:IsHidden() return false end
EntIndexToHScript=function(id) return id==1 and unit or id==2 and ability or nil end
local success=true
bus.handle_request(events.LUMBERJACK_FUSION_REQUEST,function(p)
    dispatches[#dispatches+1]=p
    return {ok=success,error=not success and "gold_not_enough" or nil}
end)
for level=1,8 do
    ability.name=string.format("ability_fuse_lumberjack_%02d",level)
    listener(nil,{PlayerID=0,entindex=1,ability_entindex=2})
    assert(#dispatches==level and responses[#responses].success==1)
end
success=false;listener(nil,{PlayerID=0,entindex=1,ability_entindex=2})
assert(responses[#responses].success==0 and responses[#responses].error=="gold_not_enough")
local count=#dispatches
listener(nil,{PlayerID=1,player_id=0,entindex=1,ability_entindex=2})
assert(#dispatches==count and responses[#responses].success==0,"client cannot forge an owner")
ability.active=false;listener(nil,{PlayerID=0,entindex=1,ability_entindex=2})
assert(#dispatches==count and responses[#responses].success==0)
print("PASS lumberjack fusion UI: 8 abilities direct dispatch, service failure, forged owner, inactive ability")
