local json_decoder = require("core/json_decoder")
local fixture = require("config/fixtures/player_profiles")
local bindings = require("config/generated/mock_player_account_bindings")
local gameplay_stats = require("config/generated/player_gameplay_stats")

local M = {}
local decoded_fixture = nil
local account_by_player_id = {}
-- Local-only persistence layer used by the mock server packet flow.  It is
-- intentionally process-local; replacing this provider with the HTTP provider
-- removes this cache without changing the profile service contract.
local gameplay_stats_overrides_by_account = {}
local isolated_gameplay_stat_by_account = {}
local profile_revisions_by_account = {}

local function copy_table(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do
        result[copy_table(key)] = copy_table(child)
    end
    return result
end

local function gameplay_stats_defaults()
    local result = {}
    for _, row in ipairs(gameplay_stats.rows or {}) do
        if row.enabled ~= false then
            result[tostring(row.field_id)] = tonumber(row.default_value) or 0
        end
    end
    return result
end

local function gameplay_stats_neutral()
    local result = {}
    for _, row in ipairs(gameplay_stats.rows or {}) do
        if row.enabled ~= false then
            local minimum = tonumber(row.min_value)
            local neutral = 0
            if minimum ~= nil and minimum > 0 then
                neutral = tonumber(row.default_value) or minimum
            end
            result[tostring(row.field_id)] = neutral
        end
    end
    return result
end

local function ensure_fixture()
    if decoded_fixture == nil then
        decoded_fixture = json_decoder.decode(fixture.json)
    end
    return decoded_fixture
end

function M.init()
    decoded_fixture = nil
    account_by_player_id = {}
    gameplay_stats_overrides_by_account = {}
    isolated_gameplay_stat_by_account = {}
    profile_revisions_by_account = {}
    for _, row in ipairs(bindings.rows or {}) do
        if row.enabled ~= false then
            account_by_player_id[tonumber(row.player_id)] = tostring(row.account_id)
        end
    end
end

function M.persist_gameplay_stats(account_id, stats, revision)
    account_id = tostring(account_id or "")
    if account_id == "" or type(stats) ~= "table" then
        return false, "gameplay_stats_persist_invalid"
    end
    gameplay_stats_overrides_by_account[account_id] = copy_table(stats)
    isolated_gameplay_stat_by_account[account_id] = nil
    if tonumber(revision) ~= nil then
        profile_revisions_by_account[account_id] = math.floor(tonumber(revision))
    end
    return true
end


-- Keep the local mock persistence sparse too. A later same-match reload
-- expands all omitted fields to neutral values instead of restoring defaults.
function M.persist_isolated_gameplay_stat(account_id, field_id, value, revision)
    account_id = tostring(account_id or "")
    field_id = tostring(field_id or "")
    if account_id == "" or field_id == "" or tonumber(value) == nil then
        return false, "isolated_gameplay_stat_persist_invalid"
    end
    gameplay_stats_overrides_by_account[account_id] = {
        [field_id] = tonumber(value),
    }
    isolated_gameplay_stat_by_account[account_id] = field_id
    if tonumber(revision) ~= nil then
        profile_revisions_by_account[account_id] = math.floor(tonumber(revision))
    end
    return true
end

function M.resolve_account_id(player_id)
    return account_by_player_id[tonumber(player_id)]
end

function M.fetch_snapshot(account_id, on_success, on_error)
    local ok, data = pcall(ensure_fixture)
    if not ok then
        on_error("fixture_json_invalid:" .. tostring(data))
        return
    end
    local profile = data.profiles and data.profiles[tostring(account_id)]
    if type(profile) ~= "table" then
        on_error("fixture_profile_not_found")
        return
    end
    local save = {}
    for key, value in pairs(profile.save or {}) do save[key] = value end
    local isolated_field = isolated_gameplay_stat_by_account[tostring(account_id)]
    save.gameplay_stats = isolated_field and gameplay_stats_neutral()
        or gameplay_stats_defaults()
    local override = gameplay_stats_overrides_by_account[tostring(account_id)]
    if override then
        for key, value in pairs(override) do
            save.gameplay_stats[key] = value
        end
    end
    local revision = profile.revision
    local override_revision = profile_revisions_by_account[tostring(account_id)]
    if override_revision and override_revision > tonumber(revision or 0) then
        revision = override_revision
    end
    on_success({
        schema_version = data.schema_version,
        account_id = tostring(account_id),
        revision = revision,
        entitlements = profile.entitlements,
        achievements = profile.achievements,
        save = save,
        public = profile.public,
    })
end

return M
