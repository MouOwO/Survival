-- Server-owned admission for restricted Workshop tests. Never read identity
-- from a client payload; SteamID64 remains decimal text throughout conversion.
local config = require("config/test_access")
local offline_onboarding = require("debug/offline_onboarding_test")
local M = {}
local initialized, initialization_error = false, nil
local allowed_accounts, disconnect_requested = {}, {}
local BASE = "76561197960265728"
local MAXIMUM = "76561202255233023"
local MAX_ACCOUNT = 4294967295

local function account_from_steamid64(value)
    if type(value) ~= "string" or #value ~= 17 or not value:match("^%d+$")
        or value <= BASE or value > MAXIMUM then return nil end
    -- Subtract the decimal base one digit at a time. Converting the complete
    -- 64-bit identifier to a Lua 5.1 number would round neighbouring accounts.
    local digits, borrow = {}, 0
    for index = 17, 1, -1 do
        local digit = tonumber(value:sub(index, index))
            - tonumber(BASE:sub(index, index)) - borrow
        if digit < 0 then digit, borrow = digit + 10, 1 else borrow = 0 end
        digits[index] = tostring(digit)
    end
    local decimal = table.concat(digits):gsub("^0+", "")
    local account = tonumber(decimal)
    if not account or account < 1 or account > MAX_ACCOUNT then return nil end
    return account
end

local function resource_method(name)
    if not PlayerResource then return nil end
    local ok, method = pcall(function() return PlayerResource[name] end)
    return ok and type(method) == "function" and method or nil
end

function M.enabled()
    -- Only an explicit false selects unrestricted development behavior.
    return type(config) ~= "table" or config.enabled ~= false
end

function M.init()
    if initialized then return initialization_error == nil, initialization_error end
    initialized = true
    -- Latch the explicit preview choice before an online match can mutate a
    -- server convar. The helper never loads or enables the offline provider.
    offline_onboarding.requested()
    if not M.enabled() then return true end
    local function fail(reason)
        initialization_error = reason
        return false, reason
    end
    if type(config) ~= "table" or config.enabled ~= true or type(config.allowed_steamids) ~= "table" then
        return fail("test_access_configuration_invalid")
    end
    local count = 0
    for key, steam in pairs(config.allowed_steamids) do
        if type(key) ~= "number" or key < 1 or key > 4 or key ~= math.floor(key) then
            return fail("test_access_requires_four_accounts")
        end
        local account = account_from_steamid64(steam)
        if not account or allowed_accounts[account] then return fail("test_access_account_invalid_or_duplicate") end
        allowed_accounts[account] = true
        count = count + 1
    end
    if count ~= 4 then return fail("test_access_requires_four_accounts") end
    if type(IsServer) ~= "function" then return fail("test_access_server_api_missing") end
    local server_ok, server = pcall(IsServer)
    if not server_ok or server ~= true then return fail("test_access_server_required") end
    if type(DisconnectClient) ~= "function" then return fail("test_access_disconnect_api_missing") end
    if not resource_method("GetSteamAccountID") and not resource_method("GetSteamID") then
        return fail("test_access_identity_api_missing")
    end
    return true
end

function M.allowed(player_id)
    if not M.enabled() then return true end
    local ready, reason = M.init()
    if not ready then return false, reason end
    if type(player_id) ~= "number" or player_id ~= player_id or player_id < 0
        or player_id > 255 or player_id ~= math.floor(player_id) then
        return false, "test_access_player_invalid"
    end
    local valid = resource_method("IsValidPlayerID")
    if valid then
        local ok, result = pcall(valid, PlayerResource, player_id)
        if not ok or result ~= true then return false, "test_access_player_invalid" end
    end
    if offline_onboarding.requested() then
        if not offline_onboarding.is_human(player_id) then
            return false, "test_access_player_invalid"
        end
        return true
    end
    local getter = resource_method("GetSteamAccountID")
    local account
    if getter then
        local ok, value = pcall(getter, PlayerResource, player_id)
        if not ok or type(value) ~= "number" or value ~= value or value < 1
            or value > MAX_ACCOUNT or value ~= math.floor(value) then
            return false, "test_access_identity_unavailable"
        end
        account = value
    else
        getter = resource_method("GetSteamID")
        if not getter then return false, "test_access_identity_api_missing" end
        local ok, value = pcall(getter, PlayerResource, player_id)
        -- Some engine bindings return an imprecise number. Only exact decimal
        -- text is eligible for this fallback; do not tostring a rounded value.
        account = ok and account_from_steamid64(value) or nil
        if not account then return false, "test_access_identity_unavailable" end
    end
    if not allowed_accounts[account] then return false, "test_access_account_not_allowed" end
    return true
end

function M.enforce(player_id)
    local allowed, reason = M.allowed(player_id)
    if allowed then
        if player_id ~= nil then disconnect_requested[player_id] = nil end
        return true
    end
    -- A real player can briefly have account 0 while Steam admission settles.
    -- Keep every data/gameplay gate closed, but do not enqueue an irreversible
    -- kick until an authoritative account is known to be outside the list.
    if reason ~= "test_access_identity_unavailable"
        and type(player_id) == "number" and player_id >= 0 and player_id <= 255
        and player_id == math.floor(player_id) and not disconnect_requested[player_id]
        and type(DisconnectClient) == "function" then
        local ok = pcall(DisconnectClient, player_id, true)
        disconnect_requested[player_id] = ok and true or nil
        if not ok then reason = "test_access_disconnect_failed" end
    end
    -- A rejected account remains denied even when the engine kick is delayed
    -- or fails. Callers must return before loading data or granting anything.
    return false, reason
end

function M.enforce_connected()
    local ready, reason = M.init()
    if not ready then return false, reason end
    if not M.enabled() then return true end
    local get_player = resource_method("GetPlayer")
    if not get_player then return false, "test_access_player_api_missing" end
    for player_id = 0, (DOTA_MAX_TEAM_PLAYERS or 24) - 1 do
        local ok, player = pcall(get_player, PlayerResource, player_id)
        if not ok then return false, "test_access_player_api_failed" end
        if player then M.enforce(player_id) end
    end
    return true
end

return M
