package.path = "scripts/vscripts/?.lua;" .. package.path

local stats_by_owner = {}
for id = 0, 3 do stats_by_owner[id] = {attack_flat = 0} end
package.loaded["systems/technology_stat_manager"] = {
    get = function(id) return {final = {lumberjack = stats_by_owner[id]}} end,
}
package.loaded["systems/player_profile_service"] = {get_profile = function() return nil end}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
package.loaded["systems/player_context_service"] = {is_defeated = function() return false end}
package.loaded["systems/worker_visual_service"] = {apply = function() end, cleanup = function() end}
package.loaded["core/modifier_registry"] = {ensure = function() return true end}

DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_ALL = 3, 55
DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER = 0, 0
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_MELEE_ATTACK = 0, 1
local vector = {__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end}
function Vector(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector) end
local now = 0
GameRules = {GetGameTime = function() return now end}
GridNav = {IsTraversable = function() return true end, IsBlocked = function() return false end}
GetGroundHeight = function() return 128 end
FindUnitsInRadius = function() return {} end
FindClearSpaceForUnit = function() end
RandomFloat = function() return 0 end

local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local workers = require("systems/worker_system")
local leader_name = require("config/generated/lumberjack_personality_definitions")
    .by_id.lumberjack_personality_leader.ability_name
local units, cities, buildings, wallets = {}, {}, {}, {}
local lookups, writes, range_writes, modifier_writes = {}, {}, {}, {}
local errors = {}
local original_print = print
print = function(message, ...)
    if tostring(message):find("[EventBus] handler error", 1, true)
        or tostring(message):find("[Scheduler] task failed", 1, true) then
        errors[#errors + 1] = tostring(message)
    else original_print(message, ...) end
end

local function reset_counters()
    for id = 0, 3 do lookups[id], writes[id], range_writes[id], modifier_writes[id] = 0, 0, 0, 0 end
end
reset_counters()
CreateUnitByName = function(name, position)
    local index = 100 + #units
    local unit = {position = position, abilities = {}, owner = 0}
    function unit:IsNull() return self.null == true end
    function unit:IsAlive() return self.dead ~= true end
    function unit:entindex() return index end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetTeamNumber() return 2 end
    function unit:GetPlayerOwnerID() return self.owner end
    function unit:SetControllableByPlayer(id) self.owner = id end
    function unit:SetBaseDamageMin(value) self.damage = value; writes[self.owner] = writes[self.owner] + 1 end
    function unit:SetBaseDamageMax(value) self.max_damage = value end
    function unit:SetBaseAttackTime(value) self.interval = value; range_writes[self.owner] = range_writes[self.owner] + 1 end
    function unit:Script_SetAttackRange(value) self.range = value; range_writes[self.owner] = range_writes[self.owner] + 1 end
    function unit:SetAcquisitionRange() range_writes[self.owner] = range_writes[self.owner] + 1 end
    function unit:HasModifier() return false end
    function unit:FindAbilityByName(ability_name)
        lookups[self.owner] = lookups[self.owner] + 1
        return self.abilities[ability_name]
    end
    function unit:AddAbility(ability_name)
        local ability = {level = 0, GetLevel = function(self) return self.level end,
            SetLevel = function(self, level) self.level = level end}
        self.abilities[ability_name] = ability
        return ability
    end
    local modifier = setmetatable({}, {__index = function(_, key)
        if key:match("^Set") then
            return function() modifier_writes[unit.owner] = modifier_writes[unit.owner] + 1 end
        end
    end})
    function unit:AddNewModifier() return modifier end
    function unit:FindModifierByName() return modifier end
    setmetatable(unit, {__index = function(_, key)
        if key:match("^Set") then return function() end end
    end})
    units[#units + 1] = unit
    return unit
end

scheduler.clear(); bus.reset(); workers.init()
for id = 0, 3 do
    local index = 10 + id
    local city = {
        IsNull = function() return false end, IsAlive = function() return true end,
        entindex = function() return index end, GetTeamNumber = function() return 2 end,
        GetPlayerOwnerID = function() return id end,
        GetAbsOrigin = function() return Vector(id * 3000, 0, 128) end,
        GetHullRadius = function() return 128 end,
    }
    cities[id], buildings[index] = city, {unit = city, building_id = "main_city", player_id = id, team = 2, level = 5}
    wallets[id] = {wood = 10000000, gold = 10000000, population = 0, max_population = 1000}
end
bus.handle_request(events.BUILDING_QUERY_REQUEST, function(p) return buildings[p.entindex] end)
bus.handle_request(events.RESOURCE_GET_REQUEST, function(p)
    local copy = {}; for k, v in pairs(wallets[p.player_id]) do copy[k] = v end; return copy
end)
-- Birth policy and growth tests use the same pre-enqueue wallet boundary as production.
bus.handle_request(events.RESOURCE_CAN_SPEND_REQUEST, function(p)
    local wallet = wallets[p.player_id]
    if wallet.wood < (p.wood or 0) then return {ok = false, error = "wood_not_enough"} end
    if wallet.gold < (p.gold or 0) then return {ok = false, error = "gold_not_enough"} end
    if wallet.population + (p.population or 0) > wallet.max_population then
        return {ok = false, error = "population_not_enough"}
    end
    return {ok = true}
end)
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function(p)
    local wallet = wallets[p.player_id]
    wallet.wood, wallet.gold = wallet.wood - (p.wood or 0), wallet.gold - (p.gold or 0)
    wallet.population = wallet.population + (p.population or 0)
    assert(wallet.population <= wallet.max_population)
    return {ok = true}
end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function() return {totals = {}} end)

local initial_wood = wallets[0].wood
wallets[0].wood = 0
local rejected = bus.request(events.WORKER_TRAIN_REQUEST, {
    player_id = 0, city = cities[0], training_id = "train_lumberjack_01",
})
assert(rejected and not rejected.ok and rejected.error == "wood_not_enough",
    "insufficient resources must reject before entering the production queue")
assert(#units == 0, "rejected training cannot create a worker")
wallets[0].wood = initial_wood

-- Recruit 104 ordinary workers through the production queue and real tier costs.
for level = 1, 8 do
    for _ = 1, (level == 1 and 5 or 3) do
        for id = 0, 3 do
            local result = bus.request(events.WORKER_TRAIN_REQUEST, {
                player_id = id, city = cities[id], training_id = string.format("train_lumberjack_%02d", level),
            })
            assert(result and result.ok and result.queued, "normal training must queue")
        end
        now = now + 1; scheduler.think()
    end
end
local roster = {}
assert(#units == 104 and #bus.request(events.WORKER_LIST_REQUEST, {}) == 104)
for id = 0, 3 do
    roster[id] = bus.request(events.WORKER_LIST_REQUEST, {player_id = id})
    table.sort(roster[id], function(a, b) return a.unit:entindex() < b.unit:entindex() end)
    assert(#roster[id] == 26 and wallets[id].population == 53)
end

local function full_refresh(id)
    bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = id, reason = "research_completed"})
end
local function close(actual, expected, message)
    assert(math.abs(actual - expected) < 1e-9, message or tostring(actual) .. " ~= " .. tostring(expected))
end
reset_counters()
for id = 0, 3 do full_refresh(id) end
for id = 0, 3 do
    assert(lookups[id] == 26 and writes[id] == 26, "four owner refreshes each touch only their 26 workers")
end
reset_counters()
stats_by_owner[0].attack_flat = 50
stats_by_owner[0].attack_speed_bonus_pct = 20
full_refresh(0)
assert(lookups[0] == 26, "no-leader refresh queries each owned worker once, not once per coworker")
for _, state in ipairs(roster[0]) do
    close(state.unit.interval, 1.5 / 1.2)
    close(state.unit.damage, state.base_damage_min + 50)
end
for id = 1, 3 do
    assert(lookups[id] == 0 and writes[id] == 0 and range_writes[id] == 0 and modifier_writes[id] == 0)
    for _, state in ipairs(roster[id]) do close(state.unit.interval, 1.5) end
end

local first, second, ordinary = roster[0][1], roster[0][2], roster[0][3]
first.unit.abilities[leader_name], second.unit.abilities[leader_name] = {}, {}
roster[1][1].unit.abilities[leader_name] = {}
stats_by_owner[0].attack_speed_bonus_pct = 0
reset_counters(); full_refresh(0)
assert(lookups[0] == 28, "two leaders add only two effect queries to the linear owner pass")
close(first.unit.interval, 1.5 / 1.2, "first leader excludes itself")
close(second.unit.interval, 1.5 / 1.2, "second leader excludes itself")
for n = 3, 26 do close(roster[0][n].unit.interval, 1.5 / 1.4, "multiple leaders stack for coworkers") end
for id = 1, 3 do assert(lookups[id] == 0 and writes[id] == 0, "foreign leader and workers stay untouched") end
reset_counters(); full_refresh(1)
close(roster[1][1].unit.interval, 1.5, "single leader receives no self bonus")
close(roster[1][2].unit.interval, 1.5 / 1.2, "single leader affects its owner only")
assert(lookups[0] == 0 and writes[0] == 0)

-- Null registry entries contribute no leader bonus and receive no writes;
-- an otherwise valid unit without ability lookup still receives coworkers' bonus.
first.unit.null = true
ordinary.unit.FindAbilityByName = false
local null_damage = first.unit.damage
reset_counters(); full_refresh(0)
assert(lookups[0] == 25, "null and missing-method entries do not query abilities")
assert(first.unit.damage == null_damage)
close(second.unit.interval, 1.5, "null leader no longer buffs the surviving leader")
close(ordinary.unit.interval, 1.5 / 1.2, "missing ability method does not remove valid coworker benefit")

-- Personal growth and the scoped attack-only path remain synchronous and skip
-- the leader/cadence/range/modifier work entirely.
local other_damage = second.unit.damage
stats_by_owner[0].attack_gain_per_attack = 0.5
reset_counters()
bus.emit(events.TREE_HIT, {player_id = 0, source = "lumberjack", attacker = ordinary.unit})
close(ordinary.unit.damage, ordinary.base_damage_min + 50.5)
assert(second.unit.damage == other_damage and writes[0] == 1 and lookups[0] == 0 and range_writes[0] == 0)
bus.emit(events.TREE_HIT, {player_id = 1, source = "lumberjack", attacker = ordinary.unit})
assert(writes[0] == 1, "a foreign growth callback cannot mutate this worker")
reset_counters(); stats_by_owner[0].attack_flat = 75
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {
    player_id = 0, changed_section = "lumberjack", changed_field = "attack", reason = "runtime_growth",
})
close(ordinary.unit.damage, ordinary.base_damage_min + 75.5)
assert(writes[0] == 25 and lookups[0] == 0 and range_writes[0] == 0 and modifier_writes[0] == 0)
for id = 1, 3 do assert(writes[id] == 0) end
reset_counters(); full_refresh(0)
close(ordinary.unit.damage, ordinary.base_damage_min + 75.5, "full research refresh retains personal growth")
assert(writes[0] == 25)
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, changed_section = "tower"})
assert(writes[0] == 25, "unrelated scoped rewards cannot refresh worker stats")
second.unit.abilities[leader_name] = nil
full_refresh(0)
close(ordinary.unit.interval, 1.5, "removing a leader is observed on the next refresh without cache invalidation")

assert(#errors == 0, table.concat(errors, "\n"))
print = original_print
print("WORKER_LEADER_REFRESH_PASS: 104 ordinary workers, four owners, linear lookups, stacking/self exclusion, foreign/null/missing abilities, immediate technology and private/scoped growth")
