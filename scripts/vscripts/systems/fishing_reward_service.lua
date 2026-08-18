local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local provider = require("systems/player_profile_providers/http_fishing_provider")
local production_reward_definitions = require("config/generated/fishing_reward_definitions")
local json_null = require("core/json_decoder").null

local M = {}
local sessions = {}
local sequence = 0
local runtime_nonce = "uninitialized"

local function active_reward_definitions()
    local tools_mode = type(IsInToolsMode) == "function" and IsInToolsMode()
    local fixture = ""
    if tools_mode and Convars and type(Convars.GetStr) == "function" then
        fixture = tostring(Convars:GetStr("survival_fishing_reward_fixture") or "")
    end
    if tools_mode and fixture == "automation_9001" then
        return require("tests/generated_fishing_reward_definitions")
    end
    return production_reward_definitions
end

local function reward_definition(grant)
    local reward_id = tostring(grant and grant.reward_id or "")
    local definition_version = tonumber(grant and grant.definition_version)
    for _, row in ipairs(active_reward_definitions().rows or {}) do
        if tostring(row.reward_id or "") == reward_id
            and tonumber(row.definition_version) == definition_version
            and row.enabled == true then
            return row
        end
    end
    return nil
end

local function player_name(player_id)
    if PlayerResource and type(PlayerResource.GetPlayerName) == "function" then
        local value = tostring(PlayerResource:GetPlayerName(player_id) or "")
        value = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if value ~= "" then return value end
    end
    return "玩家" .. tostring(player_id)
end

local function amount_text(amount)
    amount = tonumber(amount) or 0
    if amount == math.floor(amount) then return string.format("%.0f", amount) end
    return tostring(amount)
end

local function announce_grant(payload)
    local definition = reward_definition(payload)
    local player_id = tonumber(payload and payload.player_id)
    if not definition or player_id == nil then return end
    event_bus.emit(events.UI_NOTIFICATION, {
        audience = "all",
        message = player_name(player_id) .. " 钓到了："
            .. tostring(definition.display_name) .. "（"
            .. amount_text(payload.amount) .. "）",
        level = "info",
    })
end

local function provider_enabled()
    if not Convars or type(Convars.GetStr) ~= "function" then return false end
    return tostring(Convars:GetStr("survival_player_profile_provider") or "")
        == "http_fishing"
end

local function fresh_nonce()
    if type(DoUniqueString) == "function" then
        return tostring(DoUniqueString("fishing"))
    end
    return tostring({}):gsub("[^A-Za-z0-9]", "")
end

local function next_id(prefix, player_id)
    sequence = sequence + 1
    local match_id = GameRules and GameRules.Script_GetMatchID
        and GameRules:Script_GetMatchID() or 0
    return table.concat({ prefix, runtime_nonce, tostring(match_id), tostring(player_id),
        tostring(sequence) }, ":")
end

local function connected(player_id)
    if PlayerResource and type(PlayerResource.GetConnectionState) == "function"
        and DOTA_CONNECTION_STATE_CONNECTED ~= nil then
        return PlayerResource:GetConnectionState(player_id)
            == DOTA_CONNECTION_STATE_CONNECTED
    end
    return true
end

local function apply_grant(state, grant)
    if type(grant) ~= "table" or grant == json_null then
        return true
    end
    local grant_id = tostring(grant.grant_id or "")
    if grant_id == "" then return false, "grant_id_missing" end
    if state.applied_grants[grant_id] then return true end
    local definition = reward_definition(grant)
    if not definition then return false, "reward_definition_missing" end
    if tostring(grant.effect_key or "") ~= tostring(definition.effect_key)
        or tostring(grant.effect_scope or "") ~= tostring(definition.effect_scope) then
        return false, "reward_definition_mismatch"
    end
    local amount = tonumber(grant.amount)
    if not amount or amount ~= math.floor(amount)
        or amount < (tonumber(definition.value_min) or amount)
        or amount > (tonumber(definition.value_max) or amount) then
        return false, "reward_amount_invalid"
    end
    local amounts = {}
    local key = tostring(grant.effect_key or "")
    if tostring(grant.effect_scope) == "permanent" then
        local projection = event_bus.request(
            events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
            { player_id = state.player_id }
        )
        if not projection or projection.ok ~= true
            or type(projection.totals) ~= "table"
            or projection.totals[key] == nil then
            return false, "permanent_effect_not_projected"
        end
    elseif key == "immediate_gold" then amounts.gold = amount
    elseif key == "immediate_wood" then amounts.wood = amount
    elseif key == "immediate_max_population" then
        amounts.max_population = amount
    else
        return false, "immediate_effect_unsupported:" .. key
    end
    if tostring(grant.effect_scope) == "immediate" then
        amounts.player_id = state.player_id
        amounts.team = state.team
        amounts.reason = "fishing_reward:" .. grant_id
        local result = event_bus.request(events.RESOURCE_ADD_REQUEST, amounts)
        if not result or result.ok ~= true then return false, "resource_apply_failed" end
    end
    state.applied_grants[grant_id] = true
    event_bus.emit(events.FISHING_REWARD_GRANTED, {
        player_id = state.player_id,
        grant_id = grant_id,
        reward_id = tostring(definition.reward_id),
        definition_version = tonumber(definition.definition_version),
        effect_key = tostring(definition.effect_key),
        effect_scope = tostring(definition.effect_scope),
        amount = amount,
    })
    return true
end

local function heartbeat(state)
    if state.in_flight or sessions[state.player_id] ~= state then return end
    if not connected(state.player_id) then
        M.disconnect(state.player_id)
        return
    end
    local profile = require("systems/player_profile_service").get_profile(state.player_id)
    if not profile or profile.account_id ~= state.account_id then return end
    state.pending_request_id = state.pending_request_id
        or next_id("heartbeat", state.player_id)
    state.in_flight = true
    provider.heartbeat({
        account_id = state.account_id,
        session_id = state.session_id,
        request_id = state.pending_request_id,
    }, function(response)
        state.in_flight = false
        if sessions[state.player_id] ~= state then return end
        local applied = require("systems/player_profile_service").apply_snapshot(
            state.player_id, response.profile, "fishing_heartbeat"
        )
        if not applied or applied.ok ~= true then return end
        local ok, reason = apply_grant(state, response.grant)
        if not ok then
            print("[FishingReward] grant apply failed: " .. tostring(reason))
            return
        end
        state.pending_request_id = nil
    end, function(reason)
        state.in_flight = false
        print("[FishingReward] heartbeat failed: " .. tostring(reason))
    end)
end

local function start(payload)
    if not provider_enabled() then return end
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then return end
    local profile = require("systems/player_profile_service").get_profile(player_id)
    if not profile then return end
    local existing = sessions[player_id]
    if existing and existing.account_id == profile.account_id then return end
    local rule = provider.rule()
    if not rule then return end
    local state = {
        player_id = player_id,
        team = tonumber(payload.team) or PlayerResource:GetTeam(player_id),
        account_id = profile.account_id,
        session_id = next_id("session", player_id),
        applied_grants = {},
        in_flight = false,
    }
    sessions[player_id] = state
    heartbeat(state)
    scheduler.every(tonumber(rule.heartbeat_interval_seconds) or 5, function()
        if sessions[player_id] ~= state then return false end
        heartbeat(state)
    end, "fishing_heartbeat_" .. tostring(player_id))
end

function M.disconnect(player_id)
    player_id = tonumber(player_id)
    sessions[player_id] = nil
    scheduler.cancel("fishing_heartbeat_" .. tostring(player_id))
end

function M.connect(player_id)
    start({ player_id = player_id })
end

function M.init()
    sessions = {}
    sequence = 0
    runtime_nonce = fresh_nonce()
    provider.init()
    event_bus.subscribe(events.FISHING_REWARD_GRANTED, announce_grant)
    event_bus.subscribe(events.HERO_READY, start)
    event_bus.subscribe(events.PLAYER_PROFILE_CHANGED, start)
end

M._test = {
    apply_grant = apply_grant,
    announce_grant = announce_grant,
    connected = connected,
}

return M