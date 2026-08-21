local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local rules = require("config/generated/fishing_system_rules")
local profile_service = require("systems/player_profile_service")

local M = {}
local sessions = {}
local generation = 0
local task_id = "online_time_checkpoint"

local function rule()
    for _, row in ipairs(rules.rows or {}) do
        if row.enabled ~= false then return row end
    end
    return nil
end

local function request_id(player_id, state)
    state.sequence = state.sequence + 1
    return string.format("online-%s-%s-%d", tostring(player_id), state.session_id, state.sequence)
end

local function checkpoint(player_id, final)
    local state = sessions[player_id]
    if not state or state.in_flight then return end
    local provider = profile_service.get_provider()
    if not provider or type(provider.online_checkpoint) ~= "function" then return end
    local account_id = provider.resolve_account_id(player_id)
    if not account_id then return end
    state.in_flight = true
    local payload = {
        account_id = tostring(account_id),
        session_id = state.session_id,
        request_id = request_id(player_id, state),
        final = final == true,
    }
    provider.online_checkpoint(payload, function()
        state.in_flight = false
        state.last_success = GameRules:GetGameTime()
        if final then sessions[player_id] = nil end
    end, function(error_code)
        state.in_flight = false
        print("[OnlineTime] checkpoint_failed player_id=" .. tostring(player_id)
            .. " error=" .. tostring(error_code))
        if final then sessions[player_id] = nil end
    end)
end

local function start(player_id)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then return end
    local current = sessions[player_id]
    if current then return end
    local next_generation = generation
    sessions[player_id] = {
        session_id = string.format("game-%d-player-%d", next_generation, player_id),
        sequence = 0,
        in_flight = false,
    }
    checkpoint(player_id, false)
end

function M.init()
    generation = generation + 1
    sessions = {}
    local active_rule = rule()
    if not active_rule then return end
    local interval = math.max(5, tonumber(active_rule.online_time_checkpoint_interval_seconds) or 60)
    scheduler.every(interval, function()
        for player_id in pairs(sessions) do checkpoint(player_id, false) end
    end, task_id)
    event_bus.subscribe(events.HERO_READY, function(payload) start(payload.player_id) end)
    event_bus.subscribe(events.GAME_STARTED, function()
        for player_id in pairs(sessions) do checkpoint(player_id, false) end
    end)
end

function M.disconnect(player_id)
    player_id = tonumber(player_id)
    if sessions[player_id] then
        checkpoint(player_id, true)
    end
end

function M.finish()
    for player_id in pairs(sessions) do checkpoint(player_id, true) end
end

return M