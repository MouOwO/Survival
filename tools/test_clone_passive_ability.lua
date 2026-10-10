-- Real ability runtime service/builder and event bus. Engine handles and
-- nettable transport are fixtures; clone lifecycle events publish immediately.
package.path = "scripts/vscripts/?.lua;" .. package.path

local bus, events = require("core/event_bus"), require("core/events")
local definitions = require("config/generated/hero_skill_definitions")
assert(events.HERO_CLONE_CREATED == "hero.clone.created", "clone-created event is missing")
assert(events.HERO_CLONE_REMOVED == "hero.clone.removed", "clone-removed event is missing")

local tables, writes, registry, errors = {}, {}, {}, {}
local original_print = print
print = function(message)
    if tostring(message):find("handler error", 1, true) then
        errors[#errors + 1] = tostring(message)
    end
end

local timers, polls = 0, 0
package.loaded["core/scheduler"] = {
    after = function() timers = timers + 1; error("clone passive projection must be synchronous") end,
    every = function() polls = polls + 1; error("clone passive projection must not poll") end,
    cancel = function() end,
}
CustomNetTables = {
    SetTableValue = function(_, name, key, value)
        assert(name == "survival_ability_runtime", "unexpected runtime transport")
        tables[key] = value
        writes[#writes + 1] = { key = key, value = value }
    end,
    GetTableValue = function() return nil end,
}
EntIndexToHScript = function(id) return registry[id] end
PlayerResource = { GetTeam = function() return 2 end }
GameRules = { GetGameTime = function() return 0 end }

local function clone(id, player_id, hero_id, skill_id)
    local definition = assert(definitions.by_id[skill_id])
    assert(definition.skill_type == "passive", "clone Q must be defined as a passive")
    local ability = { id = id + 10000, active = true, level = 1, activation_writes = 0, level_writes = 0 }
    function ability:IsNull() return self.removed == true end
    function ability:entindex() return self.id end
    function ability:GetAbilityName() return definition.ability_name end
    function ability:GetLevel() return self.level end
    function ability:IsHidden() return false end
    function ability:IsActivated() return self.active end
    -- The definition must keep the HUD passive even when a newly replicated
    -- native handle does not yet report its passive behavior.
    function ability:IsPassive() return false end
    function ability:GetBehaviorInt() return 2 end
    function ability:SetActivated(value)
        self.activation_writes = self.activation_writes + 1
        self.active = value
    end
    function ability:SetLevel(value)
        self.level_writes = self.level_writes + 1
        self.level = value
    end

    local unit = { id = id, player_id = player_id, ability = ability,
        survival_hero_id = hero_id, survival_permanent_summon = true }
    unit[hero_id == "hero_monkey_king" and "survival_monkey_king_clone" or "survival_blademaster_clone"] = true
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return not self.removed and not self.dead end
    function unit:entindex() return self.id end
    function unit:GetTeamNumber() return 2 end
    function unit:GetPlayerOwnerID() return self.player_id end
    function unit:GetUnitName()
        return hero_id == "hero_monkey_king" and "npc_dota_hero_monkey_king" or "npc_dota_hero_juggernaut"
    end
    function unit:GetAbilityCount() return 1 end
    function unit:GetAbilityByIndex(index) return index == 0 and ability or nil end
    function unit:FindAbilityByName(name) return name == definition.ability_name and ability or nil end
    registry[id] = unit
    return unit
end

local function emit(name, payload)
    bus.emit(name, payload)
    assert(#errors == 0, table.concat(errors, "\n"))
end
local function create(unit)
    emit(events.HERO_CLONE_CREATED, {
        unit = unit, player_id = unit.player_id, team = unit:GetTeamNumber(),
    })
end
local function remove(unit, reason)
    emit(events.HERO_CLONE_REMOVED, {
        unit = unit, entindex = unit:entindex(), player_id = unit.player_id, reason = reason,
    })
end
local function projection(unit)
    return assert(tables[tostring(unit.ability:entindex())], "clone Q runtime must exist at creation")
end
local function check_passive(unit, reason)
    local runtime = projection(unit)
    local summary = assert(tables["unit:" .. unit:entindex()], "clone summary must exist")
    assert(runtime.ability_name == unit.ability:GetAbilityName()
        and runtime.owner_entindex == unit:entindex()
        and runtime.ability_entindex == unit.ability:entindex(),
        reason .. ": clone Q identity must match its own native handle")
    assert(runtime.passive == 1 and runtime.available == 1 and runtime.can_afford == 1
        and runtime.prerequisite_met == 1 and runtime.removed ~= 1,
        reason .. ": inherited Q must remain available as a passive with an empty wallet")
    assert(summary.owner_entindex == unit:entindex() and summary.ability_count == 1
        and summary.removed ~= 1, reason .. ": Q stays in its single clone slot")
    assert(unit.ability.active and unit.ability.level == 1
        and unit.ability.activation_writes == 0 and unit.ability.level_writes == 0,
        reason .. ": runtime publication must preserve native passive activation and level")
end
local function check_removed(unit, reason)
    assert(projection(unit).removed == 1, reason .. ": old ability runtime must be cleared")
    local summary = assert(tables["unit:" .. unit:entindex()])
    assert(summary.removed == 1 and summary.ability_count == 0,
        reason .. ": old unit summary must be cleared")
end

bus.reset()
local wallet = { gold = 0, wood = 0, population = 0, max_population = 0, version = 1 }
bus.handle_request(events.RESOURCE_GET_REQUEST, function() return wallet end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function()
    -- A clone inherits Q once its summon exists; player rank does not make
    -- the clone button look like a separately learnable active ability.
    return { ok = true, snapshot = { rebirth_level = 0 } }
end)
require("ui/ability_runtime_service").init()

local monkey = clone(101, 0, "hero_monkey_king", "skill_monkey_king_exclusive")
local blade = clone(201, 1, "hero_blademaster", "skill_blademaster_exclusive")
create(monkey); check_passive(monkey, "monkey birth")
create(blade); check_passive(blade, "blademaster birth")
assert(monkey.ability:entindex() ~= blade.ability:entindex())

for player_id = 0, 1 do
    for tick = 1, 5 do
        wallet.version = wallet.version + 1
        emit(events.RESOURCE_CHANGED, { player_id = player_id, team = 2,
            version = wallet.version, gold = 0, wood = 0, reason = "harvest" })
        check_passive(monkey, "empty-wallet event")
        check_passive(blade, "other player empty-wallet event")
    end
end
emit(events.HERO_PROGRESSION_CHANGED, { player_id = 0, reason = "reward_applied", rebirth_level = 0 })
check_passive(monkey, "progression refresh")
check_passive(blade, "other player progression isolation")

-- Death removes the old projection even when its engine handle is already
-- invalid. Creation publishes a fresh entity and late old removal is harmless.
monkey.dead, monkey.removed = true, true
remove(monkey, "death"); check_removed(monkey, "monkey death")
check_passive(blade, "monkey death keeps another player's Q")
local respawn = clone(102, 0, "hero_monkey_king", "skill_monkey_king_exclusive")
create(respawn); check_passive(respawn, "monkey respawn")
remove(monkey, "late_death"); check_passive(respawn, "late old removal")
check_removed(monkey, "late old removal keeps old runtime removed")

-- Source 2 may reuse a unit entindex after removal. A stale event carrying
-- the old handle must not clear a replacement clone registered at that index.
local previous_respawn = respawn
previous_respawn.dead, previous_respawn.removed = true, true
remove(previous_respawn, "death"); check_removed(previous_respawn, "respawn death")
respawn = clone(previous_respawn:entindex(), 0, "hero_monkey_king", "skill_monkey_king_exclusive")
respawn.ability.id = previous_respawn.ability:entindex() + 1
create(respawn); check_passive(respawn, "reused unit entindex")
remove(previous_respawn, "late_death"); check_passive(respawn, "stale reused-entindex removal")
assert(projection(previous_respawn).removed == 1, "reused unit keeps the old ability runtime cleared")

blade.dead = true
remove(blade, "death"); check_removed(blade, "blademaster death")
local blade_respawn = clone(202, 1, "hero_blademaster", "skill_blademaster_exclusive")
create(blade_respawn); check_passive(blade_respawn, "blademaster respawn")
remove(blade, "late_death"); check_passive(blade_respawn, "blademaster late old removal")

remove(respawn, "hero_removed"); check_removed(respawn, "hero removal")
emit(events.HERO_SUMMON_STATE_CHANGED, { player_id = 0, hero_summoned = 0 })
emit(events.HERO_PROGRESSION_CHANGED, { player_id = 0, reason = "reward_applied", rebirth_level = 10 })
check_removed(monkey, "removed dead clone stays cleared")
check_removed(respawn, "removed clone never republishes")
check_passive(blade_respawn, "owner removal preserves another player's clone")
remove(blade_respawn, "hero_removed"); check_removed(blade_respawn, "second owner removal")

assert(timers == 0 and polls == 0, "clone ability lifecycle must not add timers or polling")
assert(#errors == 0, table.concat(errors, "\n"))
original_print("CLONE_PASSIVE_ABILITY_PASS: both Q identities, explicit passive state, empty wallet, unchanged native activation, lifecycle cleanup and no polling")
