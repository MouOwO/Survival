-- The independent lobby has a separate, endpoint-pinned handoff path.
local lobby_map_ok,lobby_map=false,nil
if type(GetMapName)=="function" then lobby_map_ok,lobby_map=pcall(GetMapName) end
if lobby_map_ok and (lobby_map=="ws4_lobby" or lobby_map=="maps/ws4_lobby.vpk") then
    local lobby=require("systems/hosted_lobby_client")
    Activate=function() lobby.init() end
    ActivateClient=Activate
    lobby.init()
    return
end

-- Reopen the same Workshop item's real map from its lightweight default map.
-- The target map retains its own server-owned authentication/admission gates.
local M = {}
local COMMAND = "dota_launch_custom_game 3824360109 template_map"
local STATE_KEY = "__survival_workshop_entry_client_sent_v1"

local function active()
    if type(IsServer) ~= "function" or type(IsClient) ~= "function"
        or type(GetMapName) ~= "function" then return false end
    local server_ok, server = pcall(IsServer)
    local client_ok, client = pcall(IsClient)
    local map_ok, map = pcall(GetMapName)
    return server_ok and server == false and client_ok and client == true and map_ok
        and (map == "ws4_entry" or map == "maps/ws4_entry.vpk")
end

function M.init()
    if not active() then return false, "workshop_entry_client_map_required" end
    if rawget(_G, STATE_KEY) == true then return true end
    if type(SendToConsole) ~= "function" then return false, "workshop_entry_console_unavailable" end
    -- Latch before native dispatch. Reentrant callbacks and script reloads in
    -- this VM cannot issue another launch command, including after an error.
    rawset(_G, STATE_KEY, true)
    local sent = pcall(function() SendToConsole(COMMAND) end)
    print("[WS4-ENTRY-05] client_launch=" .. (sent and "sent" or "failed"))
    if not sent then return false, "workshop_entry_console_failed" end
    return true
end

-- Execute once when the entry-map client VM loads. Activation can retry only
-- if the native console API was unavailable before any command was attempted.
if active() then
    Activate = function() M.init() end
    ActivateClient = Activate
    M.init()
end

return M
