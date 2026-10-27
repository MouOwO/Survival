-- Checkout authority is separate from development/debug permission.
-- A public client flag, host privilege or payment bearer cannot enable it.
local release = require("core/release_policy")
local M = {}
local roster_fingerprint

local function isolated()
    -- Offline profiles are match-local memory, even if this process has a
    -- previously configured payment token. Keep every cash route offline too.
    -- Production omits this optional arena. An active offline provider has
    -- already loaded and latched it; checking cash must never load debug code.
    local offline = package.loaded["debug/offline_logic_test"]
    if offline and offline.is_enabled() then return true end
    local acceptance = package.loaded["debug/mode_unlock_test"]
    if acceptance and acceptance.is_enabled() then return true end
    local session = package.loaded["systems/session_multiplayer_test"]
    return session and session.is_enabled() or false
end

function M.online_allowed()
    if not release.is_production() or isolated() then return false end
    local config = require("config/commerce_payment_access")
    local web = require("config/player_web_auth")
    if type(config) ~= "table" or config.enabled ~= true
        or config.expected_map ~= "template_map"
        or config.base_url ~= "https://pay.xiaofengnet.com/ws4-web"
        or type(web) ~= "table" or web.enabled ~= true or web.base_url ~= config.base_url then return false end
    if type(IsServer) ~= "function" or type(IsInToolsMode) ~= "function"
        or type(GetMapName) ~= "function" then return false end
    local ok, allowed = pcall(function()
        local tools = IsInToolsMode()
        if IsServer() ~= true or GetMapName() ~= config.expected_map
            or not (tools == false or tools == true and config.connection_helper == true) then return false end
        local access = require("core/test_access_policy")
        local roster = require("config/test_access")
        if type(roster) ~= "table" or roster.enabled ~= true or type(roster.allowed_steamids) ~= "table" then return false end
        local count,seen,ids=0,{},{}
        for index,steam in pairs(roster.allowed_steamids) do
            if type(index)~="number" or index~=math.floor(index) or index<1 or index>4
                or type(steam)~="string" or #steam~=17 or not steam:match("^%d+$")
                or steam<="76561197960265728" or steam>"76561202255233023" or seen[steam] then return false end
            count,seen[steam],ids[index]=count+1,true,steam
        end
        if count~=4 then return false end
        local fingerprint=table.concat(ids,":")
        if roster_fingerprint and roster_fingerprint~=fingerprint then return false end
        if access.enabled()~=true or access.init()~=true then return false end
        roster_fingerprint=fingerprint
        return true
    end)
    return ok and allowed == true
end

function M.real_money_allowed()
    if isolated() then return false end
    return release.development_allowed() or M.online_allowed()
end

return M
