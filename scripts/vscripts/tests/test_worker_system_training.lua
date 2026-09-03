package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

DOTA_UNIT_TARGET_TEAM_BOTH = 1
DOTA_UNIT_TARGET_ALL = 1
DOTA_UNIT_TARGET_FLAG_NONE = 0
FIND_ANY_ORDER = 0
DOTA_UNIT_CAP_NO_ATTACK = 0
DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
DOTA_ABILITY_BEHAVIOR_IMMEDIATE = 2048
class = function(definition)
    definition.__index = definition
    return definition
end

local vector_meta = {}
function vector_meta.__add(left, right)
    return Vector(left.x + right.x, left.y + right.y, left.z + right.z)
end
function Vector(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vector_meta)
end

GridNav = {
    IsTraversable = function() return true end,
    IsBlocked = function() return false end,
}
FindUnitsInRadius = function() return {} end
RandomFloat = function() return 0 end
GetGroundHeight = function(position) return position.z end
FindClearSpaceForUnit = function() end

package.loaded["systems/technology_stat_manager"] = {
    get = function()
        return { final = { lumberjack = {} } }
    end,
}
package.loaded["systems/player_profile_service"] = {
    get_profile = function()
        return { save = { gameplay_stats = { lumberjack_attack_range = 125 } } }
    end,
}

local event_bus = require("core/event_bus")
local events = require("core/events")
event_bus.reset()

local city_state = {
    team = 2,
    player_id = 0,
    building_id = "main_city",
    level = 1,
}
local city = {}
function city:IsNull() return false end
function city:entindex() return 100 end
function city:GetPlayerOwnerID() return 0 end
function city:GetTeamNumber() return 2 end
function city:GetAbsOrigin() return Vector(0, 0, 0) end
function city:GetHullRadius() return 128 end

local next_worker_index = 200
local created = {}
local create_should_fail = false
local function worker()
    next_worker_index = next_worker_index + 1
    local unit = { index = next_worker_index, modifiers = {} }
    function unit:IsNull() return self.null == true end
    function unit:entindex() return self.index end
    function unit:SetControllableByPlayer() end
    function unit:SetBaseMaxHealth(value) self.max_health = value end
    function unit:SetMaxHealth(value) self.max_health = value end
    function unit:SetHealth(value) self.health = value end
    function unit:SetPhysicalArmorBaseValue(value) self.armor = value end
    function unit:SetBaseDamageMin(value) self.damage_min = value end
    function unit:SetBaseDamageMax(value) self.damage_max = value end
    function unit:SetBaseAttackTime(value) self.base_attack_time = value end
    function unit:Script_SetAttackRange(value) self.attack_range = value end
    function unit:SetAcquisitionRange(value) self.acquisition_range = value end
    function unit:HasModifier(name) return self.modifiers[name] ~= nil end
    function unit:AddNewModifier(_, _, name, values)
        self.modifiers[name] = values or {}
        return self.modifiers[name]
    end
    function unit:FindModifierByName() return nil end
    function unit:SetBaseMoveSpeed(value) self.move_speed = value end
    function unit:SetAttackCapability(value) self.attack_capability = value end
    function unit:SetModel(value) self.model = value end
    function unit:SetOriginalModel(value) self.original_model = value end
    function unit:FindAbilityByName(name) return self.abilities and self.abilities[name] or nil end
    function unit:AddAbility(name)
        self.abilities = self.abilities or {}
        local ability = { name = name, level = 0 }
        function ability:GetLevel() return self.level end
        function ability:SetLevel(value) self.level = value end
        self.abilities[name] = ability
        return ability
    end
    function unit:ForceKill(reincarnate)
        self.killed = true
        self.force_kill_reincarnate = reincarnate
        event_bus.emit(events.ENGINE_ENTITY_KILLED, { victim = self })
    end
    return unit
end

CreateUnitByName = function(unit_name)
    if create_should_fail then return nil end
    local unit = worker()
    unit.unit_name = unit_name
    created[#created + 1] = unit
    return unit
end

local spend_allowed = true
local spends = {}
local refunds = {}
local population_releases = {}
local resource_account = { wood = 0, gold = 0, population = 0, max_population = 13 }
event_bus.handle_request(events.BUILDING_QUERY_REQUEST, function()
    return city_state
end)
event_bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function(payload)
    spends[#spends + 1] = payload
    if not spend_allowed then
        return { ok = false, error = "insufficient_resources" }
    end
    return { ok = true }
end)
event_bus.handle_request(events.RESOURCE_ADD_REQUEST, function(payload)
    refunds[#refunds + 1] = payload
    return { ok = true }
end)
event_bus.handle_request(events.RESOURCE_RELEASE_POP_REQUEST, function(payload)
    population_releases[#population_releases + 1] = payload
    resource_account.population = math.max(
        0,
        resource_account.population - (tonumber(payload.population) or 0)
    )
    return { ok = true }
end)
event_bus.handle_request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST, function()
    return { ok = true }
end)

package.loaded["systems/worker_system"] = nil
local system = require("systems/worker_system")
system.init()

local function state()
    return event_bus.request(events.WORKER_TRAINING_GET_REQUEST, { team = 2 })
end

local function train(training_id)
    return event_bus.request(events.WORKER_TRAIN_REQUEST, {
        city = city,
        training_id = training_id or "train_lumberjack_auto",
    })
end

local function repair_state(training_id)
    return event_bus.request(events.WORKER_TRAINING_GET_REQUEST, {
        team = 2,
        training_type = "repairer",
        training_id = training_id,
    })
end

spend_allowed = false
train()
assert(state().level == 1 and state().count == 0 and #created == 0,
    "resource failure advanced worker training")

spend_allowed = true
create_should_fail = true
train()
assert(state().level == 1 and state().count == 0,
    "unit creation failure advanced worker training")
assert(#refunds == 1 and refunds[1].wood == 10,
    "unit creation failure did not refund resources")
assert(#population_releases == 1 and population_releases[1].population == 1,
    "unit creation failure did not release population")

create_should_fail = false
local advanced_result = train("train_repairer_02")
assert(advanced_result and advanced_result.ok,
    "advanced repairer could not be trained directly")
local advanced_repairer = created[#created]
assert(advanced_repairer:FindAbilityByName("ability_repairer_suicide")
        and advanced_repairer:FindAbilityByName("ability_repairer_suicide"):GetLevel() == 1,
    "advanced repairer did not receive the configured suicide ability")
assert(repair_state("train_repairer_02").count == 1,
    "advanced repairer direct training was not recorded independently")
assert(spends[#spends].gold == 1000 and spends[#spends].population == 1,
    "advanced repairer did not use its configured cost")
local advanced_spend_count = #spends
train("train_repairer_02")
assert(repair_state("train_repairer_02").count == 2,
    "second advanced repairer was not trainable")
train("train_repairer_02")
assert(#spends == advanced_spend_count + 1
    and repair_state("train_repairer_02").count == 2,
    "advanced repairer exceeded its configured maximum")
assert(repair_state("train_repairer_01").count == 0,
    "advanced repairer training changed normal repairer progress")

for _ = 1, 4 do train() end
local normal_result = train("train_repairer_01")
assert(normal_result and normal_result.ok,
    "normal repairer could not complete its configured final training")
local normal_repairer = created[#created]
assert(normal_repairer:FindAbilityByName("ability_repairer_suicide")
        and normal_repairer:FindAbilityByName("ability_repairer_suicide"):GetLevel() == 1,
    "normal repairer did not receive the configured suicide ability")
assert(state().level == 1 and state().count == 4,
    "LV1 advanced before the configured five trainings")
train()
assert(state().level == 2 and state().count == 0,
    "five configured LV1 workers did not unlock LV2")
local first_lumberjack = nil
for _, candidate in ipairs(created) do
    if candidate.modifiers.modifier_lumberjack_ai then
        first_lumberjack = candidate
        break
    end
end
assert(first_lumberjack and first_lumberjack.damage_min == 22,
    "LV1 worker did not receive configured stats and lumberjack AI")
assert(first_lumberjack.attack_range == 525
        and first_lumberjack.acquisition_range == 525,
    "lumberjack attack range gameplay stat was not applied")

-- Even a stale explicit LV1 request must resolve to the currently unlocked
-- tier; clients cannot bypass or roll back the shared training progression.
train("train_lumberjack_01")
assert(state().level == 2 and state().count == 1,
    "first LV2 worker was not recorded")
assert(spends[#spends].wood == 100 and created[#created].damage_min == 52,
    "LV2 worker did not use its configured cost and attack")

for _ = 1, 2 do train() end
for _ = 1, 3 do train() end
assert(state().level == 4 and state().count == 0,
    "worker progression did not reach LV4")

local spend_count = #spends
train()
assert(#spends == spend_count and state().level == 4 and state().count == 0,
    "LV4 training bypassed the main-city level prerequisite")

city_state.level = 2
train()
assert(#spends == spend_count + 1 and spends[#spends].wood == 1000,
    "LV4 training did not unlock at main-city LV2")

-- Finish LV4, then verify the remaining city gates and advance all the way to
-- LV8 using the real CSV-backed costs and combat data.
for _ = 1, 2 do train() end
assert(state().level == 5 and state().count == 0,
    "three LV4 workers did not unlock LV5")
spend_count = #spends
train()
assert(#spends == spend_count and state().level == 5,
    "LV5 training bypassed the main-city LV3 prerequisite")

city_state.level = 3
for _ = 1, 3 do train() end
assert(state().level == 6 and state().count == 0,
    "three LV5 workers did not unlock LV6")
assert(spends[#spends].wood == 5000 and spends[#spends].gold == 100
    and created[#created].damage_min == 1002,
    "LV5 worker did not use its configured cost and attack")

for _ = 1, 3 do train() end
assert(state().level == 7 and state().count == 0,
    "three LV6 workers did not unlock LV7")
assert(spends[#spends].wood == 12000 and spends[#spends].gold == 1000
    and created[#created].damage_min == 2002,
    "LV6 worker did not use its configured cost and attack")

spend_count = #spends
train()
assert(#spends == spend_count and state().level == 7,
    "LV7 training bypassed the main-city LV4 prerequisite")
city_state.level = 4
for _ = 1, 3 do train() end
assert(state().level == 8 and state().count == 0,
    "three LV7 workers did not unlock LV8")
assert(spends[#spends].wood == 30000 and spends[#spends].gold == 3000
    and created[#created].damage_min == 4002,
    "LV7 worker did not use its configured cost and attack")

for _ = 1, 5 do train() end
assert(state().level == 8 and state().count == 5
    and state().unlimited == 1 and state().max_count == -1,
    "LV8 training was limited or advanced beyond the final tier")
assert(spends[#spends].wood == 50000 and spends[#spends].gold == 5000
    and spends[#spends].population == 3
    and created[#created].damage_min == 8002,
    "LV8 worker did not use its configured cost and data")

local current_before_death = state()
local victim = created[1]
assert(victim.survival_worker_type == "repairer",
    "advanced repairer test victim was not created")
local advanced_before_death = repair_state("train_repairer_02")
assert(advanced_before_death.count == 2 and advanced_before_death.completed == 1,
    "advanced repairer limit did not reflect two living workers")
local suicide = require("abilities/ability_repairer_suicide")
local suicide_ability = setmetatable({}, { __index = suicide })
function suicide_ability:GetCaster() return victim end
resource_account.wood = 654
resource_account.gold = 321
resource_account.population = 12
local refunds_before_death = #refunds
local releases_before_death = #population_releases
suicide_ability:OnSpellStart()
local current_after_death = state()
assert(victim.killed and victim.force_kill_reincarnate == false,
    "repairer suicide did not immediately ForceKill the caster")
assert(current_after_death.level == current_before_death.level
    and current_after_death.count == current_before_death.count,
    "worker death rolled back cumulative training progression")
local advanced_after_death = repair_state("train_repairer_02")
assert(advanced_after_death.count == 1 and advanced_after_death.completed == 0
    and advanced_after_death.total_trained == 2,
    "advanced repairer death did not reopen its living-worker slot")
assert(#population_releases == releases_before_death + 1
    and population_releases[#population_releases].population == 1
    and resource_account.population == 11
    and resource_account.max_population == 13,
    "repairer suicide did not change population from 12/13 to 11/13")
assert(#refunds == refunds_before_death
    and resource_account.wood == 654 and resource_account.gold == 321,
    "repairer suicide refunded wood or gold")

event_bus.emit(events.ENGINE_ENTITY_KILLED, { victim = victim })
assert(#population_releases == releases_before_death + 1
    and resource_account.population == 11,
    "duplicate repairer death released population more than once")

local retrain_spends_before = #spends
local retrain_result = train("train_repairer_02")
assert(retrain_result and retrain_result.ok
    and #spends == retrain_spends_before + 1
    and spends[#spends].gold == 1000 and spends[#spends].population == 1,
    "advanced repairer slot did not reopen with its configured full cost")
assert(repair_state("train_repairer_02").count == 2
    and repair_state("train_repairer_02").total_trained == 3,
    "advanced repairer retraining did not restore the living count")

local invalid_victim = created[2]
local releases_before_invalid_event = #population_releases
invalid_victim.null = true
event_bus.emit(events.ENGINE_ENTITY_KILLED, {
    victim_entindex = invalid_victim:entindex(),
})
assert(#population_releases == releases_before_invalid_event + 1
    and population_releases[#population_releases].population == 1
    and repair_state("train_repairer_02").count == 1,
    "invalid engine victim handle did not release population by entindex")

print("WORKER_SYSTEM_TRAINING_PASS")
