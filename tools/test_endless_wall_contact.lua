-- Run from the addon root with Lua 5.1. Real challenge factory, collision
-- policy and shared wall-contact allocator; no Dota process is needed.
package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x, y, z) return {x=x,y=y,z=z or 0} end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 2
DOTA_UNIT_CAP_MOVE_GROUND, DOTA_UNIT_CAP_MOVE_FLY = 1, 2
GameRules = {GetGameTime=function() return 0 end}
GetGroundHeight = function() return 0 end
GridNav = {IsTraversable=function() return true end,IsBlocked=function() return false end,
    FindPathLength=function(_, a, b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end}
local noop=function() end
local actual_require=require
local collision=arg[1] and dofile(arg[1].."/wave_monster_collision.lua")
    or require("systems/wave_monster_collision")
local ground={movement_type="ground",endless=true}
local ordinary=collision.profile({}, {movement_type="ground"}, true)
local endless=collision.profile({is_challenge_monster=true}, ground)
assert(endless.base_hull_radius==ordinary.base_hull_radius and endless.base_hull_radius==32,
    "endless must use ordinary wave hull instead of zero-sized challenge hull")
assert(not endless.no_unit_collision,"endless rear units must retain physical collision")
local boss=collision.profile({is_challenge_monster=true}, {movement_type="ground"})
assert(boss.base_hull_radius==0 and boss.no_unit_collision,
    "single-boss challenge collision policy must remain unchanged")
assert(collision.profile({is_challenge_monster=true}, {}, true).base_hull_radius==32,
    "explicit wave policy must not be overwritten by challenge lifecycle metadata")

local created,appearances={},{}
local failure_mode,emissions,clears,removals=nil,0,0,0
local function entity(index,position,radius)
    local u={index=index,p=position,hull=radius or 32,modifiers={}}
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:entindex() return self.index end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return self.hull end
    function u:SetHullRadius(value) self.hull=value end
    function u:HasModifier(name) return self.modifiers[name]~=nil end
    function u:AddNewModifier(_,_,name,params) self.modifiers[name]=params end
    function u:FindAbilityByName() end
    for _,name in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth","SetBaseDamageMin",
        "SetBaseDamageMax","SetPhysicalArmorBaseValue","SetBaseMoveSpeed","SetBaseAttackTime",
        "Script_SetAttackRange","SetAttackCapability","SetAcquisitionRange","SetForwardVector",
        "AddAbility","SetModel","SetOriginalModel","SetModelScale","SetMoveCapability"}) do
        u[name]=noop
    end
    if failure_mode=="health" then u.SetHealth=function() error("fixture health setter failure") end end
    if failure_mode=="model" then u.SetModel=function() error("fixture model setter failure") end end
    if failure_mode=="hull" then u.SetHullRadius=function() error("fixture hull setter failure") end end
    if failure_mode=="ai" then
        local add=u.AddNewModifier
        u.AddNewModifier=function(self,source,ability,name,params)
            if name=="modifier_enemy_wall_ai" then error("fixture AI modifier failure") end
            return add(self,source,ability,name,params)
        end
    end
    return u
end
local dependencies={
    ["core/event_bus"]={emit=function() emissions=emissions+1 end},
    ["core/events"]=require("core/events"),
    ["core/scheduler"]={cancel=noop},["core/team_alignment"]={enforce=noop},
    ["systems/wave_monster_collision"]=collision,
    ["combat/endless_stat_projection"]={prepare=function(_,row) return row end},
    ["systems/monster_corpse_lifecycle_service"]={track=noop},
    ["systems/monster_hero_visual_service"]={apply=function(unit,_,options)
        appearances[unit]=options;return true
    end,clear=function(unit)
        clears=clears+1;appearances[unit]=nil
        if failure_mode=="clear" then error("fixture cosmetic cleanup failure") end
    end},
    ["config/generated/archive_challenge_rules"]={by_id={default={}}},
}
for _,name in ipairs({"systems/monster_hull_scale","systems/monster_navigation_policy",
    "systems/wave_spawn_sequence","config/global_rules"}) do dependencies[name]=actual_require(name) end
local env=setmetatable({require=function(name) return dependencies[name] or {rows={},by_id={}} end,
    CreateUnitByName=function(_,position)
        local unit=entity(1000+#created,position);created[#created+1]=unit;return unit
    end,
    FindClearSpaceForUnit=function(unit)
        local ai=assert(unit.modifiers.modifier_enemy_wall_ai,"AI must precede native placement")
        local expected=unit.survival_is_boss and 0 or 32
        assert(unit:GetHullRadius()==expected,"correct collision hull must precede native placement")
        assert(ai.no_unit_collision==(unit.survival_is_boss and 1 or 0),
            "native placement must already have the correct unit-collision state")
        if failure_mode=="placement" or failure_mode=="clear" then error("fixture placement failure") end
    end,
    UTIL_Remove=function(unit)
        assert(not unit.removed,"failed factory must remove its partial unit exactly once")
        assert(unit.survival_wave_cleanup,"forced removal must bypass corpse handling")
        removals=removals+1;unit.removed=true
    end},{__index=_G})
local factory=assert(loadfile((arg[1] and arg[1].."/wave_system.lua")
    or "scripts/vscripts/systems/wave_system.lua"));setfenv(factory,env)
local wave=factory()
local function set_upvalue(fn,wanted,value)
    for index=1,math.huge do
        local name=debug.getupvalue(fn,index)
        if not name then break end
        if name==wanted then debug.setupvalue(fn,index,value);return end
    end
    error("missing factory state "..wanted)
end
local channels,walls={},{}
for player=0,3 do
    local offset=player*2000
    channels[player]={marker={GetAbsOrigin=function() return Vector(offset-400,0,0) end}}
    walls[player]=player+1
end
set_upvalue(wave.spawn_challenge_monster,"wave_channels",channels)
set_upvalue(wave.spawn_challenge_monster,"wall_by_player",walls)
local definition={unit_name="npc_test",model_path="test.vmdl",movement_type="ground",
    attack_type="melee",endless=true,model_scale=.9,move_speed=280,attack_range=160}
local contact=require("systems/wall_melee_contact")
for player=0,3 do
    local offset=player*2000
    local wall=entity(walls[player],Vector(offset,0,0),128)
    local front={}
    for lane=1,4 do
        local u
        if lane%2==0 then
            u=assert(wave.spawn_challenge_monster({health=200,attack=2},definition,player))
            assert(u.survival_is_wave_monster~=true,"endless must not gain formal-wave reward metadata")
            assert(u.modifiers.modifier_enemy_wall_ai.wall_entindex==walls[player])
            assert(appearances[u] and appearances[u].fresh_unit,"fresh appearance policy must survive")
        else
            u=entity(100+player*10+lane,Vector(offset-400,0,0),ordinary.base_hull_radius)
            u.survival_is_wave_monster=true
        end
        u.p=Vector(offset-400,(lane-2.5)*64,0)
        local plan=assert(contact.resolve(wall,u))
        assert(plan.claimed and plan.point.x==offset-192 and plan.point.y==(lane-2.5)*64,
            "mixed formal/endless front must use four separate Hull32 contacts")
        u.p=plan.point;front[#front+1]=u
    end
    local rear=assert(wave.spawn_challenge_monster({health=200,attack=2},definition,player))
    rear.p=Vector(offset-400,0,0)
    assert(not contact.resolve(wall,rear).claimed,"fifth endless monster must wait behind mixed front")
    local ordinary_rear=entity(150+player,Vector(offset-400,30,0),32)
    assert(not contact.resolve(wall,ordinary_rear).claimed,"ordinary waves share the same four-contact cap")
    front[2].dead=true
    local refill=assert(contact.resolve(wall,rear))
    assert(refill.claimed,"endless waiter must replace a dead front owner without increasing contact count")
    rear.p=refill.point
    assert(not contact.resolve(wall,ordinary_rear).claimed,"replacement must consume the single vacant contact")
end
definition.endless=false
local preserved=assert(wave.spawn_challenge_monster({health=200,attack=2},definition,0))
assert(preserved:GetHullRadius()==0 and preserved.modifiers.modifier_enemy_wall_ai.no_unit_collision==1)
definition.endless=true
for _,mode in ipairs({"health","model","hull","ai","placement","clear"}) do
    failure_mode=mode
    local before_created,before_emissions,before_clears,before_removals=#created,emissions,clears,removals
    local protected,unit,reason=pcall(wave.spawn_challenge_monster,{health=200,attack=2},definition,0)
    assert(protected and unit==nil and tostring(reason):find("challenge_monster_setup_failed:",1,true),
        "factory must return a recoverable failure for "..mode)
    assert(#created==before_created+1 and removals==before_removals+1,
        "native setup failure must create once and remove once for "..mode)
    assert(clears==before_clears+1 and not appearances[created[#created]],
        "factory must clean the failed unit's own appearance for "..mode)
    assert(emissions==before_emissions,"failed setup must never publish MONSTER_SPAWNED for "..mode)
end
failure_mode=nil
assert(wave.spawn_challenge_monster({health=200,attack=2},definition,0),
    "later valid spawn must recover after setup failures")
print("ENDLESS_WALL_CONTACT_PASS: four players; mixed front capped at four; Hull32; boss policy; six native setup/cleanup failures")
