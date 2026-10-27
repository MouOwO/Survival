-- Server map-option barrier only, never identity/payment authorization.
-- No option means ordinary entry behavior: never infer a party from the
-- first target-VM player. Every consumer must retain its own normal gates.
local M = {}
local OPTION = "ws4_native_roster"
local WHITELIST = {['463897428'] = true, ['885195478'] = true, ['144521714'] = true, ['1014036256'] = true}
local STEAMIDS = {"76561198424163156", "76561198845461206", "76561198104787442", "76561198974301984"}
local world, initial_option, initial_required, option_latched

local function method(object, name)
    local ok, value = pcall(function() return object and object[name] end)
    return ok and type(value) == "function" and value or nil
end
local function call(object, name, ...)
    local fn = method(object, name)
    if not fn then return nil, false end
    local ok, value = pcall(fn, object, ...)
    return value, ok
end
local function integer(value, low, high)
    return type(value) == "number" and value == value and value >= low and value <= high and value == math.floor(value)
end
local function copy(rows)
    local result = {}; for index, value in ipairs(rows or {}) do result[index] = value end; return result
end
local function parse(raw)
    if type(raw) ~= "string" or #raw < 1 or #raw > 43 or not raw:match("^[0-9_]+$") then return nil end
    local result, seen = {}, {}
    for part in raw:gmatch("[^_]+") do
        local number = tonumber(part)
        if #part > 10 or not part:match("^[1-9][0-9]*$") or not integer(number, 1, 4294967295)
            or string.format("%.0f", number) ~= part or not WHITELIST[part] or seen[part] then return nil end
        result[#result + 1], seen[part] = part, true
    end
    if #result < 1 or #result > 4 or table.concat(result, "_") ~= raw then return nil end
    table.sort(result, function(a, b) return tonumber(a) < tonumber(b) end)
    return result
end
local function trusted_environment()
    local ok, allowed = pcall(function()
        return IsServer() == true and IsClient() == false and IsInToolsMode() == false and GetMapName() == "template_map"
    end)
    if not ok or not allowed then return nil, "native_production_server_required" end
    local cheats, readable
    if method(Convars, "GetInt") then cheats, readable = call(Convars, "GetInt", "sv_cheats"); readable = readable and cheats == 0
    elseif method(Convars, "GetBool") then cheats, readable = call(Convars, "GetBool", "sv_cheats"); readable = readable and cheats == false
    elseif method(Convars, "GetStr") then cheats, readable = call(Convars, "GetStr", "sv_cheats"); readable = readable and cheats == "0" end
    if not readable then return nil, "cheats_must_be_disabled" end
    local loaded, access = pcall(function()
        local release, config = require("config/release_profile"), require("config/test_access")
        local policy = require("core/test_access_policy")
        if type(release) ~= "table" or release.channel ~= "production" or type(config) ~= "table"
            or config.enabled ~= true or type(config.allowed_steamids) ~= "table" then return nil end
        local count = 0
        for index, steam in pairs(config.allowed_steamids) do
            if not integer(index, 1, 4) or steam ~= STEAMIDS[index] then return nil end
            count = count + 1
        end
        if count ~= 4 or type(policy) ~= "table" or type(policy.enabled) ~= "function" or type(policy.init) ~= "function"
            or type(policy.allowed) ~= "function" or policy.enabled() ~= true or policy.init() ~= true then return nil end
        return policy
    end)
    if not loaded or not access then return nil, "restricted_production_configuration_required" end
    return access
end
local function requirement()
    -- An explicit signed release flag distinguishes a native handoff whose
    -- option was lost from ordinary legacy/helper entry. Never infer this
    -- requirement from payment, cloud authentication, cheats or a client event.
    local configured, required = pcall(function()
        local profile = require("config/release_profile")
        if type(profile) ~= "table" then return nil end
        local channel, flag = profile.channel, profile.native_cloud_roster_required
        if (channel ~= "production" and channel ~= "development")
            or (flag ~= nil and type(flag) ~= "boolean")
            or (flag == true and channel ~= "production") then return nil end
        return flag == true
    end)
    if not configured or required == nil then
        return {present = true, valid = false, status = "native_roster_configuration_invalid"}
    end
    local raw, read = call(GameRules, "GetGameSessionConfigValue", OPTION, "")
    if not read or type(raw) ~= "string" then return {present = true, valid = false, status = "native_roster_option_unavailable"} end
    local mode, mode_ok = call(GameRules, "GetGameModeEntity")
    if mode_ok and mode then
        if world ~= mode then world, initial_option, initial_required, option_latched = mode, raw, required, true end
        if option_latched and required ~= initial_required then
            return {present = true, valid = false, status = "native_roster_configuration_changed"}
        end
        if option_latched and raw ~= initial_option then
            return {present = true, valid = false, status = "native_roster_option_changed"}
        end
    end
    if raw == "" then
        if required then return {present = true, valid = false, status = "native_roster_option_required"} end
        return {present = false, valid = true, status = "not_required", expected_accounts = {}}
    end
    local expected = parse(raw)
    if not expected then return {present = true, valid = false, status = "native_roster_option_invalid"} end
    if not mode_ok or not mode then return {present = true, valid = false, status = "native_roster_context_unavailable"} end
    local access, reason = trusted_environment()
    if not access then return {present = true, valid = false, status = reason} end
    return {present = true, valid = true, status = "waiting_expected_roster", expected_accounts = expected, access = access}
end
local function inspect()
    local result = requirement()
    if not result.present then result.complete = true; result.connected_accounts = {}; result.player_ids = {}; return result end
    if not result.valid then result.complete = false; return result end
    local expected, found, seen, player_ids, connected, pending = {}, {}, {}, {}, {}, false
    for _, account in ipairs(result.expected_accounts) do expected[account] = true end
    for _, name in ipairs({"IsValidPlayerID", "IsFakeClient", "GetTeam", "GetPlayer", "GetConnectionState", "GetSteamAccountID"}) do
        if not method(PlayerResource, name) then result.status = "native_roster_player_api_unavailable"; result.complete = false; result.access = nil; return result end
    end
    for id = 0, 23 do
        local valid, valid_ok = call(PlayerResource, "IsValidPlayerID", id)
        if not valid_ok or type(valid) ~= "boolean" then result.status = "native_roster_player_api_failed"; result.complete = false; result.access = nil; return result end
        if valid then
            local fake, fake_ok = call(PlayerResource, "IsFakeClient", id)
            local team, team_ok = call(PlayerResource, "GetTeam", id)
            if not fake_ok or type(fake) ~= "boolean" or not team_ok or fake or team == (DOTA_TEAM_SPECTATOR or 1) then
                result.status = "native_roster_nonhuman_or_spectator"; result.complete = false; result.access = nil; return result
            end
            local account, account_ok = call(PlayerResource, "GetSteamAccountID", id)
            local player, player_ok = call(PlayerResource, "GetPlayer", id)
            local connection, connection_ok = call(PlayerResource, "GetConnectionState", id)
            if not account_ok or not player_ok or not connection_ok then result.status = "native_roster_player_api_failed"; result.complete = false; result.access = nil; return result end
            if account ~= 0 and not integer(account, 1, 4294967295) then result.status = "native_roster_account_invalid"; result.complete = false; result.access = nil; return result end
            local decimal = account ~= 0 and string.format("%.0f", account) or nil
            if decimal and (not WHITELIST[decimal] or not expected[decimal]) then
                result.status = "native_roster_unexpected_account"; result.complete = false; result.access = nil; return result
            end
            if decimal and seen[decimal] then result.status = "native_roster_duplicate_account"; result.complete = false; result.access = nil; return result end
            if decimal then seen[decimal] = true end
            if decimal and player and connection == (DOTA_CONNECTION_STATE_CONNECTED or 2) and team ~= nil then
                local actual, actual_ok = call(player, "GetPlayerID")
                local null, null_ok = call(player, "IsNull")
                local admitted, allowed = pcall(result.access.allowed, id)
                if not actual_ok or actual ~= id or not null_ok or null ~= false or not admitted or allowed ~= true then
                    result.status = "native_roster_binding_invalid"; result.complete = false; result.access = nil; return result
                end
                found[decimal] = true; player_ids[#player_ids + 1] = id; connected[#connected + 1] = decimal
            else pending = true end
        end
    end
    result.access = nil
    result.connected_accounts, result.player_ids, result.complete = connected, player_ids, not pending
    for account in pairs(expected) do if not found[account] then result.complete = false end end
    result.status = result.complete and "complete" or "waiting_expected_roster"
    return result
end

function M.requirement_present()
    local result = requirement(); return result.present, result.status
end
function M.expected_accounts()
    local result = requirement()
    if not result.valid then return nil, result.status end
    return copy(result.expected_accounts), result.status
end
function M.complete_roster()
    local result = inspect(); return result.complete == true, result.status
end
function M.snapshot()
    local result = inspect()
    return {present = result.present == true, valid = result.valid == true, complete = result.complete == true,
        status = result.status, expected_accounts = copy(result.expected_accounts), connected_accounts = copy(result.connected_accounts),
        player_ids = copy(result.player_ids)}
end
return M
