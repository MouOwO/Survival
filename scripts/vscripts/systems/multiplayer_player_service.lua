local multiplayer_rules = require("config/generated/multiplayer_rules")

local M = {}

local function normalized_player_id(value)
    local player_id = tonumber(value)
    if player_id == nil or player_id < 0 then return nil end
    return math.floor(player_id)
end

local function configured_max_players()
    local rule = (multiplayer_rules.by_id or {}).default_multiplayer
    return math.max(1, math.floor(tonumber(rule and rule.max_players) or 1))
end

function M.resolve_player_id(keys)
    keys = keys or {}
    local direct_player_id = normalized_player_id(keys.PlayerID or keys.playerid)
    local userid = tonumber(keys.userid or keys.UserID)
    if direct_player_id ~= nil then
        return direct_player_id, "direct", userid
    end
    if userid ~= nil and type(PlayerInstanceFromIndex) == "function" then
        local player = PlayerInstanceFromIndex(userid)
        if player and type(player.GetPlayerID) == "function" then
            local player_id = normalized_player_id(player:GetPlayerID())
            if player_id ~= nil then return player_id, "userid", userid end
        end
    end
    return nil, "unresolved", userid
end

function M.assign_to_survival_team(player_id, source)
    player_id = normalized_player_id(player_id)
    source = tostring(source or "unknown")
    if player_id == nil then
        print("[MULTIPLAYER_PLAYER] assignment_rejected source=" .. source
            .. " reason=invalid_player_id")
        return false, "invalid_player_id"
    end

    local state = GameRules:State_Get()
    local current_team = PlayerResource.GetTeam
        and PlayerResource:GetTeam(player_id) or nil
    if state >= DOTA_GAMERULES_STATE_HERO_SELECTION then
        print("[MULTIPLAYER_PLAYER] assignment_window_closed source=" .. source
            .. " player_id=" .. tostring(player_id)
            .. " state=" .. tostring(state)
            .. " team=" .. tostring(current_team))
        return false, "assignment_window_closed"
    end

    PlayerResource:SetCustomTeamAssignment(player_id, DOTA_TEAM_GOODGUYS)
    print("[MULTIPLAYER_PLAYER] assigned source=" .. source
        .. " player_id=" .. tostring(player_id)
        .. " state=" .. tostring(state)
        .. " team=" .. tostring(DOTA_TEAM_GOODGUYS))
    return true, nil
end

function M.assign_connected_players(source)
    local assigned = 0
    for player_id = 0, configured_max_players() - 1 do
        local valid = not PlayerResource.IsValidPlayerID
            or PlayerResource:IsValidPlayerID(player_id)
        local player = PlayerResource.GetPlayer
            and PlayerResource:GetPlayer(player_id) or nil
        if valid and player then
            local ok = M.assign_to_survival_team(player_id, source)
            if ok then assigned = assigned + 1 end
        end
    end
    print("[MULTIPLAYER_PLAYER] connected_assignment_complete source="
        .. tostring(source or "unknown")
        .. " assigned=" .. tostring(assigned)
        .. " max_players=" .. tostring(configured_max_players()))
    return assigned
end

return M