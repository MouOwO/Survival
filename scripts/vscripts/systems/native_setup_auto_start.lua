-- Assign the co-op roster, then let Valve complete its own setup transition.
-- Authentication, assets, UI readiness and mode profiles remain separate gates.
local multiplayer = require("systems/multiplayer_player_service")
local rules = require("config/generated/multiplayer_rules")
local native_cloud_roster = require("systems/native_cloud_roster")
local M = {}
local world, generation, initialized, stable_since, fingerprint, enabled
local assignments, latest = {}, { status = "not_started", players = {} }
local INTERVAL, SETTLE_SECONDS = 0.1, 1

local function call(object, name, ...)
    if not object or type(object[name]) ~= "function" then return nil end
    local ok, result = pcall(object[name], object, ...)
    if ok then return result end
end

local function now()
    -- Game time can remain frozen throughout native custom-game setup.
    return type(Time) == "function" and Time() or os.clock()
end

local function current_world()
    return call(GameRules, "GetGameModeEntity")
end

local function expected_roster_complete()
    local ok, complete = pcall(native_cloud_roster.complete_roster)
    return ok and complete == true
end

local function maximum()
    local row = (rules.by_id or {}).default_multiplayer
    return math.max(1, math.floor(tonumber(row and row.max_players) or 1))
end

local function auto_launch(value)
    if enabled == value then return end
    GameRules:EnableCustomGameSetupAutoLaunch(value)
    -- AutoLaunch alone does not advance a setup whose original timeout is -1.
    -- Arm Valve's countdown once after the complete roster settles; cancel it
    -- when a player arrives/disconnects, never restart it on every think tick.
    GameRules:SetCustomGameSetupRemainingTime(value and 1 or -1)
    enabled = value
end

local function waiting(status, ids)
    stable_since, fingerprint = nil, nil
    auto_launch(false)
    latest = { status = status, players = ids, automatic = false }
    return INTERVAL
end

function M.tick()
    if not initialized or current_world() ~= world then return nil end
    local setup = tonumber(DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP)
    local state = tonumber(call(GameRules, "State_Get"))
    if not setup or not state then return waiting("native_state_unavailable", {}) end
    if state > setup then
        latest = { status = "native_setup_complete", players = latest.players, automatic = enabled == true }
        return nil
    end
    if state < setup then return waiting("waiting_native_load", {}) end

    local ids, keys, waiting_for_player, excluded = {}, {}, false, false
    for id = 0, (DOTA_MAX_TEAM_PLAYERS or 24) - 1 do
        if call(PlayerResource, "IsValidPlayerID", id) == true then
            local fake, team = call(PlayerResource, "IsFakeClient", id), call(PlayerResource, "GetTeam", id)
            if fake == false and team ~= (DOTA_TEAM_SPECTATOR or 1) then
                ids[#ids + 1] = id
                local player = call(PlayerResource, "GetPlayer", id)
                local connection = call(PlayerResource, "GetConnectionState", id)
                local account = tonumber(call(PlayerResource, "GetSteamAccountID", id))
                if not player or connection ~= (DOTA_CONNECTION_STATE_CONNECTED or 2)
                    or not account or account <= 0 then
                    waiting_for_player = true
                else
                    keys[#keys + 1] = tostring(id) .. ":" .. tostring(account) .. ":" .. tostring(player)
                    local prior = assignments[id]
                    local assigned_team = call(PlayerResource, "GetCustomTeamAssignment", id)
                    if not prior or prior.player ~= player or prior.account ~= account
                        or assigned_team ~= nil and assigned_team ~= (DOTA_TEAM_GOODGUYS or 2) then
                        local ok = multiplayer.assign_to_survival_team(id, "automatic_native_setup")
                        if ok then
                            multiplayer.mark_connected(id)
                            assignments[id] = { player = player, account = account }
                        else waiting_for_player = true end
                    end
                end
            else excluded = true end
        end
    end
    if #ids == 0 then return waiting("waiting_roster", ids) end
    if #ids > maximum() then return waiting("roster_over_capacity", ids) end
    -- A native lobby count can reveal players whose resource slots are still
    -- arriving. With spectators/bots its inclusion rules vary, so Valve's own
    -- auto-launch readiness remains authoritative instead of guessing a count.
    local expected = tonumber(call(GameRules, "GetCustomGamePlayerCount"))
    if not excluded and expected and expected > #ids then
        return waiting("waiting_lobby_roster", ids)
    end
    if waiting_for_player then return waiting("waiting_connection", ids) end
    if not expected_roster_complete() then return waiting("waiting_expected_roster", ids) end
    local key = table.concat(keys, "|")
    if fingerprint ~= key then
        fingerprint, stable_since = key, now()
        auto_launch(false)
    end
    if now() - stable_since < SETTLE_SECONDS then
        latest = { status = "waiting_stable_roster", players = ids, automatic = false }
        return INTERVAL
    end
    -- Never force FinishCustomGameSetup or expire a slow player's slot. The
    -- engine owns the countdown after the full connected roster has settled.
    auto_launch(true)
    latest = { status = "native_auto_launch", players = ids, automatic = true }
    return INTERVAL
end

function M.init()
    if type(IsServer) ~= "function" or IsServer() ~= true then return false, "server_required" end
    local entity = current_world()
    if type(GameRules.SetCustomGameSetupRemainingTime) ~= "function" then
        latest = { status = "native_remaining_time_api_missing", players = {}, automatic = false }
        print("[NATIVE_SETUP_AUTO_START] unavailable=native_remaining_time_api_missing")
        return false, "native_remaining_time_api_missing"
    end
    if not entity or type(entity.SetContextThink) ~= "function"
        or type(GameRules.EnableCustomGameSetupAutoLaunch) ~= "function"
        or type(GameRules.SetCustomGameSetupAutoLaunchDelay) ~= "function" then
        print("[NATIVE_SETUP_AUTO_START] unavailable=native_setup_api_missing")
        return false, "native_setup_api_missing"
    end
    if initialized and entity == world then return true end
    world, generation = entity, (generation or 0) + 1
    initialized, stable_since, fingerprint, enabled, assignments = true, nil, nil, nil, {}
    auto_launch(false)
    GameRules:SetCustomGameSetupAutoLaunchDelay(1)
    local epoch = generation
    entity:SetContextThink("SurvivalNativeSetupAutoStart", function()
        if epoch ~= generation then return nil end
        return M.tick()
    end, INTERVAL)
    M.tick()
    return true
end

function M.snapshot()
    local result = { status = latest.status, automatic = latest.automatic, players = {} }
    for index, id in ipairs(latest.players) do result.players[index] = id end
    return result
end

return M
