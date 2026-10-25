-- Restricted native multiplayer test profiles. No files, web requests, cloud
-- archives, invented identities, or debug grants belong to this provider.
local M, provider = {}, {}
local enabled = false
local profiles, accounts, current_session, revision_serial = {}, {}, nil, 0
local admission_fingerprint = nil

local function clear()
    profiles, accounts, current_session, revision_serial = {}, {}, nil, 0
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[key] = copy(child, seen) end
    return result
end

local function configuration(name)
    local ok, value = pcall(require, name)
    return ok and type(value) == "table" and value or nil
end

local function engine_false(callback)
    if type(callback) ~= "function" then return false end
    local ok, value = pcall(callback)
    return ok and value == false
end

local function cheats_disabled()
    if not Convars then return false end
    local observed = false
    for _, name in ipairs({ "GetBool", "GetInt", "GetStr" }) do
        if type(Convars[name]) == "function" then
            local ok, value = pcall(Convars[name], Convars, "sv_cheats")
            if not ok or not (value == false or value == 0 or value == "0") then return false end
            observed = true
        end
    end
    return observed
end

local function guard()
    local config = configuration("config/session_multiplayer_test")
    if not config or config.enabled ~= true or config.expected_map ~= "template_map" then
        return false, "session_multiplayer_configuration_invalid"
    end
    if type(IsServer) ~= "function" then return false, "session_multiplayer_server_required" end
    local server_ok, server = pcall(IsServer)
    if not server_ok or server ~= true then return false, "session_multiplayer_server_required" end
    if not engine_false(IsInToolsMode) then return false, "session_multiplayer_native_required" end
    if type(GetMapName) ~= "function" then return false, "session_multiplayer_map_required" end
    local map_ok, map = pcall(GetMapName)
    if not map_ok or map ~= config.expected_map then return false, "session_multiplayer_map_required" end
    if not cheats_disabled() then return false, "session_multiplayer_cheats_must_be_disabled" end
    local web = configuration("config/player_web_auth")
    if not web or web.enabled ~= false then return false, "session_multiplayer_web_auth_conflict" end
    local access = configuration("config/test_access")
    if not access or access.enabled ~= true or type(access.allowed_steamids) ~= "table" then
        return false, "session_multiplayer_four_account_gate_required"
    end
    local count, seen, ids = 0, {}, {}
    for index, steam in pairs(access.allowed_steamids) do
        if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > 4
            or type(steam) ~= "string" or #steam ~= 17 or not steam:match("^%d+$")
            or steam <= "76561197960265728" or steam > "76561202255233023" or seen[steam] then
            return false, "session_multiplayer_four_account_gate_required"
        end
        count, seen[steam], ids[index] = count + 1, true, steam
    end
    if count ~= 4 then return false, "session_multiplayer_four_account_gate_required" end
    local fingerprint = table.concat(ids, ":")
    if admission_fingerprint and admission_fingerprint ~= fingerprint then
        return false, "session_multiplayer_admission_changed"
    end
    local policy = configuration("core/test_access_policy")
    if not policy or type(policy.enabled) ~= "function"
        or type(policy.init) ~= "function" or type(policy.enforce) ~= "function" then
        return false, "session_multiplayer_four_account_gate_required"
    end
    local enabled_ok, access_enabled = pcall(policy.enabled)
    if not enabled_ok or access_enabled ~= true then return false, "session_multiplayer_four_account_gate_required" end
    local init_ok, ready, reason = pcall(policy.init)
    if not init_ok or ready ~= true then
        return false, init_ok and reason or "session_multiplayer_four_account_gate_required"
    end
    return true, nil, fingerprint
end

function M.configure()
    enabled, admission_fingerprint = false, nil
    clear()
    local config = configuration("config/session_multiplayer_test")
    assert(config and type(config.enabled) == "boolean", "session_multiplayer_configuration_invalid")
    if config.enabled == false then return false end
    local allowed, reason, fingerprint = guard()
    assert(allowed, reason)
    enabled, admission_fingerprint = true, fingerprint
    print("[SESSION_MULTIPLAYER_TEST] enabled=true storage=session_memory cloud=false cheats=false")
    return true
end

function M.is_enabled()
    if not enabled then return false end
    local allowed = guard()
    if not allowed then
        enabled = false
        clear()
    end
    return enabled
end

function M.is_provider(value) return M.is_enabled() and value == provider end

function M.profile_options()
    if not M.is_enabled() then return nil end
    return { provider = provider, session_multiplayer_test = true }
end

local function setup()
    assert(M.is_enabled(), "session_multiplayer_not_enabled")
    local match = require("systems/match_setup_service")
    local session = match.get_session_id()
    assert(type(session) == "string" and #session >= 8, "match_session_missing")
    if current_session ~= session then
        -- The profile service retains a revision high-water mark until init.
        -- Keep its monotonic counter while discarding all previous match data.
        local previous_revision = revision_serial
        clear()
        revision_serial = previous_revision
        current_session = session
    end
    return match, session
end

local function engine_account(player_id)
    if not PlayerResource or type(PlayerResource.GetSteamAccountID) ~= "function" then return nil end
    local ok, value = pcall(PlayerResource.GetSteamAccountID, PlayerResource, player_id)
    if not ok or type(value) ~= "number" or value ~= value or value < 1
        or value > 4294967295 or value ~= math.floor(value) then return nil end
    if type(PlayerResource.IsFakeClient) == "function" then
        local fake_ok, fake = pcall(PlayerResource.IsFakeClient, PlayerResource, player_id)
        if not fake_ok or fake ~= false then return nil end
    end
    return string.format("%.0f", value)
end

local function admitted(account)
    local player_id = accounts[account]
    if player_id == nil then return false end
    if not require("core/test_access_policy").enforce(player_id) or engine_account(player_id) ~= account then
        accounts[account] = nil
        return false
    end
    return true
end

local function progression(save)
    local archive = type(save) == "table" and save.archive or {}
    local value = { loaded = true }
    for _, field in ipairs({ "clear_counts", "standard_clear_counts", "pure_clear_counts",
        "rich_clear_counts", "cold_clear_counts", "scourge_clear_counts", "ruins_clear_counts",
        "celestial_clear_counts", "mode_clear_counts" }) do
        value[field] = copy(type(archive) == "table" and archive[field] or {})
    end
    return value
end

local function defaults(isolated)
    local value = {}
    for _, row in ipairs(require("config/generated/player_gameplay_stats").rows or {}) do
        if row.enabled ~= false then
            local minimum = tonumber(row.min_value)
            value[tostring(row.field_id)] = isolated and not (minimum and minimum > 0)
                and 0 or tonumber(row.default_value) or minimum or 0
        end
    end
    return value
end

local function profile(account)
    local match, session = setup()
    if not admitted(account) then return nil, "session_multiplayer_account_unavailable" end
    if not match.is_mode_selected() then return nil, "mode_not_selected" end
    local mode = type(match.get_profile_mode) == "function" and match.get_profile_mode() or match.get_mode()
    if mode ~= "standard" and mode ~= "pure" then return nil, "mode_not_selected" end
    profiles[mode] = profiles[mode] or {}
    local value = profiles[mode][account]
    if not value then
        revision_serial = revision_serial + 1
        value = { schema_version = 1, account_id = account, revision = revision_serial,
            mode = mode, match_session_id = session,
            entitlements = {}, achievements = {}, public = {},
            save = { gameplay_stats = defaults(false), content_inventory = {}, archive = {} } }
        profiles[mode][account] = value
    end
    value.game_mode, value.progression = match.get_mode(), progression(value.save)
    return value
end

function provider.init()
    assert(M.is_enabled(), "session_multiplayer_not_enabled")
    clear()
end

function provider.resolve_account_id(player_id)
    setup()
    if type(player_id) ~= "number" or player_id ~= player_id or player_id < 0 or player_id > 255
        or player_id ~= math.floor(player_id) then return nil end
    if not require("core/test_access_policy").enforce(player_id) then return nil end
    local account = engine_account(player_id)
    if not account or accounts[account] ~= nil and accounts[account] ~= player_id then return nil end
    accounts[account] = player_id
    return account
end

function provider.authenticate(account, success, failure)
    local _, session = setup()
    if not admitted(account) then failure("session_multiplayer_account_unavailable") return end
    success({ authenticated = true, account_id = account, match_session_id = session,
              progression = progression() })
end

function provider.fetch_snapshot(account, success, failure)
    local value, reason = profile(account)
    if not value then failure(reason) return end
    success(copy(value))
end

local function revision_valid(value)
    return type(value) == "number" and value == value and value >= 0
        and value < math.huge and value == math.floor(value)
end

function provider.persist_save(account, save, revision)
    local value, reason = profile(account)
    if not value then return false, reason end
    if type(save) ~= "table" or type(save.gameplay_stats) ~= "table"
        or type(save.content_inventory) ~= "table" or type(save.archive) ~= "table"
        or not revision_valid(revision) then return false, "session_multiplayer_save_invalid" end
    value.save, value.revision = copy(save), revision
    revision_serial = math.max(revision_serial, revision)
    return true
end

function provider.persist_gameplay_stats(account, stats, revision)
    local value, reason = profile(account)
    if not value then return false, reason end
    if type(stats) ~= "table" or not revision_valid(revision) then
        return false, "session_multiplayer_save_invalid"
    end
    value.save.gameplay_stats, value.revision = copy(stats), revision
    revision_serial = math.max(revision_serial, revision)
    return true
end

function provider.persist_isolated_gameplay_stat(account, field_id, amount, revision)
    local value, reason = profile(account)
    if not value then return false, reason end
    local stats = defaults(true)
    if type(field_id) ~= "string" or stats[field_id] == nil or type(amount) ~= "number"
        or amount ~= amount or math.abs(amount) == math.huge or not revision_valid(revision) then
        return false, "session_multiplayer_save_invalid"
    end
    stats[field_id] = amount
    value.save.gameplay_stats, value.revision = stats, revision
    revision_serial = math.max(revision_serial, revision)
    return true
end

function provider.archive_enabled() return false end

return M
