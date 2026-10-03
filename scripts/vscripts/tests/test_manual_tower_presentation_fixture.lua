-- SIMULATION: explicit fixture guards/ownership/async cleanup; no engine capture.
package.path = "scripts/vscripts/?.lua;" .. package.path
local rank_projection = require("systems/tower_rank_projection")
local units, ranks, effects, callbacks, tasks = {}, {}, {}, {}, {}
local world, in_tools, occupied = {}, true, false
local delayed_cleanup = false
local serial = 0
local vector = {__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end}
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z},vector) end
IsServer = function() return true end
IsInToolsMode = function() return in_tools end
GetGroundHeight = function() return 384 end
GameRules = {GetGameModeEntity = function() return world end}
CustomNetTables = {GetTableValue=function(_,name,key)
    assert(name=="survival_tower_rank")
    return ranks[tonumber(key:match("^unit_(%d+)$"))]
end}
PlayerResource = {IsValidPlayerID = function(_,id) return id==0 end,GetTeam=function() return 2 end}
DOTA_UNIT_TARGET_FLAG_INVULNERABLE,DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=1,2
DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC,DOTA_UNIT_TARGET_BUILDING=1,2,4
DOTA_UNIT_TARGET_TEAM_BOTH,FIND_ANY_ORDER,DOTA_UNIT_CAP_NO_ATTACK,DOTA_UNIT_CAP_MOVE_NONE=3,0,0,0
FindUnitsInRadius = function() return occupied and {{}} or {} end
PrecacheUnitByNameAsync = function(name, callback)
    assert(name=="npc_dota_unit_ultimate_tower");callbacks[#callbacks+1]=callback
end
package.loaded["core/scheduler"] = {
    after=function(delay,callback,key)tasks[key]={delay=delay,callback=callback} end,
    cancel=function(key)tasks[key]=nil end,
}
package.loaded["systems/tower_rank_presentation_service"] = {
    publish=function(s)ranks[s.entindex]=s end,
    remove=function(i)ranks[i]=nil end,
}
package.loaded["systems/tower_visual_service"] = {
    apply=function(s)
        local rank=rank_projection.project(s)
        local key=tostring(s.tower_class)..rank.rarity..tostring(rank.red_stars>0)
        if effects[s.entindex] and effects[s.entindex].key==key then return true end
        local ids={}
        local count=rank.rarity=="N" and 0 or rank.rarity=="R" and 1
            or (rank.rarity=="UR" or rank.red_stars>0) and 3 or 2
        for _=1,count do serial=serial+1;ids[#ids+1]=serial end
        effects[s.entindex]={key=key,particle_ids=ids,tracked=true}
        return true
    end,
    remove=function(i)effects[i]=nil end,
    debug_snapshot=function(i)return effects[i] or {particle_ids={},tracked=false,key=""} end,
}
package.loaded["systems/building_visual_service"] = {
    apply=function(unit,data) unit:SetModel(data.model_name);return true,"ready" end,
    clear=function(unit)assert(unit.survival_manual_presentation_fixture) end,
}
CreateUnitByName = function(name, position, find_clear, owner, owner_entity, team)
    assert(name=="npc_survival_grid_preview_proxy" and find_clear==false and owner==nil and owner_entity==nil and team==2)
    local u={index=#units+1,position=position,alive=true,model="base",unit_name=name}
    function u:entindex()assert(not self.removed,"queried removed entity index");return self.index end
    function u:IsNull()return self.removed==true end
    function u:IsAlive()assert(not self.removed,"queried removed entity alive state");return self.alive end
    function u:GetUnitName()return self.unit_name end
    function u:GetAbsOrigin()return self.position end
    function u:SetAbsOrigin(value)self.position=value end
    function u:SetModel(value)assert(not self.removed,"late model callback touched removed entity");self.model=value end
    function u:GetModelName()return self.model end
    function u:ForceKill()
        self.alive=false
        if not delayed_cleanup then ranks[self.index]=nil;effects[self.index]=nil end
    end
    for _, method in ipairs({"SetAcquisitionRange","SetAttackCapability","SetMoveCapability","SetHullRadius",
        "SetDayTimeVisionRange","SetNightTimeVisionRange","SetControllableByPlayer","AddNewModifier",
        "SetOriginalModel","SetModelScale"}) do u[method]=function()end end
    units[#units+1]=u
    return u
end
UTIL_Remove = function(unit)assert(unit.survival_manual_presentation_fixture);unit.removed=true end
local fixture_module=require("tests/manual_tower_presentation_review")
assert(#units==0,"requiring fixture must not create units")
in_tools=false;assert(not fixture_module.run().ok and #units==0)
in_tools=true;occupied=true;assert(fixture_module.run().error=="fixture_position_occupied" and #units==0)
occupied=false
local f=fixture_module.run()
assert(f.ok and #f.slots==10 and #units==10)
for _,u in ipairs(units)do
    assert(u.survival_is_building==false and not u.survival_building_id,"fixture must remain unregistered")
    assert(u:GetUnitName()~="building_arrow_tower","legacy upgrade recovery-by-name must not match")
end
for _,callback in ipairs(callbacks)do callback() end
assert(f:status()[10].model_ready)
f:levels(25)
assert(f.slots[1].state.level==1 and f.slots[2].state.level==5 and f.slots[10].state.level==1)
for i=3,9 do assert(f.slots[i].state.level==25)end
local before=effects[3].particle_ids[1]
f:move(3,180,0)
assert(effects[3].particle_ids[1]==before)
delayed_cleanup=true
f:kill(3)
local death_check=tasks.tower_presentation_review_death_3
assert(death_check.delay>1,"death assertion must cover both production fallback sweep periods")
assert(f.last_death_passed==nil and effects[3] and ranks[3],"pending cleanup is not a premature failure")
units[3].removed=true
-- Model the production sweeps finishing before the delayed assertion, even
-- when the original entity has already been removed by the native engine.
ranks[3]={removed=1};effects[3]=nil
death_check.callback()
assert(f.last_death_passed)
assert(f.last_death_check.entindex==3 and f.last_death_check.rank_cleared)
f:kill(4)
local later_check=tasks.tower_presentation_review_death_4
f:cleanup()
assert(tasks.tower_presentation_review_death_4==nil,"cleanup cancels pending assertions")
later_check.callback()
assert(not next(ranks) and not next(effects) and not SURVIVAL_TOWER_PRESENTATION_REVIEW)
for _,u in ipairs(units)do assert(u.removed) end
callbacks={}
f=fixture_module.run()
f:cleanup()
for _,callback in ipairs(callbacks)do callback()end
assert(not SURVIVAL_TOWER_PRESENTATION_REVIEW,"late preload callback must not resurrect a cleaned fixture")
print("MANUAL_TOWER_PRESENTATION_FIXTURE_SIMULATION_PASS")
