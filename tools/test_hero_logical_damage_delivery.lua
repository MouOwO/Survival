-- Run from addon root with Lua 5.1; no live game or production reload.
-- Real item producers, transaction pipeline and filter; native filter keys
-- deliberately match the four fields observed in the actual Source2 callback.
package.path = "scripts/vscripts/?.lua;" .. package.path
DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_MAGICAL, DAMAGE_TYPE_PURE = 1, 2, 4
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 0
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 2
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER = 0, 0
class = function(value) return value or {} end
IsServer = function() return true end
RandomFloat = function() return 1 end
local now, jobs, owned = 0, {}, {orbital=true}
GameRules = {GetGameTime=function() return now end}
CustomNetTables = {SetTableValue=function() end}
CustomGameEventManager = {RegisterListener=function() end}
package.loaded["core/scheduler"] = {every=function(interval, callback, key)
    jobs[key] = {interval=interval, callback=callback}
end}
package.loaded["systems/commerce_effects"] = {
    owned=function(_, key) return owned[key] == true end, invalidate=function() end,
}
package.loaded["systems/rogue_effect_state_service"] = {
    has_effect=function() return false end, numeric=function() return 0 end,
}
package.loaded["systems/player_context_service"] = {active_player_ids=function() return {0} end}
package.loaded["systems/worker_system"] = {refresh_commerce_capacity=function() end}

local bus, events = require("core/event_bus"), require("core/events")
local combat_events = require("combat/combat_events")
local rules = require("combat/damage_rule_config")
local repository = require("combat/damage_transaction_repository")
local projection = require("combat/endless_stat_projection")
local filter = require("combat/damage_filter_service")
local service = require("combat/damage_service")
local adapter = require("adapters/dota_damage_adapter")
local armor = require("config/armor_balance")
require("modifiers/modifier_equipment_effects")
local commerce = require("systems/commerce_runtime")
local entities, serial = {}, 0
local function unit(player_id, real_hero)
    serial = serial + 1
    local u = {index=serial, survival_player_id=player_id, real_hero=real_hero,
        alive=true, health=1000000, max_health=1000000, modifiers={}}
    entities[serial] = u
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.index end
    function u:GetUnitName() return "npc_dota_creature" end
    function u:IsRealHero() return self.real_hero == true end
    function u:IsIllusion() return false end
    function u:IsInvulnerable() return false end
    function u:HasModifier() return false end
    function u:FindModifierByName() return nil end
    function u:FindAllModifiersByName() return {} end
    function u:GetPhysicalArmorValue() return 0 end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.max_health end
    function u:GetTeamNumber() return self.real_hero and 2 or 3 end
    function u:GetAbsOrigin() return {x=0,y=0,z=0} end
    function u:GetPlayerOwnerID() return self.survival_player_id end
    function u:GetStrength() return 123 end
    function u:GetAgility() return 234 end
    function u:GetIntellect() return 345 end
    function u:AddNewModifier(caster, ability, name, kv)
        self.modifiers[#self.modifiers+1] = {caster=caster,name=name,kv=kv}
    end
    return u
end
EntIndexToHScript = function(index) return entities[index] end
repository.init(rules)
filter.init({event_bus=bus,events=combat_events,repository=repository,config=rules})
service.init({event_bus=bus,events=combat_events,context=require("combat/damage_context"),
    rules=rules,repository=repository,adapter=adapter,debug={log=function() end}})
local hero, candidates, radius, calls, captured = nil, {}, nil, {}, {}
bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function() return {unit=hero} end)
bus.handle_request(events.EQUIPMENT_STATS_GET_REQUEST, function()
    return {snapshot={values={}}}
end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function()
    return {snapshot={strength=123,agility=234,intellect=345}}
end)
bus.handle_request(events.EQUIPMENT_EFFECT_SNAPSHOT_GET_REQUEST, function()
    return {snapshot={sources={{source_id="gear",effects={{effect_type="aura_attribute_damage",
        value={multiplier=2.5,internal_cooldown=0.75,range=700}}}}}}}
end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function()
    return {totals={hero_attack_armor_reduction=12}}
end)
for _, name in ipairs({"DAMAGE_REQUESTED","DAMAGE_CALCULATED","DAMAGE_SUBMITTED",
        "DAMAGE_FILTERED","DAMAGE_RESOLVED","DAMAGE_BLOCKED"}) do
    local event_name = name
    bus.subscribe(combat_events[event_name], function(payload)
        captured[event_name] = captured[event_name] or {}
        captured[event_name][#captured[event_name]+1] = payload
    end)
end
FindUnitsInRadius = function(_, _, _, requested_radius)
    radius = requested_radius
    return candidates
end
local function near(actual, expected, label)
    assert(type(actual)=="number" and math.abs(actual-expected)
        <= math.max(1e-18,math.abs(expected)*1e-11),
        label .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
ApplyDamage = function(input)
    assert(input.ability==nil,"item producer unexpectedly supplied an ability")
    -- No category/inflictor fields, source-kind hints or mocked filter result.
    local keys = {entindex_attacker_const=input.attacker:entindex(),
        entindex_victim_const=input.victim:entindex(),
        damagetype_const=input.damage_type,damage=input.damage}
    local call = {input=input,keys=keys,pending_before=repository.debug_snapshot().pending_records}
    assert(filter._filter_for_test(filter,keys),"real filter rejected damage")
    calls[#calls+1] = call
    input.victim.health = math.max(0,input.victim.health-keys.damage)
    return keys.damage
end
local function reset_capture()
    calls,captured = {},{}
end
local function count(name) return #(captured[name] or {}) end
local function check_item_delivery(expected, damage_type, targets)
    assert(#calls==#targets,"wrong number of native item submissions")
    for _, name in ipairs({"DAMAGE_REQUESTED","DAMAGE_CALCULATED","DAMAGE_SUBMITTED",
            "DAMAGE_FILTERED","DAMAGE_RESOLVED"}) do
        assert(count(name)==#targets,name .. " was missing or duplicated")
    end
    assert(count("DAMAGE_BLOCKED")==0,"item damage was blocked")
    for index,target in ipairs(targets) do
        local call = calls[index]
        local requested,submitted = captured.DAMAGE_REQUESTED[index],captured.DAMAGE_SUBMITTED[index]
        local filtered,resolved = captured.DAMAGE_FILTERED[index],captured.DAMAGE_RESOLVED[index]
        assert(call.input.attacker==hero and call.input.victim==target,"wrong item combatants")
        assert(call.input.damage_type==damage_type and requested.source_kind=="item"
            and submitted.source_kind=="item","lost logical item provenance")
        assert(call.pending_before==1,"native filter did not receive pending item transaction")
        near(call.input.damage,expected,"adapter receives authored logical item amount")
        near(requested.base_damage,expected,"producer formula")
        local logical = expected
        if damage_type==DAMAGE_TYPE_PHYSICAL then
            logical = logical*armor.war3_physical_damage_multiplier(512,0)
        end
        near(filtered.final_damage,logical,"filtered logical damage before HP projection")
        near(filtered.engine_damage,logical,"logical engine payload")
        near(submitted.final_damage,logical,"submitted logical result")
        near(call.keys.damage,logical/(target.survival_endless_health_scale or 1),
            "native damage applies HP projection exactly once")
        assert(filtered.transaction_id and filtered.transaction_id==submitted.transaction_id
            and resolved.transaction_id==filtered.transaction_id,"transaction events lost correlation")
        assert(filtered.attacker_entindex==hero:entindex()
            and filtered.victim_entindex==target:entindex(),"logical event combatants changed")
        assert(repository.get(filtered.transaction_id).attacker==nil,
            "completed transaction retained an entity")
    end
    local state = repository.debug_snapshot()
    assert(state.active_records==0 and state.pending_records==0,"item delivery leaked pending transaction")
end

for _, attack in ipairs({1e12,9e15}) do
    now = now+100
    hero = unit(0,true)
    local _, native = projection.prepare_attack(hero,attack,attack,20)
    assert(hero.survival_endless_attack_scale>1 and native*20<=1e8,
        "hero fixture did not exercise bounded 20x native attack projection")
    local ordinary,scaled = unit(0),unit(0)
    projection.prepare(scaled,{health=1e20,attack=0})
    scaled.health,scaled.max_health = 1e8,1e8
    candidates = {ordinary,scaled}
    local gear = setmetatable({parent=hero},{__index=modifier_equipment_effects})
    function gear:GetParent() return self.parent end
    function gear:SetHasCustomTransmitterData() end
    function gear:SendBuffRefreshToClients() end
    function gear:StartIntervalThink(interval) self.interval=interval end
    gear:OnCreated({player_id=0})
    assert(gear.interval==0.25,"gear polling interval changed")
    reset_capture()
    gear:OnIntervalThink()
    assert(radius==700,"gear range changed")
    check_item_delivery(702*2.5,DAMAGE_TYPE_MAGICAL,{ordinary,scaled})
    reset_capture()
    gear:OnIntervalThink()
    now = now+0.74
    gear:OnIntervalThink()
    assert(#calls==0 and count("DAMAGE_REQUESTED")==0,"gear bypassed internal cooldown")
    now = now+0.02
    gear:OnIntervalThink()
    check_item_delivery(702*2.5,DAMAGE_TYPE_MAGICAL,{ordinary,scaled})

    jobs = {}
    commerce.init()
    local wall = unit(0)
    bus.emit(events.BUILDING_CREATED,{building_id="wall",player_id=0,unit=wall})
    ordinary.survival_is_wave_monster,scaled.survival_is_challenge_monster = true,true
    for _, target in ipairs({ordinary,scaled}) do
        target.survival_war3_armor_target=true
        target.survival_armor_mapping_version=armor.CUSTOM_WAR3_MAPPING_VERSION
        target.survival_effective_war3_armor=512
    end
    local foreign,unmarked,dead = unit(1),unit(0),unit(0)
    foreign.survival_is_wave_monster=true
    dead.survival_is_challenge_monster,dead.alive=true,false
    candidates = {ordinary,foreign,unmarked,dead,scaled}
    commerce.orbital(0,"endless:27")
    local orbital = assert(jobs.commerce_orbital_0,"orbital was not scheduled")
    assert(orbital.interval==0.5,"orbital cadence changed")
    commerce.orbital(0,"endless:28")
    assert(jobs.commerce_orbital_0==orbital,"orbital bypassed 10-second cooldown")
    reset_capture()
    assert(orbital.callback()==true,"orbital stopped before second tick")
    assert(radius==1600,"orbital range changed")
    check_item_delivery(702*10,DAMAGE_TYPE_PHYSICAL,{ordinary,scaled})
    for _, target in ipairs({ordinary,scaled}) do
        assert(#target.modifiers==1 and target.modifiers[1].name=="modifier_research_armor_reduction",
            "orbital lost its armor strip")
        near(target.modifiers[1].kv.armor_reduction_per_attack,armor.from_war3_linear(12),"armor strip")
    end
    assert(#foreign.modifiers==0 and #unmarked.modifiers==0 and #dead.modifiers==0,
        "orbital affected a foreign, unmarked or dead monster")
    now = now+11
    commerce.orbital(0,"endless:27")
    assert(jobs.commerce_orbital_0==orbital,"orbital repeated the same wave")
end

-- One real periodic commerce tick also protects the unrelated raw flame-wall
-- path: its author is the wall, damage is 1% native max HP, and no Deal runs.
owned = {flame_wall=true}
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen=function() return false end}
local flame_target = unit(0)
flame_target.survival_is_wave_monster=true
local projected = projection.prepare(flame_target,{health=1e12,attack=0})
flame_target.health,flame_target.max_health=projected.health,projected.health
candidates = {flame_target}
reset_capture()
assert(jobs.commerce_runtime.callback()==true,"commerce periodic tick stopped")
assert(#calls==1 and calls[1].input.attacker~=hero and calls[1].pending_before==0,
    "flame wall was routed through a hero/item transaction")
near(calls[1].input.damage,flame_target:GetMaxHealth()*0.01,"raw flame-wall submission")
assert(count("DAMAGE_REQUESTED")==0 and count("DAMAGE_SUBMITTED")==0
    and count("DAMAGE_FILTERED")==1 and captured.DAMAGE_FILTERED[1].transaction_id==nil,
    "raw flame-wall event behavior changed")
assert(repository.debug_snapshot().pending_records==0,"raw wall left a pending item transaction")
print("HERO_LOGICAL_DAMAGE_DELIVERY_PASS gear/orbital real delivery with missing native category/inflictor; 1e12/9e15 20x hero projection, ordinary/scaled targets, cooldown/owner checks and unchanged raw flame wall")
