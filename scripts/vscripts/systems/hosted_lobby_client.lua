-- Only this entry map may hand off to a pinned match server. Never execute
-- command text supplied by a backend, UI event, player name or room field.
local config = require("config/hosted_lobby")
local M = {}
local initialized, last_match = false, nil
local function active()
    if config.enabled~=true or config.expected_map~="ws4_lobby" then return false end
    if type(IsServer)~="function" or type(IsClient)~="function" or type(GetMapName)~="function" then return false end
    local a,server=pcall(IsServer);local b,client=pcall(IsClient);local c,map=pcall(GetMapName)
    return a and server==false and b and client==true and c
        and (map=="ws4_lobby" or map=="maps/ws4_lobby.vpk")
end
local function endpoint(value)
    if type(value)~="string" or #value>21 then return false end
    local a,b,c,d,p=value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+):(%d+)$")
    if not a then return false end
    for _,part in ipairs({a,b,c,d}) do
        local n=tonumber(part)
        if n>255 or tostring(n)~=part then return false end
    end
    local port=tonumber(p)
    if port<1024 or port>65535 or tostring(port)~=p then return false end
    for _,pin in ipairs(config.connect_addresses or {}) do if pin==value then return true end end
    return false
end
function M.connect(event)
    if not active() or type(event)~="table" or type(SendToConsole)~="function" then return false end
    if not endpoint(event.address) or type(event.match_id)~="string" or #event.match_id<8 or #event.match_id>128
        or not event.match_id:match("^[A-Za-z0-9_%-]+$") or event.match_id==last_match
        or type(config.match_build_sha256)~="string" or #config.match_build_sha256~=64
        or not config.match_build_sha256:match("^[a-f0-9]+$")
        or event.build_sha256~=config.match_build_sha256 then return false end
    -- Latch before dispatch, including a native error. A retry needs an
    -- explicitly refreshed entry VM, rather than a console command loop.
    last_match=event.match_id
    local ok=pcall(SendToConsole,"connect "..event.address)
    print("[WS4-LOBBY-01] connect_dispatch="..(ok and "sent" or "failed"))
    return ok
end
function M.init()
    if not active() then return false end
    if initialized then return true end
    if type(ListenToGameEvent)~="function" then return false end
    ListenToGameEvent("survival_lobby_connect_local",function(event) M.connect(event) end,nil)
    initialized=true
    return true
end
return M
