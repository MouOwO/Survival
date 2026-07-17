local logger = require("core/logger")

local M = {}

local COMMANDS = {
    shopshow = true,
    ["-shopshow"] = true,
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function resolve_player_id(keys)
    local player_id = tonumber(
        keys and (keys.playerid or keys.player_id or keys.PlayerID)
    )
    if valid_player_id(player_id) then return player_id end

    local user_id = tonumber(keys and keys.userid)
    if user_id and PlayerResource.GetPlayerIDForUserID then
        local ok, resolved = pcall(function()
            return PlayerResource:GetPlayerIDForUserID(user_id)
        end)
        if ok and valid_player_id(resolved) then return resolved end
    end

    return nil
end

local function send_show_event(player_id, command)
    local player = PlayerResource:GetPlayer(player_id)
    if not player then
        logger.warn("ShopDebug", "player handle unavailable for " .. player_id)
        return
    end

    CustomGameEventManager:Send_ServerToPlayer(player, "ui_shop_debug_show", {
        command = command,
        source = "player_chat",
    })
    logger.info("ShopDebug", "sent shop UI show event to player " .. player_id)
end

local function on_player_chat(keys)
    local command = string.lower(trim(keys and keys.text))
    if not COMMANDS[command] then return end

    local player_id = resolve_player_id(keys)
    if not valid_player_id(player_id) then
        logger.warn("ShopDebug", "shopshow received without a valid player id")
        return
    end

    send_show_event(player_id, command)
end

function M.init()
    ListenToGameEvent("player_chat", on_player_chat, nil)
    logger.info("ShopDebug", "chat command ready: shopshow")
end

return M
