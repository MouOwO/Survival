-- Explicit server-only entry transition. Loading this module does nothing.
-- It never authenticates, loads saves, sends HTTP, or changes payment policy.
local M = {}
local REVISION = "WS4-NATIVE-HANDOFF-01"
local LATCH = "__survival_native_cloud_handoff_01"
local COMMAND = "changelevel template_map gamemode=15 customgamemode=3824360109 nomapvalidation=1"
local MAP, CAPACITY, INTERVAL, STABLE_SECONDS, MAX_SECONDS = "ws4_entry", 4, 0.1, 1, 120
local ROSTER = {"76561198424163156", "76561198845461206", "76561198104787442", "76561198974301984"}
local ACCOUNTS = {['463897428'] = true, ['885195478'] = true, ['144521714'] = true, ['1014036256'] = true}
local RESOURCE_APIS = {"GetPlayerCount", "IsValidPlayerID", "IsFakeClient", "GetTeam", "GetPlayer", "GetConnectionState", "GetSteamAccountID"}

local function method(object, name)
    local ok, value = pcall(function() return object and object[name] end)
    return ok and type(value) == "function" and value or nil
end
local function call(object, name, ...)
    local fn = method(object, name)
    if not fn then return nil, false end
    local ok, value = pcall(fn, object, ...)
    return value, ok
end
local function clock()
    if type(Time) ~= "function" then return nil end
    local ok, value = pcall(Time)
    if ok and type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
end
local function integer(value, low, high)
    return type(value) == "number" and value == value and value >= low and value <= high and value == math.floor(value)
end
local function native_phase()
    local setup = rawget(_G, "DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP")
    local post_game = rawget(_G, "DOTA_GAMERULES_STATE_POST_GAME")
    if not integer(setup, 0, 255) or not integer(post_game, setup + 1, 255)
        or not method(GameRules, "State_Get") then return nil, "native_phase_api_unavailable" end
    local state, ok = call(GameRules, "State_Get")
    if not ok or not integer(state, 0, 255) then return nil, "native_state_invalid" end
    if state >= post_game then return nil, "native_game_finished" end
    if state < setup then return false, "waiting_native_load" end
    return true
end
local function environment()
    local ok, allowed = pcall(function()
        return IsServer() == true and IsClient() == false and IsInToolsMode() == false and GetMapName() == MAP
    end)
    if not ok or not allowed then return false, "entry_server_required" end
    local value, found
    if method(Convars, "GetInt") then value, found = call(Convars, "GetInt", "sv_cheats"); found = found and value == 0
    elseif method(Convars, "GetBool") then value, found = call(Convars, "GetBool", "sv_cheats"); found = found and value == false
    elseif method(Convars, "GetStr") then value, found = call(Convars, "GetStr", "sv_cheats"); found = found and value == "0" end
    if not found then return false, "cheats_must_be_disabled" end
    local configured, access = pcall(function()
        local release = require("config/release_profile")
        local config = require("config/test_access")
        local rules = require("config/generated/multiplayer_rules")
        local policy = require("core/test_access_policy")
        if type(release) ~= "table" or release.channel ~= "production" or type(config) ~= "table" or config.enabled ~= true
            or type(config.allowed_steamids) ~= "table" or type(rules) ~= "table" or type(rules.by_id) ~= "table"
            or type(rules.by_id.default_multiplayer) ~= "table" or rules.by_id.default_multiplayer.max_players ~= CAPACITY then return nil end
        local count = 0
        for index, steam in pairs(config.allowed_steamids) do
            if not integer(index, 1, CAPACITY) or steam ~= ROSTER[index] then return nil end
            count = count + 1
        end
        if count ~= CAPACITY or type(policy) ~= "table" or type(policy.enabled) ~= "function"
            or type(policy.init) ~= "function" or type(policy.allowed) ~= "function"
            or policy.enabled() ~= true or policy.init() ~= true then return nil end
        return policy
    end)
    if not configured or not access then return false, "restricted_production_configuration_required" end
    return true, access
end
local function current_world()
    local mode, ok = call(GameRules, "GetGameModeEntity")
    return ok and mode or nil
end
local function emit(run)
    -- Fixed status/counts only; no Steam identities, lobby nonces, credentials
    -- or caller-supplied text reaches the console.
    pcall(print, "[" .. REVISION .. "] status=" .. run.status .. " players=" .. tostring(run.count or 0)
        .. " expected=" .. tostring(run.expected or 0))
end
local function stop(run, reason)
    if not run.live then return end
    run.live, run.status, run.stable_since, run.roster = false, reason, nil, nil
    emit(run)
end
local function waiting(run, status, count, expected)
    run.status, run.count, run.expected = status, count or 0, expected or 0
    run.stable_since, run.roster = nil, nil
    return INTERVAL
end
local function registered_count(run)
    -- Native GetPlayerCount includes unassigned/loading resource slots. A
    -- connected-human/team count would silently omit a slow unassigned guest.
    local count, ok = call(PlayerResource, "GetPlayerCount")
    if not ok or not integer(count, 0, CAPACITY) then return nil, "registered_roster_count_invalid" end
    run.expected_floor = math.max(run.expected_floor or 0, count)
    return count
end
local function roster(access, run)
    local expected, count_reason = registered_count(run)
    if expected == nil then return nil, count_reason, true end
    local required = run.expected_floor
    local rows, seen, pending = {}, {}, false
    for id = 0, 23 do
        local valid, valid_ok = call(PlayerResource, "IsValidPlayerID", id)
        if not valid_ok or type(valid) ~= "boolean" then return nil, "player_api_failed", true end
        if valid then
            local fake, fake_ok = call(PlayerResource, "IsFakeClient", id)
            local team, team_ok = call(PlayerResource, "GetTeam", id)
            if not fake_ok or type(fake) ~= "boolean" or not team_ok then return nil, "player_api_failed", true end
            if fake or team == (DOTA_TEAM_SPECTATOR or 1) then return nil, "nonhuman_or_spectator_roster", true end
            local player, player_ok = call(PlayerResource, "GetPlayer", id)
            local connection, connection_ok = call(PlayerResource, "GetConnectionState", id)
            local account, account_ok = call(PlayerResource, "GetSteamAccountID", id)
            if not player_ok or not connection_ok or not account_ok then return nil, "player_api_failed", true end
            if player == nil or connection ~= (DOTA_CONNECTION_STATE_CONNECTED or 2) or account == 0 or team == nil then
                pending = true
            else
                if not integer(account, 1, 4294967295) then return nil, "account_invalid", true end
                local decimal = string.format("%.0f", account)
                if not ACCOUNTS[decimal] then return nil, "account_not_allowed", true end
                if seen[decimal] then return nil, "duplicate_account", true end
                seen[decimal] = true
                local player_id, player_id_ok = call(player, "GetPlayerID")
                local is_null, is_null_ok = call(player, "IsNull")
                if not player_id_ok or player_id ~= id or not is_null_ok or is_null ~= false then return nil, "player_binding_invalid", true end
                local allowed, admitted = pcall(access.allowed, id)
                if not allowed or admitted ~= true then return nil, "test_access_denied", true end
            end
            rows[#rows + 1] = {id = id, player = player, account = account, team = team, connection = connection}
        end
    end
    if #rows > CAPACITY then return nil, "roster_over_capacity", true end
    if required == 0 or #rows == 0 then return nil, "waiting_roster", false, #rows, required end
    if expected ~= required or required ~= #rows then return nil, "waiting_complete_roster", false, #rows, required end
    if pending then return nil, "waiting_connected_roster", false, #rows, required end
    return rows, nil, false, #rows, required
end
local function same_roster(first, second)
    if not first or not second or #first ~= #second then return false end
    for index, row in ipairs(first) do
        local other = second[index]
        if row.id ~= other.id or row.player ~= other.player or row.account ~= other.account
            or row.team ~= other.team or row.connection ~= other.connection then return false end
    end
    return true
end
local function tick(run)
    if not run.live or rawget(_G, LATCH) ~= run then return nil end
    run.ticks = run.ticks + 1
    local now = clock()
    if not now or now < run.last_clock or now - run.started >= MAX_SECONDS or run.ticks > MAX_SECONDS / INTERVAL + 1 then
        stop(run, "handoff_timeout_or_clock_invalid"); return nil
    end
    run.last_clock = now
    if current_world() ~= run.mode then stop(run, "context_changed"); return nil end
    local permitted, access = environment()
    if not permitted then stop(run, access); return nil end
    local phase_ready, phase_reason = native_phase()
    if phase_ready == nil then stop(run, phase_reason); return nil end
    if not phase_ready then
        -- Retain the native registered-party size observed while the engine
        -- waits for its GC lobby to finish loading. A disappearing participant
        -- cannot shrink the barrier and turn the same party into a solo game.
        local registered, count_reason = registered_count(run)
        if registered == nil then stop(run, count_reason); return nil end
        return waiting(run, phase_reason, 0, run.expected_floor)
    end
    local rows, reason, fatal, count, expected = roster(access, run)
    if not rows then
        if fatal then stop(run, reason); return nil end
        return waiting(run, reason, count, expected)
    end
    run.count, run.expected = count, expected
    if not same_roster(run.roster, rows) then run.roster, run.stable_since = rows, now end
    run.status = "waiting_stable_roster"
    if now - run.stable_since < STABLE_SECONDS then return INTERVAL end
    -- Recheck the whole roster and policy at the commit boundary. A late
    -- arrival/disconnect or account/entity replacement cannot launch half a
    -- party using the previous stable observation.
    local still_allowed, current_access = environment()
    if not still_allowed then stop(run, current_access); return nil end
    local final, final_reason, final_fatal, final_count, final_expected = roster(current_access, run)
    if not final then
        if final_fatal then stop(run, final_reason); return nil end
        return waiting(run, final_reason, final_count, final_expected)
    end
    if not same_roster(rows, final) then return waiting(run, "roster_changed_before_handoff", final_count, final_expected) end
    local final_phase_ready, final_phase_reason = native_phase()
    if final_phase_ready == nil then stop(run, final_phase_reason); return nil end
    if not final_phase_ready then return waiting(run, final_phase_reason, final_count, final_expected) end
    local checked = clock()
    if current_world() ~= run.mode or not checked or checked < now or checked - run.started >= MAX_SECONDS then
        stop(run, "context_or_clock_changed"); return nil
    end
    run.handoff_attempted, run.live = true, false -- consume before an ambiguous engine call
    -- Only the final server-observed, authenticated-by-engine account32 roster
    -- crosses the level boundary. It is a readiness requirement, not a login
    -- credential or a payment capability; target PWA identity remains separate.
    local accounts = {}
    for _, row in ipairs(final) do accounts[#accounts + 1] = row.account end
    table.sort(accounts)
    for index, account in ipairs(accounts) do accounts[index] = string.format("%.0f", account) end
    local sent, accepted = pcall(SendToServerConsole, COMMAND .. " ws4_native_roster=" .. table.concat(accounts, "_"))
    run.status = sent and accepted ~= false and "handoff_queued" or "handoff_send_failed"
    emit(run)
    return nil
end

function M.activate(...)
    if select("#", ...) ~= 0 then return false, "arguments_not_accepted" end
    local permitted, reason = environment()
    if not permitted then return false, reason end
    local mode, started = current_world(), clock()
    if not mode or not method(mode, "SetContextThink") or not started then return false, "thinker_or_clock_unavailable" end
    if type(SendToServerConsole) ~= "function" or not method(GameRules, "SetCustomGameTeamMaxPlayers") then
        return false, "handoff_engine_api_unavailable"
    end
    local phase_ready, phase_reason = native_phase()
    if phase_ready == nil then return false, phase_reason end
    for _, name in ipairs(RESOURCE_APIS) do
        if not method(PlayerResource, name) then return false, "player_engine_api_unavailable" end
    end
    local previous = rawget(_G, LATCH)
    if type(previous) == "table" and previous.mode == mode then
        return previous.live or previous.status == "handoff_queued", previous.status
    end
    if type(previous) == "table" and previous.live then stop(previous, "context_changed") end
    local good, good_ok = call(GameRules, "SetCustomGameTeamMaxPlayers", DOTA_TEAM_GOODGUYS or 2, CAPACITY)
    local bad, bad_ok = call(GameRules, "SetCustomGameTeamMaxPlayers", DOTA_TEAM_BADGUYS or 3, 0)
    if not good_ok or good == false or not bad_ok or bad == false then return false, "capacity_configuration_failed" end
    local run = {mode = mode, started = started, last_clock = started, live = true, ticks = 0,
        status = phase_ready and "waiting_roster" or phase_reason, count = 0, expected = 0, expected_floor = 0, handoff_attempted = false}
    rawset(_G, LATCH, run)
    local scheduled, accepted = call(mode, "SetContextThink", "SurvivalNativeCloudHandoff01", function()
        local ok, delay = pcall(tick, run)
        if not ok then stop(run, "handoff_internal_error"); return nil end
        return delay
    end, INTERVAL)
    if not accepted or scheduled == false then
        stop(run, "thinker_refused")
        if rawget(_G, LATCH) == run then rawset(_G, LATCH, nil) end
        return false, "thinker_refused"
    end
    emit(run)
    return true
end
function M.snapshot()
    local run = rawget(_G, LATCH)
    if type(run) ~= "table" or run.mode ~= current_world() then return {status = "not_started", revision = REVISION} end
    return {status = run.status, revision = REVISION, active = run.live == true, players = run.count,
        expected_players = run.expected, capacity = CAPACITY, handoff_attempted = run.handoff_attempted == true}
end
return M
