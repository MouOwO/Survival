local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/resources_config")

local M = {}
local accounts = {}
local version = 0

local function new_account()
    return {
        wood = config.initial_wood,
        gold = config.initial_gold,
        population = config.initial_population,
        max_population = config.initial_max_population,
        debug_mode = false,
    }
end

local function get_account(team)
    if not accounts[team] then
        accounts[team] = new_account()
    end
    return accounts[team]
end

local function snapshot(team)
    local account = get_account(team)
    return {
        team = team,
        wood = account.wood,
        gold = account.gold,
        population = account.population,
        max_population = account.max_population,
        version = version,
    }
end

local function publish(team, reason)
    version = version + 1
    local data = snapshot(team)
    data.version = version
    data.reason = reason or "unknown"
    event_bus.emit(events.RESOURCE_CHANGED, data)
end

local function handle_get(payload)
    return snapshot(payload.team)
end

local function handle_spend(payload)
    local account = get_account(payload.team)
    local wood = math.max(0, payload.wood or 0)
    local gold = math.max(0, payload.gold or 0)
    local population = math.max(0, payload.population or 0)

    if not account.debug_mode then
        if account.wood < wood then return { ok = false, error = "wood_not_enough" } end
        if account.gold < gold then return { ok = false, error = "gold_not_enough" } end
        if account.population + population > account.max_population then
            return { ok = false, error = "population_not_enough" }
        end
        account.wood = account.wood - wood
        account.gold = account.gold - gold
        account.population = account.population + population
    end
    publish(payload.team, payload.reason or "spend")
    return { ok = true, snapshot = snapshot(payload.team) }
end

local function handle_add(payload)
    local account = get_account(payload.team)
    account.wood = math.max(0, account.wood + (payload.wood or 0))
    account.gold = math.max(0, account.gold + (payload.gold or 0))
    account.max_population = math.max(0, account.max_population + (payload.max_population or 0))
    publish(payload.team, payload.reason or "add")
    return { ok = true, snapshot = snapshot(payload.team) }
end

local function handle_debug_set(payload)
    local account = get_account(payload.team)
    local amount = math.max(0, tonumber(payload.amount) or 100000000)
    account.wood = amount
    account.gold = amount
    account.population = amount
    account.max_population = amount
    account.debug_mode = true
    publish(payload.team, payload.reason or "debug_set")
    return { ok = true, snapshot = snapshot(payload.team) }
end

local function handle_release_pop(payload)
    local account = get_account(payload.team)
    account.population = math.max(0, account.population - math.max(0, payload.population or 0))
    publish(payload.team, payload.reason or "release_population")
    return { ok = true, snapshot = snapshot(payload.team) }
end

function M.init()
    accounts = {}
    version = 0
    event_bus.handle_request(events.RESOURCE_GET_REQUEST, handle_get)
    event_bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, handle_spend)
    event_bus.handle_request(events.RESOURCE_ADD_REQUEST, handle_add)
    event_bus.handle_request(events.RESOURCE_RELEASE_POP_REQUEST, handle_release_pop)
    event_bus.handle_request(events.RESOURCE_DEBUG_SET_REQUEST, handle_debug_set)

    get_account(DOTA_TEAM_GOODGUYS)
    get_account(DOTA_TEAM_BADGUYS)
    publish(DOTA_TEAM_GOODGUYS, "initial")
    publish(DOTA_TEAM_BADGUYS, "initial")
end

return M
