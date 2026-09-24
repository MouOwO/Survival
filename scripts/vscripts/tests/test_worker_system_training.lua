-- Offline regression: unavailable land must not consume resources or spawn workers.
package.path = "scripts/vscripts/?.lua;" .. package.path

local definitions = {rows = {
    {training_id = "train_lumberjack_01", training_type = "unit", enabled = true,
        name = "农民", level = 1, max_count = 5, wood_cost = 10, population_cost = 1},
    {training_id = "train_repairer_01", training_type = "unit", enabled = true,
        name = "修理工", level = 1, max_count = 5, wood_cost = 100, gold_cost = 20,
        population_cost = 1, unit_name = "test_repairer"},
    {training_id = "train_population_01", training_type = "population_upgrade", enabled = true,
        name = "人口训练", level = 1, max_count = 1, wood_cost = 30, population_add = 5},
}}
definitions.by_id = {}
for _, row in ipairs(definitions.rows) do definitions.by_id[row.training_id] = row end
package.loaded["config/generated/training_definitions"] = definitions
package.loaded["systems/technology_stat_manager"] = {get = function() return {final = {lumberjack = {}}} end}
package.loaded["systems/player_profile_service"] = {}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
package.loaded["core/modifier_registry"] = {ensure = function() return true end}

DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_ALL = 3, 55
DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER = 0, 0
DOTA_UNIT_CAP_NO_ATTACK = 0
local vector = {}
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector) end

local bus, events = require("core/event_bus"), require("core/events")
local service = require("systems/worker_system")
local checks, attempts, calls, notifications, created, cleared, state, units
local traversable, blocked, occupied, spend_ok, create_ok
local city_origin_height
local city = {
    IsNull = function() return false end,
    entindex = function() return 10 end,
    GetAbsOrigin = function() return Vector(1000, 2000, city_origin_height) end,
    GetHullRadius = function() return 128 end,
    GetTeamNumber = function() return 2 end,
    GetPlayerOwnerID = function() return 0 end,
}

local function reset()
    checks, attempts, calls, notifications, created, cleared, units = 0, 0, {}, {}, {}, {}, {}
    traversable, blocked, occupied, spend_ok, create_ok = true, false, false, true, true
    city_origin_height = 128
    state = {building_id = "main_city", team = 2, player_id = 0, level = 1}
    bus.reset()
    service.init()
    bus.handle_request(events.BUILDING_QUERY_REQUEST, function() return state end)
    bus.handle_request(events.RESOURCE_GET_REQUEST, function()
        return {population = 0, max_population = 20}
    end)
    for _, event in ipairs({events.RESOURCE_TRY_SPEND_REQUEST,
        events.RESOURCE_ADD_REQUEST, events.RESOURCE_RELEASE_POP_REQUEST}) do
        bus.handle_request(event, function(payload)
            calls[#calls + 1] = {event = event, payload = payload}
            if event == events.RESOURCE_TRY_SPEND_REQUEST then
                return {ok = spend_ok, error = not spend_ok and "wood_not_enough" or nil}
            end
            return {ok = true}
        end)
    end
    bus.subscribe(events.UI_NOTIFICATION, function(payload) notifications[#notifications + 1] = payload end)
    GridNav = {
        IsTraversable = function(_, position)
            checks = checks + 1
            if traversable == "error" then error("navigation unavailable") end
            if type(traversable) == "function" then return traversable(position) end
            return traversable
        end,
        IsBlocked = function(_, position)
            if blocked == "error" then error("navigation unavailable") end
            if type(blocked) == "function" then return blocked(position) end
            return blocked
        end,
    }
    FindUnitsInRadius = function() return occupied and {city} or {} end
    RandomFloat = function() attempts = attempts + 1; return 0 end
    GetGroundHeight = function() return 128 end
    FindClearSpaceForUnit = function(unit, position)
        assert(position and position.z == GetGroundHeight(position, city))
        cleared[#cleared + 1] = position
        unit.position = position
    end
    CreateUnitByName = function(name, position)
        assert(position ~= nil, "never pass an absent destination to the engine")
        created[#created + 1] = {name = name, position = position}
        if not create_ok then return nil end
        local id = 100 + #created
        local unit = {position = position}
        function unit:IsNull() return false end
        function unit:IsAlive() return true end
        function unit:entindex() return id end
        function unit:HasModifier() return false end
        function unit:GetAbsOrigin() return self.position end
        function unit:ForceKill() self.killed = true end
        setmetatable(unit, {__index = function(_, key)
            if key:match("^Set") or key == "AddNewModifier" then return function() end end
        end})
        units[id] = unit
        return unit
    end
    EntIndexToHScript = function(id) return units[id] end
end

local function train(options)
    options = options or {}
    options.city = city
    options.training_id = options.training_id or "train_repairer_01"
    local result, error_message = bus.request(events.WORKER_TRAIN_REQUEST, options)
    assert(not error_message, error_message)
    return result
end

local function assert_no_land()
    local result = train()
    assert(result and result.ok == false and result.error:find("没有可通行的空地", 1, true))
    assert(attempts == 24, "search remains bounded to the configured candidates")
    assert(#calls == 0, "rejection must precede every resource/population mutation")
    assert(#created == 0 and #cleared == 0)
    assert(#notifications == 1 and notifications[1].player_id == 0 and notifications[1].level == "error")
    return result
end

reset(); traversable = false; assert_no_land()
reset(); blocked = true; assert_no_land()
reset(); occupied = true; assert_no_land()
reset(); traversable = "error"; assert_no_land()
reset(); blocked = "error"; assert_no_land()

-- Traversable water is still rejected by height relative to the city's ground.
reset()
GetGroundHeight = function(position)
    return position.x > 1300 and 4 or 128
end
assert_no_land()
assert(checks == 0, "underwater candidates fail before navigation or occupancy")

-- A valid center is insufficient when any of its four 32-unit edges drops off.
reset()
GetGroundHeight = function(position) return position.y > 2000 and 4 or 128 end
assert_no_land()
reset()
GetGroundHeight = function(position) return position.y < 2000 and 95 or 128 end
assert_no_land()
reset(); blocked = function(position) return position.y > 2000 end
assert_no_land()

-- Keep the declared slope tolerances inclusive without accepting steeper drops.
reset()
GetGroundHeight = function(position) return position.y ~= 2000 and 96 or 128 end
assert(train().ok and #created == 1)
reset()
GetGroundHeight = function(position) return position.x > 1300 and 192 or 128 end
assert(train().ok and created[1].position.z == 192)
reset()
GetGroundHeight = function(position) return position.x > 1300 and 193 or 128 end
assert_no_land()

-- Use actual terrain height beneath an elevated building model, not model Z.
reset(); city_origin_height = 1024
assert(train().ok and #created == 1 and created[1].position.z == 128)
assert(checks == 5, "center and all four ground/navigation samples are checked")

-- Missing ground information cannot turn into an unchecked fallback either.
reset(); GetGroundHeight = function() return nil end
local missing_ground = train()
assert(missing_ground.ok == false and #calls == 0 and #created == 0 and attempts == 0)

-- A rejected attempt is retryable and does not advance worker training.
reset(); traversable = false; assert_no_land()
traversable = true
local result = train()
assert(result.ok and #created == 1 and #cleared == 1 and #calls == 1)
assert(calls[1].event == events.RESOURCE_TRY_SPEND_REQUEST)
assert(calls[1].payload.wood == 100 and calls[1].payload.gold == 20 and calls[1].payload.population == 1)
assert(result.training.total_trained == 1 and result.training.count == 1)

-- Reject obstructed candidates, retaining the first valid grounded destination.
reset(); traversable = function(position) return position.x > 1450 end
result = train()
assert(result.ok and checks > 1 and checks < 24)
assert(created[1].position.x > 1450 and created[1].position.z == 128)
assert(cleared[1] == created[1].position and #calls == 1)

-- Existing spending failure and engine creation refund behavior stay intact.
reset(); spend_ok = false
result = train()
assert(result.ok == false and result.error == "wood_not_enough" and #calls == 1 and #created == 0)
reset(); create_ok = false
result = train()
assert(result.ok == false and result.error == "worker_create_failed" and #calls == 3)
assert(calls[1].event == events.RESOURCE_TRY_SPEND_REQUEST)
assert(calls[2].event == events.RESOURCE_ADD_REQUEST and calls[2].payload.wood == 100 and calls[2].payload.gold == 20)
assert(calls[3].event == events.RESOURCE_RELEASE_POP_REQUEST and calls[3].payload.population == 1)

-- Population upgrades do not spawn a unit and must not require a landing spot.
reset(); state.building_id = "farm"; traversable = false
result = train({training_id = "train_population_auto"})
assert(result.ok and result.population_add == 5 and checks == 0 and #created == 0)
assert(#calls == 2 and calls[2].payload.max_population == 5)

-- Reward batches share the same early rejection; a nil destination is never used.
reset(); traversable = false
result = train({source = "rogue_reward", count = 2, wood_cost_override = 0, gold_cost_override = 0})
assert(result.ok == false and #calls == 0 and #created == 0 and checks == 24)

-- Preserve batch rollback if a later free reward cannot find space.
reset(); traversable = function() return #created == 0 end
result = train({source = "rogue_reward", count = 2, wood_cost_override = 0, gold_cost_override = 0})
assert(result.ok == false and #created == 1 and units[101].killed)
assert(#calls == 2 and calls[1].event == events.RESOURCE_TRY_SPEND_REQUEST)
assert(calls[1].payload.wood == 0 and calls[1].payload.gold == 0)
assert(calls[2].event == events.RESOURCE_RELEASE_POP_REQUEST and calls[2].payload.population == 1)

print("PASS worker spawn safety: water/shore/height clearance, blocked/occupied/unavailable land, safe retry, spending, refunds, population and batch rollback")
