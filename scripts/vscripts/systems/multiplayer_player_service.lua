local multiplayer_rules = require("config/generated/multiplayer_rules")
local scheduler = require("core/scheduler")
local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local player_states = {}
local DISCONNECT_DEFEAT_SECONDS = 20

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
            M.mark_connected(player_id)
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

function M.mark_connected(player_id)
    player_id = normalized_player_id(player_id)
    if player_id == nil then return false end
    local state = player_states[player_id] or {}
    if state.status ~= "defeated" then state.status = "active" end
    state.disconnected_at = nil
    player_states[player_id] = state
    scheduler.cancel("player_disconnect_defeat_" .. tostring(player_id))
    return true
end

function M.participating_player_ids()
    local result = {}
    for player_id in pairs(player_states) do
        result[#result + 1] = player_id
    end
    table.sort(result)
    return result
end

function M.is_disconnected(player_id)
    local state = player_states[normalized_player_id(player_id) or -1]
    return state ~= nil and state.status == "disconnected"
end

function M.all_participants_defeated()
    local total = 0
    for _, state in pairs(player_states) do
        total = total + 1
        if state.status ~= "defeated" then return false end
    end
    return total > 0
end

function M.defeat(player_id, reason)
    player_id = normalized_player_id(player_id)
    if player_id == nil then return false end
    local state = player_states[player_id] or {}
    if state.status == "defeated" then return false end
    state.status = "defeated"
    state.defeat_reason = tostring(reason or "unknown")
    player_states[player_id] = state
    scheduler.cancel("player_disconnect_defeat_" .. tostring(player_id))
    event_bus.emit(events.PLAYER_DEFEATED, {
        player_id = player_id,
        reason = state.defeat_reason,
    })
    event_bus.emit(events.PLAYER_DISCONNECTED, {
        player_id = player_id,
        reason = state.defeat_reason,
        defeat_cleanup = true,
    })
    print(string.format("[PLAYER_DEFEAT] player=%s reason=%s",
        tostring(player_id), state.defeat_reason))
    return true
end

function M.mark_disconnected(player_id)
    player_id = normalized_player_id(player_id)
    if player_id == nil then return false end
    local state = player_states[player_id] or {}
    if state.status == "defeated" then return false end
    state.status = "disconnected"
    state.disconnected_at = GameRules:GetGameTime()
    player_states[player_id] = state
    local task_id = "player_disconnect_defeat_" .. tostring(player_id)
    scheduler.cancel(task_id)
    scheduler.after(DISCONNECT_DEFEAT_SECONDS, function()
        if M.is_disconnected(player_id) then
            M.defeat(player_id, "disconnect_timeout")
        end
        return false
    end, task_id)
    print(string.format("[PLAYER_DISCONNECT_GRACE] player=%s seconds=%d",
        tostring(player_id), DISCONNECT_DEFEAT_SECONDS))
    return true
end

function M._reset_for_test()
    player_states = {}
end

return M