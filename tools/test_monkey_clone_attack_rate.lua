package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local tasks, created, heroes, snapshots, skill_enabled = {}, {}, {}, {}, {}
local serial, requests = 100, 0
local RATE = "modifier_hero_exclusive_summon_attack_rate"
local DEBUG = "modifier_debug_fixed_attack_rate"
package.loaded["core/scheduler"] = {
    after = function(delay, callback, id) tasks[id] = {callback=callback, delay=delay}; return id end,
    every = function(delay, callback, id) tasks[id] = {callback=callback, delay=delay}; return id end,
    cancel = function(id) tasks[id] = nil end,
}
package.loaded["systems/hero_cosmetic_service"] = {
    sync_appearance=function(unit,source) unit.cosmetics=source;return true end,
    clear=function(unit) unit.cosmetics=false end,
}
package.loaded["systems/hero_base_health_service"] = {apply=function() return {} end}
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen=function() return false end}
package.loaded["core/sound_service"] = {play=function() end}
function class(value) return value end
function IsServer() return true end
MODIFIER_PROPERTY_FIXED_ATTACK_RATE = 1
local rate_definition = require("modifiers/modifier_hero_exclusive_summon_attack_rate")
local vector = {}; vector.__index=vector
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector) end
vector.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
RandomVector=function() return Vector(0,0,0) end
GetGroundPosition=function(position) return position end
FindClearSpaceForUnit=function() end
GameRules={GetGameTime=function() return 0 end}
PlayerResource={GetPlayer=function(_,id) return {id=id} end}
UTIL_Remove=function(unit) unit.removed=true end
local function near(actual,expected,label)
    assert(type(actual)=="number" and math.abs(actual-expected)<1e-8,
        (label or "value") .. ": " .. tostring(actual) .. " ~= " .. expected)
end
local function unit(player_id)
    serial=serial+1
    local u={id=serial,player_id=player_id,modifiers={},health=500,maximum=1000,
        bat=1.7,natural_bat=1.7,animation_point=0.5,bat_writes=0,
        modifier_adds=0,rate_transmissions=0,rate_refreshes=0,abilities={}}
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return not self.removed and not self.dead end
    function u:entindex() return self.id end
    function u:GetUnitName() return "npc_dota_hero_monkey_king" end
    function u:GetAbsOrigin() return Vector(0,0,0) end
    function u:GetTeamNumber() return 2 end
    function u:GetPlayerOwnerID() return self.player_id end
    function u:SetPlayerID(value) self.player_id=value end
    function u:SetOwner(value) self.owner=value end
    function u:GetOwner() return self.owner end
    function u:GetAbilityCount() return 0 end
    function u:FindAbilityByName(name) return self.abilities[name] end
    function u:AddAbility(name)
        local ability={SetLevel=function() end,SetActivated=function() end,SetHidden=function() end}
        self.abilities[name]=ability; return ability
    end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(value) self.health=value end
    function u:SetBaseDamageMin(value) self.damage_min=value end
    function u:SetBaseDamageMax(value) self.damage_max=value end
    function u:SetBaseAttackTime(value) self.bat=value;self.bat_writes=self.bat_writes+1 end
    function u:GetBaseAttackTime() return self.bat end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:AddNewModifier(caster,_,name,params)
        local modifier
        if name == RATE then
            self.modifier_adds=self.modifier_adds+1
            modifier=setmetatable({caster=caster},{__index=rate_definition})
            function modifier:GetParent() return u end
            function modifier:SetHasCustomTransmitterData() end
            function modifier:SendBuffRefreshToClients() u.rate_transmissions=u.rate_transmissions+1 end
            function modifier:ForceRefresh()
                u.rate_refreshes=u.rate_refreshes+1
                self.native_interval=self:GetModifierFixedAttackRate()
                self:OnRefresh({})
            end
            modifier:OnCreated(params)
            modifier.native_interval=modifier:GetModifierFixedAttackRate()
        else
            modifier={SetCombatSnapshot=function(self,snapshot) self.snapshot=snapshot end,
                GetStackCount=function() return 0 end}
        end
        self.modifiers[name]=modifier
        return modifier
    end
    function u:GetAttacksPerSecond()
        local fixed=self.modifiers[DEBUG] or self.modifiers[RATE]
        if fixed then return 1/(fixed.native_interval or fixed:GetModifierFixedAttackRate()) end
        return self.runtime_aps or 1/self.bat
    end
    -- Regression approximation of the independently observed native failure:
    -- GetAttacksPerSecond alone still reports 10 when BAT=.1 stops the attack
    -- animation being accelerated. This fixture is not a Dota engine emulator.
    function u:FixtureAttackInterval()
        local interval=1/self:GetAttacksPerSecond()
        local animation_scale=self.bat/interval
        return math.max(interval,self.animation_point/animation_scale)
    end
    function u:AddNoDraw() self.hidden=true end
    for _,name in ipairs({"SetControllableByPlayer","SetHullRadius","SetBaseStrength",
        "SetBaseAgility","SetBaseIntellect","CalculateStatBonus"}) do u[name]=function() end end
    return u
end
CreateUnitByName=function(_,_,_,owner)
    local clone=unit(owner.player_id);created[#created+1]=clone;return clone
end
local reenter_snapshot = false
bus.reset()
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(payload)
    return {ok=heroes[payload.player_id]~=nil,unit=heroes[payload.player_id]}
end)
bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST,function(payload)
    return {ok=true,snapshot={skills=skill_enabled[payload.player_id]
        and {{skill_id="skill_monkey_king_fury",level=1}} or {}}}
end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST,function(payload)
    requests=requests+1
    if reenter_snapshot then
        reenter_snapshot=false
        bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=payload.player_id,
            snapshot=snapshots[payload.player_id]})
    end
    return {ok=true,snapshot=snapshots[payload.player_id]}
end)
local original_print=print
print=function(message)
    if tostring(message):find("%[EventBus%] handler error") then error(message) end
end
local service=require("systems/monkey_king_exclusive_service")
service.init()
local function fixed(hero,aps)
    hero.modifiers[DEBUG]={GetModifierFixedAttackRate=function() return 1/aps end}
end
local function summon(player_id,aps)
    local hero=unit(player_id);hero.survival_hero_id="hero_monkey_king"
    heroes[player_id]=hero;skill_enabled[player_id]=true
    snapshots[player_id]={entindex=hero.id,max_health=1000,engine_attack_min=30,
        engine_attack_max=40,attack_min=300,attack_max=400,attack_speed=1.4,
        strength=10,agility=20,intellect=30}
    if aps then fixed(hero,aps) else hero.runtime_aps=2 end
    bus.emit(events.HERO_SKILL_CHANGED,{player_id=player_id})
    return hero,created[#created]
end
local function interval(clone,aps)
    local modifier=assert(clone.modifiers[RATE],"clone requires an engine FIXED_ATTACK_RATE modifier")
    near(modifier:GetModifierFixedAttackRate(),1/aps,"actual modifier interval")
    near(clone:GetAttacksPerSecond(),aps,"modifier-backed native APS")
    near(clone:GetBaseAttackTime(),clone.natural_bat,"carrier natural BAT must remain unchanged")
    assert(clone.bat_writes==0,"fixed-rate inheritance must never overwrite carrier BAT")
    near(clone:FixtureAttackInterval(),1/aps,"animation-aware fixture interval")
    near(clone.survival_attack_speed,aps,"HUD attack speed cache")
    assert(modifier.caster == heroes[clone.player_id],"modifier caster should be the source hero")
end

local first,clone=summon(0,10)
local second,other=summon(1,3)
interval(clone,10);interval(other,3)
-- Prove the fixture detects the reported mismatch even when the APS getter is
-- unchanged: shortening BAT to the fixed interval recreates a slow animation.
clone.bat=0.1
near(clone:GetAttacksPerSecond(),10,"legacy mutation still reports ten APS")
near(clone:FixtureAttackInterval(),0.5,"legacy BAT mutation exposes the animation bound")
clone.bat=clone.natural_bat
near(clone.damage_min,30);near(clone.damage_max,40)
near(clone.health,500,"speed synchronization may not heal")
near(clone.modifiers.modifier_monkey_king_clone.snapshot.attack_speed,10)
local additions,transmissions,refreshes=clone.modifier_adds,clone.rate_transmissions,clone.rate_refreshes
local bat_writes=clone.bat_writes
for _=1,10 do tasks.monkey_clone_sync.callback() end
assert(clone.modifier_adds==additions and clone.rate_transmissions==transmissions
    and clone.rate_refreshes==refreshes and clone.bat_writes==bat_writes,
    "unchanged polling must not recreate or republish the rate modifier")

fixed(first,5)
local reads=requests
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=snapshots[0]})
interval(clone,5);interval(other,3)
assert(clone.rate_refreshes==refreshes+1,"changing inherited APS must invalidate the native property cache")
assert(requests==reads,"immediate stat-change sync must use its supplied snapshot")
fixed(first,4)
tasks.monkey_clone_sync.callback()
interval(clone,4)
first.modifiers[DEBUG]=nil;first.runtime_aps=2.5
tasks.monkey_clone_sync.callback()
interval(clone,2.5)
clone.modifiers[RATE]=nil
tasks.monkey_clone_sync.callback()
interval(clone,2.5)
assert(clone.modifier_adds==additions+1,"polling must restore a missing fixed-rate modifier")

fixed(first,8)
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=snapshots[1]})
interval(clone,2.5)
reads=requests;reenter_snapshot=true
tasks.monkey_clone_sync.callback()
interval(clone,8)
assert(requests==reads+2,"nested snapshot publication must not recurse into another request")

clone.dead=true
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=clone})
fixed(first,6)
tasks["monkey_clone_respawn:0"].callback()
local respawned=created[#created]
assert(respawned~=clone)
interval(respawned,6)
first.removed=true;heroes[0]=nil
bus.emit(events.HERO_REMOVED,{player_id=0,unit=first,entindex=first.id})
assert(respawned.removed and not tasks["monkey_growth:0"])
interval(other,3)
local replacement,replacement_clone=summon(0,7)
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot={entindex=first.id,attack_speed=99}})
interval(replacement_clone,7)
assert(replacement~=first)
print=original_print
print("MONKEY_CLONE_ATTACK_RATE_PASS: fixed-rate modifier, preserved natural BAT and animation-aware fixture, addspeed changes/removal, spawn/respawn/event/poll sync, stable refresh, identity isolation and deletion")
