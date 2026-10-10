-- Real endless spawn, death and visual-disposal pipeline under instant deaths.
-- Counts retained objects/native calls; this cannot measure Source 2 GPU cost.
package.path = "scripts/vscripts/?.lua;" .. package.path
local noop = function() end
local clock, units, counts = 0, {}, {}
local function count(name) counts[name] = (counts[name] or 0) + 1 end
local function setter(name)
    return function(self, value) count(name); self.values[name] = value end
end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DOTA_UNIT_CAP_MOVE_GROUND = 1
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 2
Vector = function(x,y,z) return {x=x,y=y,z=z} end
GameRules = {GetGameTime=function() return clock end}
Entities = {FindAllByClassname=function() count("world_scan"); return {} end,
    FindByClassname=function() count("world_scan") end}
SpawnEntityFromTableSynchronous=function() count("prop_spawn"); error("unexpected prop") end
PrecacheResource=function() count("runtime_precache"); error("unexpected runtime precache") end
ParticleManager={CreateParticle=function() count("particle_spawn"); error("unexpected particle") end}
local alive_count, retained_count, max_retained, removed_count = 0, 0, 0, 0
CreateUnitByName=function(name,position,clear,owner,unit_owner,team)
    assert(name=="npc_survival_wave_monster" and clear==false and team==DOTA_TEAM_BADGUYS)
    count("unit_spawn")
    local unit={index=#units+1,hull=32,modifiers={},values={},position=position,alive=true}
    function unit:IsNull() return self.removed==true end
    function unit:IsAlive() return self.alive and not self.removed end
    function unit:entindex() assert(not self.removed); return self.index end
    function unit:GetAbsOrigin() assert(not self.removed); return self.position end
    function unit:SetAbsOrigin(position) assert(not self.removed); count("corpse_move"); self.position=position end
    function unit:AddNoDraw() assert(not self.removed); count("corpse_hide"); self.hidden=true end
    function unit:GetHullRadius() return self.hull end
    function unit:SetHullRadius(radius) count("SetHullRadius"); self.hull=radius end
    function unit:HasModifier(name) return self.modifiers[name]~=nil end
    function unit:AddNewModifier(_,_,name,parameters) count("modifier_spawn"); self.modifiers[name]=parameters end
    function unit:FindAbilityByName() end
    for _,method in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth",
        "SetBaseDamageMin","SetBaseDamageMax","SetPhysicalArmorBaseValue",
        "SetBaseMoveSpeed","SetBaseAttackTime","Script_SetAttackRange",
        "SetAttackCapability","SetModelScale","SetModel","SetOriginalModel",
        "SetMoveCapability","SetDeathXP","SetMinimumGoldBounty","SetMaximumGoldBounty",
        "SetBaseMagicalResistanceValue"}) do unit[method]=setter(method) end
    units[#units+1]=unit; alive_count=alive_count+1; retained_count=retained_count+1
    max_retained=math.max(max_retained,retained_count)
    return unit
end
FindClearSpaceForUnit=function() count("placement") end
GetGroundHeight=function() return 0 end
UTIL_Remove=function(unit)
    assert(not unit.removed,"entity removed twice")
    unit.removed=true; retained_count=retained_count-1; removed_count=removed_count+1
end
PlayerResource={GetPlayer=function(_,id) return {player_id=id} end}
CustomGameEventManager={Send_ServerToPlayer=function() count("state_event") end}
package.loaded["core/logger"]={info=noop,warn=noop,error=noop}
package.loaded["systems/player_context_service"]={is_defeated=function() return false end}
package.loaded["systems/archive_service"]={record_endless_wave=function() count("earned_wave") end,flush_endless_rewards=noop}
local bus,events=require("core/event_bus"),require("core/events")
local scheduler=require("core/scheduler")
local lifecycle=require("systems/monster_corpse_lifecycle_service")
local hero_visual=require("systems/monster_hero_visual_service")
local challenge_visual=require("systems/challenge_monster_visual_service")
local generic_visual=require("systems/monster_visual_service")
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
    ["systems/monster_hero_visual_service"]=hero_visual,
    ["systems/monster_corpse_lifecycle_service"]=lifecycle,
    ["combat/endless_stat_projection"]=require("combat/endless_stat_projection"),
}
local env=setmetatable({require=function(name) return deps[name] or {rows={},by_id={}} end},{__index=_G})
local chunk=assert(loadfile("scripts/vscripts/systems/wave_system.lua")); setfenv(chunk,env)
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
    if name=="wave_channels" then debug.setupvalue(wave.spawn_challenge_monster,index,channels); replaced=true; break end
end
assert(replaced,"fixture must enter the real player spawn channels")
package.loaded["systems/wave_system"]=wave
local endless=require("systems/archive_endless_service")
local guard=require("systems/gameplay_phase_guard")
bus.reset(); scheduler.clear(); guard.reset(); guard.set_post_clear_frozen(true)
bus.handle_request("archive.challenge_state",function() return {expired=0} end)
lifecycle.init(); endless.init(noop)
local function find_upvalue(module,wanted)
    local seen={}
    local function visit(fn)
        if type(fn)~="function" or seen[fn] then return end
        seen[fn]=true
        for index=1,100 do
            local name,value=debug.getupvalue(fn,index)
            if not name then break end
            if name==wanted then return value end
            if type(value)=="function" then local found=visit(value); if found~=nil then return found end end
        end
    end
    for _,fn in pairs(module) do local found=visit(fn); if found~=nil then return found end end
end
local function size(values) local n=0; for _ in pairs(values) do n=n+1 end; return n end
local corpse_states=assert(find_upvalue(lifecycle,"corpses"))
local max_corpses,max_tasks,killed_count,scan_index=0,0,0,1
local function kill_newborns()
    while scan_index<=#units do
        local unit=units[scan_index]; scan_index=scan_index+1
        assert(unit.values.SetDeathXP==0 and unit.values.SetMinimumGoldBounty==0 and unit.values.SetMaximumGoldBounty==0)
        assert(unit.survival_monster_default_wearable_asset_id==nil and unit.survival_model_asset_id==nil)
        unit.alive=false; alive_count=alive_count-1; killed_count=killed_count+1
        -- Repeated engine notifications must be harmless for all owned paths.
        bus.emit(events.ENGINE_ENTITY_KILLED,{victim=unit,victim_entindex=unit.index})
        bus.emit(events.ENGINE_ENTITY_KILLED,{victim=unit,victim_entindex=unit.index})
    end
    max_corpses=math.max(max_corpses,size(corpse_states))
    max_tasks=math.max(max_tasks,scheduler.task_count())
end
local TARGET_WAVE=200
for id=0,3 do assert(endless.start(id,1)) end
kill_newborns()
for frame=1,20000 do
    clock=frame*0.05; scheduler.think(); kill_newborns()
    if endless.snapshot(0).cleared==TARGET_WAVE then break end
end
for id=0,3 do
    assert(endless.snapshot(id).cleared==TARGET_WAVE)
    endless.cancel(id,"offline fixture complete")
end
local end_time=clock
for step=1,50 do clock=end_time+step*0.05; scheduler.think() end
assert(#units==4000 and counts.earned_wave==800 and killed_count==4000)
assert(removed_count==4000 and retained_count==0 and alive_count==0)
assert(size(corpse_states)==0 and scheduler.task_count()==0,"corpse/task cache leaked")
assert(generic_visual.active_state_count()==0)
assert(max_corpses<=16 and max_retained<=20,"dead monster count grew with cleared waves")
assert(max_tasks<=9,"more than four spawn tasks, four next-wave tasks, and two shared timers")
assert((counts.world_scan or 0)==0 and (counts.prop_spawn or 0)==0
    and (counts.particle_spawn or 0)==0 and (counts.runtime_precache or 0)==0)
print(string.format("ENDLESS_DEATH_COST_PASS players=4 waves=%d births=%d deaths=%d duplicate_deaths=%d removed=%d max_corpses=%d max_retained=%d max_tasks=%d pending=%d world_scans=%d outfit_props=%d particles=%d corpse_moves=%d",
    TARGET_WAVE,#units,killed_count,killed_count,removed_count,max_corpses,max_retained,max_tasks,
    scheduler.task_count(),counts.world_scan or 0,counts.prop_spawn or 0,counts.particle_spawn or 0,counts.corpse_move or 0))
