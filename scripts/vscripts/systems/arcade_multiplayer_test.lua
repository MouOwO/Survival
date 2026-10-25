-- Native session-only acceptance HUD. No account data, orders or rewards.
local M = {}
local TABLE = "survival_arcade_multiplayer_test"
local LATCH = "__survival_arcade_mp10_status"
local phases = {not_run=true, probing=true, available=true, unavailable=true}

local function hide()
    pcall(function() CustomNetTables:SetTableValue(TABLE,"state",{enabled=false}) end)
end

local function allowed()
    local ok, value = pcall(function()
        return require("systems/session_multiplayer_test").is_enabled() == true
            and require("config/release_profile").channel == "production"
            and type(IsServer) == "function" and IsServer() == true
            and type(IsInToolsMode) == "function" and IsInToolsMode() == false
            and type(GetMapName) == "function" and GetMapName() == "template_map"
            and require("core/test_access_policy").enforce_connected() == true
    end)
    return ok and value == true
end

local function roster()
    local count, host = 0, -1
    if not PlayerResource then return count, host end
    for id=0,23 do
        local ok, connected, player = pcall(function()
            if not PlayerResource:IsValidPlayerID(id)
                or PlayerResource:IsFakeClient(id) ~= false
                or (tonumber(PlayerResource:GetSteamAccountID(id)) or 0) <= 0 then return false end
            local state = PlayerResource:GetConnectionState(id)
            return type(state) == "number" and type(DOTA_CONNECTION_STATE_CONNECTED) == "number"
                and state == DOTA_CONNECTION_STATE_CONNECTED, PlayerResource:GetPlayer(id)
        end)
        if ok and connected == true then
            count = count + 1
            if player and GameRules and type(GameRules.PlayerHasCustomGameHostPrivileges) == "function" then
                local checked, is_host = pcall(GameRules.PlayerHasCustomGameHostPrivileges, GameRules, player)
                if checked and is_host == true then host = id end
            end
        end
    end
    return count, host
end

local function publish(run)
    if not allowed() then
        hide()
        return false
    end
    local count, host = roster()
    local phase = "not_run"
    local probe = package.loaded["systems/workshop_network_probe"]
    if probe and type(probe.public_status) == "function" then
        local ok, value = pcall(probe.public_status)
        if ok and phases[value] then phase = value end
    end
    run.sequence = run.sequence % 2147483647 + 1
    CustomNetTables:SetTableValue(TABLE,"state",{
        schema_version=1, enabled=true, session_only=true,
        online_players=count, capacity=4, host_player_id=host,
        http_phase=phase, sequence=run.sequence,
    })
    if count ~= run.players or host ~= run.host or phase ~= run.phase then
        print("[WS4-MP-10] native_status players="..count.." host="..host.." http="..phase
            .." storage=session_memory cash=false")
        run.players, run.host, run.phase = count, host, phase
    end
    return true
end

function M.activate()
    if not allowed() then return false end
    local checked, mode = pcall(GameRules.GetGameModeEntity,GameRules)
    if not checked or not mode then hide(); return false end
    local previous = rawget(_G,LATCH)
    if previous and previous.mode == mode then return true end
    local run = {mode=mode, sequence=0}
    rawset(_G,LATCH,run)
    local ok, result = pcall(mode.SetContextThink,mode,"ws4_mp10_status",function()
        local found, current_mode = pcall(GameRules.GetGameModeEntity,GameRules)
        if rawget(_G,LATCH) ~= run or not found or current_mode ~= mode then hide(); return nil end
        local checked, live = pcall(publish,run)
        if not checked or not live then
            hide()
            if rawget(_G,LATCH) == run then rawset(_G,LATCH,nil) end
            return nil
        end
        return 1
    end,0)
    if not ok or result == false then
        hide()
        if rawget(_G,LATCH) == run then rawset(_G,LATCH,nil) end
        return false
    end
    return true
end

return M
