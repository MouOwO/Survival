local json_decoder = require("core/json_decoder")
local json_encoder = require("core/json_encoder")
local fixture = require("config/fixtures/player_profiles")
local bindings = require("config/generated/mock_player_account_bindings")
local gameplay_stats = require("config/generated/player_gameplay_stats")

local M = {}
local decoded_fixture = nil
local active_fixture_path = nil
local account_by_player_id = {}
-- Local-only persistence layer used by the mock server packet flow. The
-- tables are same-process overrides; the JSON file is the cross-restart mock
-- store. Replacing this provider with HTTP removes both without changing the
-- profile service contract.
local gameplay_stats_overrides_by_account = {}
local isolated_gameplay_stat_by_account = {}
local profile_revisions_by_account = {}
local memory_only_notice_emitted = false

-- TODO(HTTP/Supabase): this file-backed packet is only a local server
-- substitute. Replace read/write_fixture_file with the HTTP provider after
-- the production database contract is accepted; keep the profile service
-- snapshot contract unchanged.
local FIXTURE_RELATIVE_PATH = "data/mock/player_profiles.json"

local function fixture_paths()
    local paths = {}
    local seen = {}
    local function add(path)
        path = tostring(path or ""):gsub("\\", "/")
        if path ~= "" and not seen[path] then
            seen[path] = true
            table.insert(paths, path)
        end
    end

    -- Lua launched by the standalone tests uses the addon root as cwd. Dota
    -- may launch VScript from game/, game/dota/, or game/bin/win64/, so none
    -- of those working directories can safely be assumed here.
    add(FIXTURE_RELATIVE_PATH)
    add("dota_addons/survival/" .. FIXTURE_RELATIVE_PATH)
    add("../dota_addons/survival/" .. FIXTURE_RELATIVE_PATH)
    add("../../dota_addons/survival/" .. FIXTURE_RELATIVE_PATH)
    add("game/dota_addons/survival/" .. FIXTURE_RELATIVE_PATH)

    -- Prefer a path derived from this script when the VScript loader exposes
    -- an absolute chunk source. This keeps local installations portable.
    if debug and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, 1, "S")
        local source = ok and info and tostring(info.source or "") or ""
        if string.sub(source, 1, 1) == "@" then
            source = string.sub(source, 2):gsub("\\", "/")
            local suffix = "/scripts/vscripts/systems/player_profile_providers/"
                .. "local_fixture_provider.lua"
            if string.sub(source, -string.len(suffix)) == suffix then
                add(string.sub(source, 1, string.len(source) - string.len(suffix))
                    .. "/" .. FIXTURE_RELATIVE_PATH)
            end
        end
    end

    -- Local development fallback for this workspace. Production persistence
    -- will be provided by HTTP/Supabase and must not depend on this path.
    add("D:/steam/steamapps/common/dota 2 beta/game/dota_addons/survival/"
        .. FIXTURE_RELATIVE_PATH)
    return paths
end

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
        local loaded = nil
        active_fixture_path = nil
        if io and type(io.open) == "function" then
            for _, path in ipairs(fixture_paths()) do
                local open_ok, handle = pcall(io.open, path, "rb")
                if open_ok and handle then
                    local text = handle:read("*a")
                    handle:close()
                    local ok, value = pcall(json_decoder.decode, text)
                    if ok and type(value) == "table" then
                        loaded = value
                        active_fixture_path = path
                        break
                    end
                end
            end
        end
        -- Keep the generated fixture as a read-only fallback for environments
        -- where loose-file I/O is unavailable (for example isolated tests).
        decoded_fixture = loaded or json_decoder.decode(fixture.json)
    end
    return decoded_fixture
end

local function write_fixture_file(data)
    if not io or type(io.open) ~= "function" then
        -- Dota's VScript sandbox does not expose loose-file writes. The local
        -- fixture has already been updated in decoded_fixture at this point,
        -- so keep it as a same-session mock store. This fallback belongs only
        -- to the development fixture provider; a production HTTP provider
        -- must still report a real persistence failure to the profile service.
        if not memory_only_notice_emitted then
            memory_only_notice_emitted = true
            print("[PLAYER_PROFILE_FIXTURE] file I/O unavailable; "
                .. "using same-session memory persistence")
        end
        return true, "fixture_memory_only"
    end
    if not active_fixture_path then
        return false, "fixture_file_not_resolved"
    end
    local ok, encoded = pcall(json_encoder.encode, data)
    if not ok then return false, "fixture_json_encode_failed:" .. tostring(encoded) end
    local open_ok, handle, open_error = pcall(io.open, active_fixture_path, "wb")
    if not open_ok or not handle then
        return false, "fixture_file_write_failed:path="
            .. tostring(active_fixture_path) .. ":error="
            .. tostring(open_ok and open_error or handle)
    end
    local write_ok, write_error = pcall(function()
        local written, error_message = handle:write(encoded)
        if written == nil then error(error_message) end
        handle:close()
    end)
    if write_ok then return true end
    pcall(function() handle:close() end)
    return false, "fixture_file_write_failed:path="
        .. tostring(active_fixture_path) .. ":error=" .. tostring(write_error)
end

function M.init()
    decoded_fixture = nil
    active_fixture_path = nil
    account_by_player_id = {}
    gameplay_stats_overrides_by_account = {}
    isolated_gameplay_stat_by_account = {}
    profile_revisions_by_account = {}
    memory_only_notice_emitted = false
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
    local data = ensure_fixture()
    local profile = data.profiles and data.profiles[account_id]
    if type(profile) ~= "table" then return false, "fixture_profile_not_found" end
    profile.save = profile.save or {}
    profile.save.gameplay_stats = copy_table(stats)
    profile.gameplay_stats_mode = nil
    profile.revision = tonumber(revision) or profile.revision or 0
    local persisted, persist_error = write_fixture_file(data)
    if not persisted then return false, persist_error end
    return true
end

function M.persist_save(account_id, save, revision)
    account_id = tostring(account_id or "")
    if account_id == "" or type(save) ~= "table" then
        return false, "save_persist_invalid"
    end
    local data = ensure_fixture()
    local profile = data.profiles and data.profiles[account_id]
    if type(profile) ~= "table" then return false, "fixture_profile_not_found" end
    local previous_save, previous_revision = profile.save, profile.revision
    profile.save = copy_table(save)
    profile.revision = tonumber(revision) or profile.revision or 0
    local persisted, persist_error = write_fixture_file(data)
    if not persisted then
        profile.save, profile.revision = previous_save, previous_revision
        return false, persist_error
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
    local data = ensure_fixture()
    local profile = data.profiles and data.profiles[account_id]
    if type(profile) ~= "table" then return false, "fixture_profile_not_found" end
    profile.save = profile.save or {}
    profile.save.gameplay_stats = { [field_id] = tonumber(value) }
    profile.gameplay_stats_mode = "isolated_test"
    profile.revision = tonumber(revision) or profile.revision or 0
    local persisted, persist_error = write_fixture_file(data)
    if not persisted then return false, persist_error end
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
    if isolated_field == nil and profile.gameplay_stats_mode == "isolated_test" then
        for field_id in pairs(profile.save.gameplay_stats or {}) do
            isolated_field = tostring(field_id)
            break
        end
    end
    local persisted_stats = profile.save.gameplay_stats
    save.gameplay_stats = isolated_field and gameplay_stats_neutral()
        or (type(persisted_stats) == "table"
            and copy_table(persisted_stats) or gameplay_stats_defaults())
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
