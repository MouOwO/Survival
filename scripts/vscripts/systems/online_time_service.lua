local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local rules = require("config/generated/fishing_system_rules")
local profile_service = require("systems/player_profile_service")
local production_definitions = require("config/generated/star_blessing_reward_definitions")

local M = {}
local sessions = {}
local generation = 0

local function runtime_id()
    local parts = {}
    if os and type(os.time) == "function" then
        parts[#parts + 1] = tostring(os.time())
    elseif type(GetSystemDate) == "function" and type(GetSystemTime) == "function" then
        parts[#parts + 1] = tostring(GetSystemDate()) .. tostring(GetSystemTime())
    end
    if type(RandomInt) == "function" then
        for _ = 1, 4 do
            parts[#parts + 1] = string.format("%08x", RandomInt(0, 2147483647))
        end
    end
    parts[#parts + 1] = tostring({})
    return string.gsub(table.concat(parts), "[^0-9A-Za-z]", "")
end

local runtime_nonce = runtime_id()
local task_id = "online_time_checkpoint"
local debug_command_registered = false
local checkpoint

local function convar(name)
    if not Convars or type(Convars.GetStr) ~= "function" then return "" end
    return tostring(Convars:GetStr(name) or "")
end

local function active_definitions()
    local tools_mode = type(IsInToolsMode) == "function" and IsInToolsMode()
    local fixture = ""
    if tools_mode and Convars and type(Convars.GetStr) == "function" then
        fixture = tostring(Convars:GetStr("survival_fishing_reward_fixture") or "")
    end
    if tools_mode and fixture == "automation_9001" then
        return require("tests/generated_fishing_reward_definitions")
    end
    return production_definitions
end

local function validated_grant(grant)
    local reward_id = tostring(grant and grant.reward_id or "")
    local definition_version = tonumber(grant and grant.definition_version)
    local amount = tonumber(grant and grant.amount)
    local grant_id = tostring(grant and grant.grant_id or "")
    local row = active_definitions().by_id[reward_id]
    if not row then
        return nil, "reward_missing"
    end
    if row.enabled ~= true then
        return nil, "reward_disabled"
    end
    if row.effect_scope ~= "permanent" then
        return nil, "scope_mismatch"
    end
    if tonumber(row.definition_version) ~= definition_version then
        return nil, "definition_version_mismatch"
    end
    if amount == nil then
        return nil, "amount_missing"
    end
    if amount < tonumber(row.value_min) then
        return nil, "amount_below_min"
    end
    if amount > tonumber(row.value_max) then
        return nil, "amount_above_max"
    end
    if grant_id == "" then
        return nil, "grant_id_missing"
    end
    return {
        grant_id = grant_id,
        reward_id = reward_id,
        amount = amount,
        definition_version = definition_version,
    }
end

local function complete_checkpoint(player_id, state, final)
    state.in_flight = false
    if final then
        sessions[player_id] = nil
        return
    end
    if state.final_requested then
        state.final_requested = false
        checkpoint(player_id, true)
    end
end

local function publish_grants(player_id, state, grants, final)
    print("[OnlineTime] profile_refresh_started player_id=" .. tostring(player_id)
        .. " grant_count=" .. tostring(#grants))
    profile_service.load_player(player_id, "star_blessing_grant", function()
        local permanent_effects = require("systems/permanent_reward_effect_service")
        print("[OnlineTime] profile_refresh_completed player_id=" .. tostring(player_id)
            .. " hero_all_attributes_flat="
            .. tostring(permanent_effects.value(player_id, "hero_all_attributes_flat")))
        for _, grant in ipairs(grants) do
            if grant.grant_id ~= "" and not state.grants[grant.grant_id] then
                state.grants[grant.grant_id] = true
                grant.player_id = player_id
                event_bus.emit(events.FISHING_REWARD_GRANTED, grant)
                print("[OnlineTime] grant_published player_id=" .. tostring(player_id)
                    .. " reward_id=" .. tostring(grant.reward_id)
                    .. " amount=" .. tostring(grant.amount))
            end
        end
        complete_checkpoint(player_id, state, final)
    end, function(error_code)
        print("[OnlineTime] profile_refresh_failed player_id=" .. tostring(player_id)
            .. " error=" .. tostring(error_code))
        complete_checkpoint(player_id, state, final)
    end)
end

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

checkpoint = function(player_id, final)
    local state = sessions[player_id]
    if not state then return end
    if state.in_flight then
        if final then state.final_requested = true end
        return
    end
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
    provider.online_checkpoint(payload, function(response)
        state.last_success = GameRules:GetGameTime()
        local grants = {}
        local raw_grants = response and response.grants or {}
        for _, grant in ipairs(response and response.grants or {}) do
            local value, rejection_reason = validated_grant(grant)
            if value then
                table.insert(grants, value)
            else
                print("[OnlineTime] grant_rejected player_id=" .. tostring(player_id)
                    .. " reason=" .. tostring(rejection_reason)
                    .. " reward_id=" .. tostring(grant and grant.reward_id or "")
                    .. " definition_version="
                    .. tostring(grant and grant.definition_version or "")
                    .. " amount=" .. tostring(grant and grant.amount or ""))
            end
        end
        print("[OnlineTime] checkpoint_response player_id=" .. tostring(player_id)
            .. " elapsed_seconds=" .. tostring(response and response.elapsed_seconds)
            .. " online_seconds_total=" .. tostring(response and response.online_seconds_total)
            .. " grant_count=" .. tostring(#raw_grants)
            .. " validated_grant_count=" .. tostring(#grants))
        if #grants > 0 then
            publish_grants(player_id, state, grants, final)
            return
        end
        complete_checkpoint(player_id, state, final)
    end, function(error_code)
        print("[OnlineTime] checkpoint_failed player_id=" .. tostring(player_id)
            .. " error=" .. tostring(error_code))
        complete_checkpoint(player_id, state, final)
    end)
end

local function debug_checkpoint(_, player_id)
    if type(IsInToolsMode) ~= "function" or not IsInToolsMode() then
        print("[OnlineTime] debug_checkpoint_rejected reason=tools_mode_required")
        return
    end
    local fixture = convar("survival_fishing_reward_fixture")
    if fixture ~= "automation_9001" and fixture ~= "production_60s" then
        print("[OnlineTime] debug_checkpoint_rejected reason=tools_reward_fixture_required")
        return
    end
    if convar("survival_player_profile_provider") ~= "http_fishing" then
        print("[OnlineTime] debug_checkpoint_rejected reason=http_fishing_required")
        return
    end
    player_id = tonumber(player_id) or 0
    if not sessions[player_id] then
        print("[OnlineTime] debug_checkpoint_rejected reason=session_missing player_id="
            .. tostring(player_id))
        return
    end
    if sessions[player_id].in_flight then
        print("[OnlineTime] debug_checkpoint_rejected reason=request_in_flight player_id="
            .. tostring(player_id))
        return
    end
    print("[OnlineTime] debug_checkpoint_requested player_id=" .. tostring(player_id))
    checkpoint(player_id, false)
end

local function start(player_id)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then return end
    local current = sessions[player_id]
    if current then return end
    local next_generation = generation
    sessions[player_id] = {
        session_id = string.format("game-%s-%d-player-%d", runtime_nonce,
            next_generation, player_id),
        sequence = 0,
        in_flight = false,
        final_requested = false,
        grants = {},
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
    if not debug_command_registered and Convars
        and type(Convars.RegisterCommand) == "function" then
        Convars:RegisterCommand(
            "survival_online_checkpoint_now",
            debug_checkpoint,
            "Run the Automation9001 online checkpoint for a player",
            FCVAR_CHEAT
        )
        debug_command_registered = true
    end
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

M._test = {
    debug_checkpoint = debug_checkpoint,
    validated_grant = validated_grant,
}

return M