local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local config = require("config/resources_config")

local M = {}
local accounts = {}
local version = 0

local function normalized_player_id(value)
    value = tonumber(value)
    if value == nil or value < 0 then return nil end
    return math.floor(value)
end

local function gameplay_stats(player_id)
    local profile = require("systems/player_profile_service").get_profile(player_id)
    return profile and profile.save and profile.save.gameplay_stats or nil
end

local function new_account()
    return {
        wood = config.initial_wood,
        gold = config.initial_gold,
        population = config.initial_population,
        max_population = config.initial_max_population,
        wood_per_second = 0,
        gold_per_second = 0,
        wood_fraction = 0,
        gold_fraction = 0,
        debug_mode = false,
        initialized = false,
    }
end

local function get_account(player_id)
    player_id = normalized_player_id(player_id)
    if player_id == nil then return nil end
    if not accounts[player_id] then accounts[player_id] = new_account() end
    return accounts[player_id]
end

local function snapshot(player_id)
    local account = get_account(player_id)
    if not account or not account.initialized then return nil end
    return {
        player_id = player_id,
        team = account.team,
        wood = account.wood,
        gold = account.gold,
        population = account.population,
        max_population = account.max_population,
        version = version,
    }
end

local function publish(player_id, reason)
    local data = snapshot(player_id)
    if not data then return false end
    version = version + 1
    data.version = version
    data.reason = reason or "unknown"
    event_bus.emit(events.RESOURCE_CHANGED, data)
    return true
end

local function start_income_task(player_id, account)
    local task_id = "resource_income:" .. tostring(player_id)
    scheduler.cancel(task_id)
    scheduler.every(1, function()
        if accounts[player_id] ~= account or not account.initialized then return false end
        local wood_exact = account.wood_per_second + account.wood_fraction
        local gold_exact = account.gold_per_second + account.gold_fraction
        local wood = math.floor(wood_exact)
        local gold = math.floor(gold_exact)
        account.wood_fraction = wood_exact - wood
        account.gold_fraction = gold_exact - gold
        if wood > 0 or gold > 0 then
            account.wood = account.wood + wood
            account.gold = account.gold + gold
            publish(player_id, "profile_income")
        end
        return true
    end, task_id)
end

local function initialize_from_profile(payload)
    local player_id = normalized_player_id(payload and payload.player_id)
    if player_id == nil then return false end
    local account = get_account(player_id)
    if account.initialized then return true end
    local stats = gameplay_stats(player_id)
    if not stats then return false end
    account.team = PlayerResource and PlayerResource.GetTeam
        and PlayerResource:GetTeam(player_id) or nil
    account.wood = math.max(0, tonumber(stats.initial_wood) or config.initial_wood)
    account.gold = math.max(0, tonumber(stats.initial_gold) or config.initial_gold)
    account.max_population = math.max(0,
        tonumber(stats.initial_population_cap) or config.initial_max_population)
    account.wood_per_second = math.max(0, tonumber(stats.wood_per_second) or 0)
    account.gold_per_second = math.max(0, tonumber(stats.gold_per_second) or 0)
    account.initialized = true
    start_income_task(player_id, account)
    publish(player_id, "profile_initialized")
    return true
end

local function require_account(payload)
    local player_id = normalized_player_id(payload and payload.player_id)
    if player_id == nil then return nil, nil, "player_id_invalid" end
    local account = get_account(player_id)
    if not account.initialized then return nil, player_id, "profile_not_loaded" end
    return account, player_id, nil
end

local function handle_get(payload)
    local account, player_id, error_code = require_account(payload)
    if not account then
        return { ok = false, error = error_code, player_id = player_id,
            wood = 0, gold = 0, population = 0, max_population = 0, version = version }
    end
    return snapshot(player_id)
end

local function handle_spend(payload)
    local account, player_id, error_code = require_account(payload)
    if not account then return { ok = false, error = error_code } end
    local wood = math.max(0, tonumber(payload.wood) or 0)
    local gold = math.max(0, tonumber(payload.gold) or 0)
    local population = math.max(0, tonumber(payload.population) or 0)
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
    publish(player_id, payload.reason or "spend")
    return { ok = true, snapshot = snapshot(player_id) }
end

local function handle_add(payload)
    local account, player_id, error_code = require_account(payload)
    if not account then return { ok = false, error = error_code } end
    account.wood = math.max(0, account.wood + (tonumber(payload.wood) or 0))
    account.gold = math.max(0, account.gold + (tonumber(payload.gold) or 0))
    account.max_population = math.max(0,
        account.max_population + (tonumber(payload.max_population) or 0))
    publish(player_id, payload.reason or "add")
    return { ok = true, snapshot = snapshot(player_id) }
end

local function handle_debug_set(payload)
    local account, player_id, error_code = require_account(payload)
    if not account then return { ok = false, error = error_code } end
    local amount = math.max(0, tonumber(payload.amount) or 100000000)
    account.wood = amount
    account.gold = amount
    account.population = amount
    account.max_population = amount
    account.debug_mode = true
    publish(player_id, payload.reason or "debug_set")
    return { ok = true, snapshot = snapshot(player_id) }
end

local function handle_release_pop(payload)
    local account, player_id, error_code = require_account(payload)
    if not account then return { ok = false, error = error_code } end
    account.population = math.max(0,
        account.population - math.max(0, tonumber(payload.population) or 0))
    publish(player_id, payload.reason or "release_population")
    return { ok = true, snapshot = snapshot(player_id) }
end

function M.init()
    accounts = {}
    version = 0
    event_bus.handle_request(events.RESOURCE_GET_REQUEST, handle_get)
    event_bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, handle_spend)
    event_bus.handle_request(events.RESOURCE_ADD_REQUEST, handle_add)
    event_bus.handle_request(events.RESOURCE_RELEASE_POP_REQUEST, handle_release_pop)
    event_bus.handle_request(events.RESOURCE_DEBUG_SET_REQUEST, handle_debug_set)
    event_bus.subscribe(events.PLAYER_PROFILE_CHANGED, initialize_from_profile)
end

M._test = {
    initialize_from_profile = initialize_from_profile,
    accounts = function() return accounts end,
}

return M