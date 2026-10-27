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

-- The native entry handoff is owned by the server; never launch a local map here.
return {}
