-- Explicit Workshop Tools arena. Its profiles exist only in this Lua session;
-- they never open fixture files, carry Steam credentials, or contact the API.
local M = {}
local enabled = false
local provider = {}
local profiles, accounts, onboarding = {}, {}, {}
local current_session = nil
local revision_serial = 0

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function tools_allowed()
    return require("core/release_policy").development_allowed()
end

local function requested()
    if not Convars or type(Convars.GetStr) ~= "function" then return false end
    local ok, value = pcall(Convars.GetStr, Convars, "survival_offline_logic_test")
    return ok and tostring(value or "") == "1"
end

function M.configure()
    enabled, profiles, accounts, onboarding, current_session = false, {}, {}, {}, nil
    if Convars and type(Convars.RegisterConvar) == "function" then
        -- Registration preserves an existing explicit server value.
        pcall(Convars.RegisterConvar, Convars, "survival_offline_logic_test", "0",
            "Opt-in development Workshop Tools offline logic arena", 0)
    end
    require("debug/offline_onboarding_test").configure()
    if not requested() then return false end
    assert(tools_allowed(), "offline_logic_tools_required")
    assert(not require("systems/player_web_auth").enabled(),
        "offline_logic_web_auth_conflict")
    enabled = true
    require("debug/offline_onboarding_test").configure()
    print("[OFFLINE_LOGIC_TEST] enabled=true storage=session_memory cloud=false")
    return true
end

function M.is_enabled()
    -- A launch choice is latched for the match; changing the convar cannot
    -- turn an offline profile into an online one halfway through gameplay.
    return enabled and tools_allowed()
end

function M.is_provider(value) return M.is_enabled() and value == provider end

function M.profile_options()
    if not M.is_enabled() then return nil end
    return { provider = provider, offline_logic_test = true }
end

local function setup()
    assert(M.is_enabled(), "offline_logic_not_enabled")
    local value = require("systems/match_setup_service")
    local session = value.get_session_id()
    assert(type(session) == "string" and #session >= 8, "match_session_missing")
    if current_session ~= session then
        current_session, profiles, accounts, onboarding = session, {}, {}, {}
    end
    return value, session
end

local function progression(save)
    local archive = type(save) == "table" and save.archive or {}
    local result = { loaded = true }
    for _, field in ipairs({ "clear_counts", "standard_clear_counts", "rich_clear_counts",
        "cold_clear_counts", "scourge_clear_counts", "ruins_clear_counts",
        "celestial_clear_counts", "mode_clear_counts" }) do
        result[field] = copy(archive and archive[field] or {})
    end
    return result
end

local function defaults()
    local result = {}
    for _, row in ipairs(require("config/generated/player_gameplay_stats").rows or {}) do
        if row.enabled ~= false then result[tostring(row.field_id)] = tonumber(row.default_value) or 0 end
    end
    return result
end

local function profile(account)
    local match, session = setup()
    if not accounts[account] then return nil, "offline_account_unavailable" end
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
            save = { gameplay_stats = defaults(), content_inventory = {}, archive = {} } }
        profiles[mode][account] = value
    end
    value.game_mode, value.progression = match.get_mode(), progression(value.save)
    return value
end

function provider.init()
    assert(M.is_enabled(), "offline_logic_not_enabled")
    profiles, accounts, onboarding, current_session, revision_serial = {}, {}, {}, nil, 0
end

function provider.resolve_account_id(player_id)
    setup()
    if type(player_id) ~= "number" or player_id < 0 or player_id ~= math.floor(player_id) then return nil end
    local preview = require("debug/offline_onboarding_test")
    if preview.is_enabled() then
        local account = preview.account_id(player_id)
        if account then accounts[account] = true end
        return account
    end
    if not require("core/test_access_policy").allowed(player_id) then return nil end
    -- Admission compares this identity with the engine's Steam account ID.
    -- Isolation belongs to this memory-only provider/session, not a fake ID.
    if not PlayerResource or type(PlayerResource.GetSteamAccountID) ~= "function" then return nil end
    local ok, identity = pcall(PlayerResource.GetSteamAccountID, PlayerResource, player_id)
    if not ok or type(identity) ~= "number" or identity < 1 or identity > 4294967295
        or identity ~= math.floor(identity) then return nil end
    local account = string.format("%.0f", identity)
    accounts[account] = true
    return account
end

function provider.authenticate(account, success, failure)
    local _, session = setup()
    if not accounts[account] then failure("offline_account_unavailable") return end
    success({ authenticated = true, account_id = account, match_session_id = session,
        progression = progression() })
end

function provider.fetch_snapshot(account, success, failure)
    local value, reason = profile(account)
    if not value then failure(reason) return end
    success(copy(value))
end

function provider.persist_save(account, save, revision)
    local value, reason = profile(account)
    if not value then return false, reason end
    value.save, value.revision = copy(save), revision
    revision_serial = math.max(revision_serial, tonumber(revision) or 0)
    return true
end

function provider.persist_gameplay_stats(account, stats, revision)
    local value, reason = profile(account)
    if not value then return false, reason end
    value.save.gameplay_stats, value.revision = copy(stats), revision
    revision_serial = math.max(revision_serial, tonumber(revision) or 0)
    return true
end

function provider.persist_isolated_gameplay_stat(account, field_id, value, revision)
    local current, reason = profile(account)
    if not current then return false, reason end
    local stats = {}
    for _, row in ipairs(require("config/generated/player_gameplay_stats").rows or {}) do
        if row.enabled ~= false then
            stats[tostring(row.field_id)] = tonumber(row.min_value) and tonumber(row.min_value) > 0
                and (tonumber(row.default_value) or tonumber(row.min_value)) or 0
        end
    end
    stats[field_id] = value
    current.save.gameplay_stats, current.revision = stats, revision
    revision_serial = math.max(revision_serial, tonumber(revision) or 0)
    return true
end

local function onboarding_request(payload, outcome, success, failure)
    local _, session = setup()
    local account = type(payload) == "table" and payload.account_id or nil
    if type(account) ~= "string" or not accounts[account] then
        failure("offline_account_unavailable")
        return
    end
    if payload.match_session_id ~= nil and payload.match_session_id ~= session then
        failure("match_profile_mismatch")
        return
    end
    local preview = require("debug/offline_onboarding_test").is_enabled()
    if not preview and outcome then
        failure("offline_onboarding_not_enabled")
        return
    end
    -- Metadata is shared across profile modes, but never across matches. Only
    -- the dedicated guide preview starts required; ordinary offline QA keeps
    -- the previous unrestricted gameplay flow without consulting cloud state.
    local status = preview and (onboarding[account] or "required") or "legacy"
    if status == "required" and outcome then status = outcome end
    onboarding[account] = status
    success({ok=true, account_id=account, match_session_id=session, version=1,
        required=status == "required", status=status})
end

function provider.onboarding_state(payload, success, failure)
    onboarding_request(payload, nil, success, failure)
end

function provider.onboarding_finish(payload, success, failure)
    assert(M.is_enabled(), "offline_logic_not_enabled")
    local outcome = type(payload) == "table" and payload.outcome or nil
    if outcome ~= "completed" and outcome ~= "skipped" then
        failure("onboarding_outcome_invalid")
        return
    end
    onboarding_request(payload, outcome, success, failure)
end

function provider.archive_enabled() return false end

return M
