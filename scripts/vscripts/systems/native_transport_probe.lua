-- Restricted, private round-trip evidence only. This listener cannot authorize
-- a player, load a profile, acknowledge an order, or change gameplay state.
local M = {}
local REVISION = "WS4-NATIVE-PROBE-01"
local REQUEST, REPLY = "survival_native_transport_probe_request", "survival_native_transport_probe_reply"
local ROSTER = {"76561198424163156", "76561198845461206", "76561198104787442", "76561198974301984"}
local ACCOUNTS = {['463897428'] = true, ['885195478'] = true, ['144521714'] = true, ['1014036256'] = true}
local initialized, active_session, last_clock = false, nil, nil
local accounts = {}

local function clock()
    if type(Time) ~= "function" then return nil end
    local ok, value = pcall(Time)
    if ok and type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
end
local function server()
    local ok, allowed = pcall(function()
        return IsServer() == true and IsClient() == false and GetMapName() == "template_map"
    end)
    return ok and allowed == true
end
local function resource(name, id)
    if not PlayerResource or type(PlayerResource[name]) ~= "function" then return nil end
    local ok, value = pcall(PlayerResource[name], PlayerResource, id)
    if ok then return value end
end
local function actor(source)
    local index = tonumber(source)
    if not index or index ~= index or index < 0 or index > 2147483647 or index ~= math.floor(index)
        or type(EntIndexToHScript) ~= "function" then return nil end
    local ok, entity = pcall(EntIndexToHScript, index)
    if not ok or not entity then return nil end
    local found, id = pcall(function()
        if type(entity.IsNull) == "function" and entity:IsNull() then return nil end
        return entity:GetPlayerID()
    end)
    if not found or type(id) ~= "number" or id ~= id or id < 0 or id > 23 or id ~= math.floor(id)
        or resource("GetPlayer", id) ~= entity or resource("IsValidPlayerID", id) ~= true
        or resource("IsFakeClient", id) ~= false or resource("GetConnectionState", id) ~= (DOTA_CONNECTION_STATE_CONNECTED or 2)
        or resource("GetTeam", id) == (DOTA_TEAM_SPECTATOR or 1) then return nil end
    local account = resource("GetSteamAccountID", id)
    if type(account) ~= "number" or account ~= account or account < 1 or account > 4294967295
        or account ~= math.floor(account) then return nil end
    account = string.format("%.0f", account)
    if not ACCOUNTS[account] then return nil end
    local permitted, allowed = pcall(function()
        local config, access = require("config/test_access"), require("core/test_access_policy")
        if type(config) ~= "table" or config.enabled ~= true or type(config.allowed_steamids) ~= "table" then return false end
        local count = 0
        for key, value in pairs(config.allowed_steamids) do
            if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > 4 or value ~= ROSTER[key] then return false end
            count = count + 1
        end
        return count == 4 and access.enabled() == true and access.init() == true and access.allowed(id) == true
    end)
    if permitted and allowed then return entity, id, account end
end
local function session()
    local ok, value = pcall(function() return require("systems/match_setup_service").get_session_id() end)
    if ok and type(value) == "string" and #value >= 8 and #value <= 128 and value:match("^[A-Za-z0-9_.:%-]+$") then return value end
end
local function receive(source, payload)
    if not server() or type(payload) ~= "table" then return false end
    local entity, id, account = actor(source)
    if not entity then return false end
    -- Some engine versions append PlayerID. It is never an identity source;
    -- even a matching value grants no authority. A forged value is rejected.
    for key in pairs(payload) do
        if key ~= "nonce" and key ~= "echo_b64" and key ~= "PlayerID" then return false end
    end
    if payload.PlayerID ~= nil and payload.PlayerID ~= id then return false end
    local nonce, echo = payload.nonce, payload.echo_b64
    if type(nonce) ~= "string" or #nonce ~= 32 or not nonce:match("^[a-f0-9]+$")
        or type(echo) ~= "string" or #echo < 1 or #echo > 192 or not echo:match("^[A-Za-z0-9_%-]+$") then return false end
    local match, now = session(), clock()
    if not match or not now or last_clock and now < last_clock then return false end
    last_clock = now
    if active_session ~= match then active_session, accounts = match, {} end
    local record = accounts[account]
    if not record then record = {seen = {}, recent = {}, count = 0}; accounts[account] = record end
    if record.seen[nonce] or record.count >= 128 then return false end
    local recent = {}
    for _, at in ipairs(record.recent) do if now - at < 30 then recent[#recent + 1] = at end end
    record.recent = recent
    if #recent >= 10 then return false end
    record.seen[nonce], record.count = true, record.count + 1
    recent[#recent + 1] = now
    -- Revalidate the live actor immediately before the private send. Never
    -- fall back to a broadcast, a client-supplied slot, or another entity.
    local still, current_id, current_account = actor(source)
    if still ~= entity or current_id ~= id or current_account ~= account or session() ~= match then return false end
    local sent, accepted = pcall(CustomGameEventManager.Send_ServerToPlayer, CustomGameEventManager, entity, REPLY, {
        ok = true, revision = REVISION, nonce = nonce, echo_b64 = echo,
        player_id = id, account_id = account, match_session_id = match,
    })
    return sent and accepted ~= false
end

function M.init()
    if initialized then return true end
    if not server() or not CustomGameEventManager or type(CustomGameEventManager.RegisterListener) ~= "function"
        or type(CustomGameEventManager.Send_ServerToPlayer) ~= "function" then return false end
    local ok, accepted = pcall(CustomGameEventManager.RegisterListener, CustomGameEventManager, REQUEST, function(source, payload)
        -- Bad engine objects or malformed events remain inert diagnostics.
        pcall(receive, source, payload)
    end)
    if not ok or accepted == false then return false end
    initialized = true
    return true
end
function M.sample(options)
    if not server() or type(options) ~= "table" then return false, "server_required" end
    local own = {side = "server", nonce = options.nonce, trigger = options.trigger, include_yhttp = options.include_yhttp}
    return require("systems/native_transport_client_probe").sample(own)
end
function M.inventory()
    if not server() then return false, "server_required" end
    return require("systems/native_transport_client_probe").inventory()
end
function M.start(options)
    if not M.init() then return false, "listener_unavailable" end
    options = options or {}
    if type(options) ~= "table" then return false, "options_invalid" end
    return require("systems/native_transport_client_probe").start({side = "server", automatic = options.automatic,
        include_yhttp = options.include_yhttp})
end
return M
