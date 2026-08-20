local json_decoder = require("core/json_decoder")
local fixture = require("config/fixtures/player_profiles")
local bindings = require("config/generated/mock_player_account_bindings")
local gameplay_stats = require("config/generated/player_gameplay_stats")

local M = {}
local decoded_fixture = nil
local account_by_player_id = {}

local function gameplay_stats_defaults()
    local result = {}
    for _, row in ipairs(gameplay_stats.rows or {}) do
        if row.enabled ~= false then
            result[tostring(row.field_id)] = tonumber(row.default_value) or 0
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
    for _, row in ipairs(bindings.rows or {}) do
        if row.enabled ~= false then
            account_by_player_id[tonumber(row.player_id)] = tostring(row.account_id)
        end
    end
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
    save.gameplay_stats = gameplay_stats_defaults()
    on_success({
        schema_version = data.schema_version,
        account_id = tostring(account_id),
        revision = profile.revision,
        entitlements = profile.entitlements,
        achievements = profile.achievements,
        save = save,
        public = profile.public,
    })
end

return M
