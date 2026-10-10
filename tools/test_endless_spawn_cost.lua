-- Offline operation counts through real archive_endless_service -> wave_system
-- -> collision/stats/default-appearance code. Native engine calls are counted,
-- not timed: these counts cannot establish Source 2 CPU/GPU frame cost.
package.path = "scripts/vscripts/?.lua;" .. package.path
local noop = function() end
local clock, units, counts = 0, {}, {}
local function count(name) counts[name] = (counts[name] or 0) + 1 end
local function setter(name)
    return function(self, value)
        count(name)
        self.values[name] = value
    end
end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DOTA_UNIT_CAP_MOVE_GROUND = 1
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 2
Vector = function(x, y, z) return {x=x, y=y, z=z} end
GameRules = {GetGameTime=function() return clock end}
Entities = {
    FindAllByClassname=function() count("world_scan"); return {} end,
    FindByClassname=function() count("world_scan") end,
}
SpawnEntityFromTableSynchronous = function() count("prop_spawn"); error("unexpected outfit spawn") end
PrecacheResource = function() count("runtime_precache"); error("unexpected synchronous runtime precache") end
local function create(name, position, clear, owner, unit_owner, team)
    assert(name=="npc_survival_wave_monster" and clear==false and team==DOTA_TEAM_BADGUYS)
    count("unit_spawn")
    local unit={index=#units+1, hull=32, modifiers={}, values={}, position=position, alive=true}
    function unit:IsNull() return self.removed==true end
    function unit:IsAlive() return self.alive and not self.removed end
    function unit:entindex() return self.index end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetHullRadius() return self.hull end
    function unit:SetHullRadius(radius) count("SetHullRadius"); self.hull=radius end
    function unit:HasModifier(modifier) return self.modifiers[modifier]~=nil end
    function unit:AddNewModifier(_, _, name, parameters)
        count("modifier_spawn"); self.modifiers[name]=parameters
    end
    function unit:FindAbilityByName() end
    for _, method in ipairs({"SetBaseMaxHealth", "SetMaxHealth", "SetHealth",
        "SetBaseDamageMin", "SetBaseDamageMax", "SetPhysicalArmorBaseValue",
        "SetBaseMoveSpeed", "SetBaseAttackTime", "Script_SetAttackRange",
        "SetAttackCapability", "SetModelScale", "SetModel", "SetOriginalModel",
        "SetMoveCapability", "SetDeathXP", "SetMinimumGoldBounty", "SetMaximumGoldBounty",
        "SetBaseMagicalResistanceValue"}) do unit[method]=setter(method) end
    units[#units+1]=unit
    return unit
end
CreateUnitByName=create
FindClearSpaceForUnit=function() count("placement") end
GetGroundHeight=function() return 0 end
UTIL_Remove=function(unit) unit.removed=true end
PlayerResource={GetPlayer=function(_, id) return {player_id=id} end}
CustomGameEventManager={Send_ServerToPlayer=function() count("state_event") end}
package.loaded["core/logger"]={info=noop,warn=noop,error=noop}
package.loaded["systems/player_context_service"]={is_defeated=function() return false end}
package.loaded["systems/archive_service"]={record_endless_wave=noop}
local bus, events=require("core/event_bus"),require("core/events")
local scheduler=require("core/scheduler")
local deps={
    ["core/event_bus"]=bus,["core/events"]=events,["core/scheduler"]=scheduler,
    ["core/team_alignment"]={enforce=noop},
    ["config/armor_balance"]=require("config/armor_balance"),
    ["config/global_rules"]=require("config/global_rules"),
    ["config/generated/archive_challenge_rules"]=require("config/generated/archive_challenge_rules"),
    ["systems/monster_navigation_policy"]=require("systems/monster_navigation_policy"),
    ["systems/monster_hull_scale"]=require("systems/monster_hull_scale"),
    ["systems/wave_monster_collision"]=require("systems/wave_monster_collision"),
    ["systems/wave_spawn_sequence"]=require("systems/wave_spawn_sequence"),
    ["systems/monster_hero_visual_service"]=require("systems/monster_hero_visual_service"),
    ["systems/monster_corpse_lifecycle_service"]={track=function(unit) unit.survival_monster_corpse=true end},
    ["combat/endless_stat_projection"]=require("combat/endless_stat_projection"),
}
local env=setmetatable({require=function(name) return deps[name] or {rows={},by_id={}} end},{__index=_G})
local chunk=assert(loadfile("scripts/vscripts/systems/wave_system.lua"));setfenv(chunk,env)
local wave=chunk()
local channels={}
for id=0,3 do
    local position=Vector(id*1000,0,32)
    channels[id]={marker={GetAbsOrigin=function() return Vector(position.x,position.y,position.z) end}}
end
local replaced=false
for index=1,100 do
    local name=debug.getupvalue(wave.spawn_challenge_monster,index)
    if not name then break end
    if name=="wave_channels" then debug.setupvalue(wave.spawn_challenge_monster,index,channels);replaced=true;break end
end
assert(replaced,"fixture must enter the production player spawn channels")
package.loaded["systems/wave_system"]=wave
local endless=require("systems/archive_endless_service")
local config=require("systems/archive_endless_config")
local guard=require("systems/gameplay_phase_guard")
bus.reset();scheduler.clear();guard.reset();guard.set_post_clear_frozen(true)
bus.handle_request("archive.challenge_state",function() return {expired=0} end)
local availability_changes=0
endless.init(function() availability_changes=availability_changes+1 end)
for id=0,3 do assert(endless.start(id,1)) end
assert(#units==4,"four starts must create only one unit per player")
for birth=2,config.rules.monsters_per_wave do
    clock=(birth-1)*config.rules.spawn_interval
    local before=#units
    scheduler.think()
    assert(#units-before==4,"each scheduled frame creates one unit per active player")
end
assert(#units==20 and scheduler.task_count()==1,"four waves share only the countdown after births")
for _,unit in ipairs(units) do
    assert(unit.values.SetModel==config.rules.model_path and unit.values.SetOriginalModel==config.rules.model_path)
    assert(unit.survival_player_id~=nil and unit.modifiers.modifier_enemy_wall_ai)
    assert(unit.survival_monster_default_wearable_asset_id==nil,
        "the authored endless body has no default outfit")
end
clock=3;scheduler.think()
assert(availability_changes==4,"birth and countdown events cannot repaint archive hub abilities")
assert((counts.world_scan or 0)==0 and (counts.prop_spawn or 0)==0
    and (counts.runtime_precache or 0)==0,"endless setup cannot scan wearables or synchronously precache")
assert(counts.placement==20 and counts.SetModel==20 and counts.SetOriginalModel==20)
print(string.format("ENDLESS_SPAWN_COST_PASS players=4 units=%d placements=%d model_changes=%d world_scans=%d outfit_props=%d runtime_precaches=%d modifier_allocations=%d availability_changes=%d",
    #units,counts.placement,counts.SetModel,counts.world_scan or 0,counts.prop_spawn or 0,
    counts.runtime_precache or 0,counts.modifier_spawn,availability_changes))
-- The real startup manifest must load this exact body before its first spawn.
local context, model_preloads = {}, 0
PrecacheResource=function(kind,path,actual)
    assert(actual==context)
    if kind=="model" and path==config.rules.model_path then model_preloads=model_preloads+1 end
end
local ok,ready,failed=require("systems/startup_asset_preload_service").precache(context)
assert(ok and model_preloads==1,"the endless model must be statically precached once at map startup")
print(string.format("ENDLESS_STARTUP_MODEL_PRECACHE_PASS model=%s calls=%d static_ready=%d failed=%d",
    config.rules.model_path,model_preloads,ready,failed))
