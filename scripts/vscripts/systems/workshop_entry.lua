-- The Workshop default map only admits testers and hands the local client to
-- the same Workshop item's real map. It never loads gameplay or cloud systems.
local M = {}
local MAP = "ws4_entry"
local initialized = false

local function active()
    if type(IsServer) ~= "function" or type(IsClient) ~= "function" or type(GetMapName) ~= "function" then return false end
    local server_ok, server = pcall(IsServer)
    local client_ok, client = pcall(IsClient)
    local map_ok, map = pcall(GetMapName)
    return server_ok and server == true and client_ok and client == false and map_ok and map == MAP
end

function M.activate()
    if not active() then return false, "workshop_entry_server_map_required" end
    if initialized then return true end
    local loaded, access = pcall(require, "core/test_access_policy")
    if not loaded or type(access) ~= "table" or type(access.enabled) ~= "function"
        or type(access.init) ~= "function" or type(access.enforce_connected) ~= "function" then
        return false, "workshop_entry_access_unavailable"
    end
    local enabled_ok, enabled = pcall(access.enabled)
    local ready_ok, ready = pcall(access.init)
    if not enabled_ok or enabled ~= true or not ready_ok or ready ~= true then
        return false, "workshop_entry_restricted_access_required"
    end
    local connected_ok, checked = pcall(access.enforce_connected)
    if not connected_ok or checked ~= true then return false, "workshop_entry_admission_unavailable" end
    if not GameRules or type(GameRules.GetGameModeEntity) ~= "function" then
        return false, "workshop_entry_engine_api_unavailable"
    end
    local mode_ok, mode = pcall(GameRules.GetGameModeEntity, GameRules)
    if not mode_ok or not mode or type(mode.SetContextThink) ~= "function" then
        return false, "workshop_entry_thinker_unavailable"
    end
    local configured = pcall(function()
        GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS or 2, 1)
        GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS or 3, 0)
        GameRules:SetHeroSelectionTime(0)
        GameRules:SetStrategyTime(0)
        GameRules:SetShowcaseTime(0)
        GameRules:SetCustomGameSetupTimeout(1)
        GameRules:EnableCustomGameSetupAutoLaunch(true)
    end)
    if not configured then return false, "workshop_entry_setup_failed" end
    local function tick()
        if not active() then return nil end
        local checked, admitted = pcall(access.enforce_connected)
        if not checked or admitted ~= true then return nil end
        return 0.1
    end
    local scheduled = pcall(mode.SetContextThink, mode, "SurvivalWorkshopEntryAdmission", tick, 0.1)
    if not scheduled then return false, "workshop_entry_thinker_failed" end
    initialized = true
    tick()
    print("[WS4-ENTRY-05] server_ready single_player=true cloud_started=false")
    return true
end

return M
