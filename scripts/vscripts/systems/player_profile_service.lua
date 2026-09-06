local event_bus = require("core/event_bus")
local events = require("core/events")
local logger = require("core/logger")
local json_decoder = require("core/json_decoder")
local entitlement_service = require("systems/player_entitlement_service")
local rules = require("config/generated/player_profile_rules")
local public_fields = require("config/generated/player_profile_public_fields")
local gameplay_stats = require("config/generated/player_gameplay_stats")
local achievement_definitions = require("config/generated/achievement_definitions")
local entitlement_definitions = require("config/generated/entitlement_definitions")

local M = {}
local profiles_by_player = {}
local player_by_account = {}
local provider = nil
local provider_id = nil
local injected_provider = false
local active_rule = nil
local load_generation_by_player = {}
local revision_high_water_by_account = {}

local function register_server_convar(name, default_value)
    if Convars and type(Convars.RegisterConvar) == "function" then
        pcall(function()
            Convars:RegisterConvar(name, default_value, "Survival server config", 0)
        end)
    end
end

local function configured_provider_id()
    local result = tostring(active_rule and active_rule.provider_id or "")
    if Convars and type(Convars.GetStr) == "function" then
        local override = tostring(
            Convars:GetStr("survival_player_profile_provider") or ""
        )
        if override ~= "" then result = override end
    end
    return result
end

local function ensure_provider()
    if injected_provider then return provider ~= nil end
    local next_provider_id = configured_provider_id()
    if not string.match(next_provider_id, "^[a-z][a-z0-9_]*$") then
        return false, "player profile provider_id invalid: " .. next_provider_id
    end
    if provider ~= nil and provider_id == next_provider_id then return true end
    local ok, next_provider = pcall(
        require,
        "systems/player_profile_providers/" .. next_provider_id .. "_provider"
    )
    if not ok then
        return false, "profile_provider_load_failed:" .. tostring(next_provider)
    end
    if type(next_provider.init) ~= "function"
        or type(next_provider.resolve_account_id) ~= "function"
        or type(next_provider.fetch_snapshot) ~= "function" then
        return false, "player profile provider contract invalid"
    end
    next_provider.init()
    provider = next_provider
    provider_id = next_provider_id
    logger.info("PlayerProfile", "provider_initialized provider_id=" .. provider_id)
    return true
end

local function copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local function integer(value)
    return type(value) == "number" and value >= 0 and value == math.floor(value)
end

local function validate_entitlements(value)
    if type(value) ~= "table" or value == json_decoder.null then
        return false, "entitlements_invalid"
    end
    for entitlement_id, state in pairs(value) do
        local definition = entitlement_definitions.by_id[entitlement_id]
        if type(entitlement_id) ~= "string" or definition == nil
            or definition.enabled == false or type(state) ~= "table"
            or type(state.active) ~= "boolean" then
            return false, "entitlement_state_invalid:" .. tostring(entitlement_id)
        end
    end
    return true
end

local function validate_achievements(value)
    if type(value) ~= "table" or value == json_decoder.null then
        return false, "achievements_invalid"
    end
    for achievement_id, state in pairs(value) do
        local definition = achievement_definitions.by_id[achievement_id]
        if definition == nil or type(state) ~= "table"
            or not integer(state.progress)
            or type(state.unlocked) ~= "boolean" then
            return false, "achievement_state_invalid:" .. tostring(achievement_id)
        end
    end
    return true
end

local function validate_gameplay_stats(value)
    if type(value) ~= "table" or value == json_decoder.null then
        return false, "gameplay_stats_invalid"
    end
    for _, definition in ipairs(gameplay_stats.rows or {}) do
        if definition.enabled ~= false then
            local field_id = tostring(definition.field_id)
            local number = value[field_id]
            if type(number) ~= "number" then
                return false, "gameplay_stat_invalid:" .. field_id
            end
            if definition.storage_type == "integer" and number ~= math.floor(number) then
                return false, "gameplay_stat_not_integer:" .. field_id
            end
            if definition.min_value ~= nil and number < tonumber(definition.min_value) then
                return false, "gameplay_stat_below_min:" .. field_id
            end
            if definition.max_value ~= nil and number > tonumber(definition.max_value) then
                return false, "gameplay_stat_above_max:" .. field_id
            end
        end
    end
    return true
end

local function gameplay_stats_defaults()
    local result = {}
    for _, definition in ipairs(gameplay_stats.rows or {}) do
        if definition.enabled ~= false then
            result[tostring(definition.field_id)] = tonumber(definition.default_value) or 0
        end
    end
    return result
end

-- Isolated gameplay-stat packets are deliberately sparse: the mock JSON only
-- carries the one field under test. Expand that payload into a schema-valid
-- neutral snapshot at the profile boundary. Absolute fields whose schema
-- cannot accept zero retain their authored default value.
local function isolated_gameplay_stats(patch)
    if type(patch) ~= "table" or patch == json_decoder.null then
        return nil, "isolated_gameplay_stats_invalid"
    end
    local result = {}
    local field_count = 0
    for _, definition in ipairs(gameplay_stats.rows or {}) do
        if definition.enabled ~= false then
            local field_id = tostring(definition.field_id)
            local minimum = tonumber(definition.min_value)
            local neutral = 0
            if minimum ~= nil and minimum > 0 then
                neutral = tonumber(definition.default_value) or minimum
            end
            result[field_id] = neutral
        end
    end
    for field_id, value in pairs(patch) do
        local definition = gameplay_stats.by_id[tostring(field_id)]
        if not definition or definition.enabled == false then
            return nil, "gameplay_stat_unknown:" .. tostring(field_id)
        end
        if type(value) ~= "number" or value ~= value
            or value == math.huge or value == -math.huge then
            return nil, "gameplay_stat_invalid:" .. tostring(field_id)
        end
        field_count = field_count + 1
        result[tostring(field_id)] = value
    end
    if field_count ~= 1 then
        return nil, "isolated_gameplay_stats_requires_one_field"
    end
    return result
end

local function fill_gameplay_stats_defaults(value)
    for _, definition in ipairs(gameplay_stats.rows or {}) do
        if definition.enabled ~= false then
            local field_id = tostring(definition.field_id)
            if value[field_id] == nil then
                value[field_id] = tonumber(definition.default_value) or 0
            end
        end
    end
    return value
end

local function validate_snapshot(snapshot, expected_account_id)
    if type(snapshot) ~= "table" then
        return false, "snapshot_invalid"
    end
    if tonumber(snapshot.schema_version) ~= tonumber(active_rule.schema_version) then
        return false, "schema_version_unsupported"
    end
    if type(snapshot.account_id) ~= "string" or snapshot.account_id == ""
        or snapshot.account_id ~= tostring(expected_account_id or "") then
        return false, "account_id_mismatch"
    end
    if not integer(snapshot.revision) then
        return false, "revision_invalid"
    end
    local ok, reason = validate_entitlements(snapshot.entitlements)
    if not ok then
        return false, reason
    end
    ok, reason = validate_achievements(snapshot.achievements)
    if not ok then
        return false, reason
    end
    if type(snapshot.save) ~= "table" or snapshot.save == json_decoder.null
        or type(snapshot.public) ~= "table" or snapshot.public == json_decoder.null then
        return false, "profile_sections_invalid"
    end
    if snapshot.save.gameplay_stats == nil
        or snapshot.save.gameplay_stats == json_decoder.null then
        snapshot.save.gameplay_stats = gameplay_stats_defaults()
    else
        fill_gameplay_stats_defaults(snapshot.save.gameplay_stats)
    end
    ok, reason = validate_gameplay_stats(snapshot.save.gameplay_stats)
    if not ok then
        return false, reason
    end
    return true
end

local function public_value(profile, row)
    local section = tostring(row.source_section or "")
    local key = tostring(row.source_key or "")
    local raw = nil
    if section == "entitlements" then
        local state = profile.entitlements[key]
        raw = state and state.active or false
    else
        local source = profile[section]
        raw = type(source) == "table" and source[key] or nil
    end
    if raw == nil or raw == "" then
        raw = row.default_value
    end
    local value_type = tostring(row.value_type or "string")
    if value_type == "boolean" then
        return raw == true or raw == 1 or raw == "1" or raw == "true"
    end
    if value_type == "number" then
        return tonumber(raw) or 0
    end
    return tostring(raw or "")
end

local function publish_empty_public_profile(player_id, reason)
    if active_rule.publish_public_profiles == false or not CustomNetTables then
        return
    end
    local projection = {
        schema_version = tonumber(active_rule.schema_version),
        revision = 0,
        player_id = player_id,
        reason = tostring(reason or "profile_unavailable"),
    }
    for _, row in ipairs(public_fields.rows or {}) do
        if row.enabled ~= false then
            local value_type = tostring(row.value_type or "string")
            if value_type == "boolean" then
                projection[tostring(row.field_id)] = false
            elseif value_type == "number" then
                projection[tostring(row.field_id)] = tonumber(row.default_value) or 0
            else
                projection[tostring(row.field_id)] = tostring(row.default_value or "")
            end
        end
    end
    CustomNetTables:SetTableValue(
        "survival_player_public_profiles",
        tostring(player_id),
        projection
    )
end

local function invalidate_player(player_id, reason)
    local previous = profiles_by_player[player_id]
    if previous then
        player_by_account[previous.account_id] = nil
    end
    profiles_by_player[player_id] = nil
    entitlement_service.replace_all(
        player_id,
        {},
        "player_profile:" .. tostring(reason or "invalidated")
    )
    publish_empty_public_profile(player_id, reason)
    if previous then
        event_bus.emit(events.PLAYER_PROFILE_CHANGED, {
            player_id = player_id,
            account_id = previous.account_id,
            revision = 0,
            reason = tostring(reason or "invalidated"),
        })
    end
end

local function publish_public_profile(player_id, reason)
    if active_rule.publish_public_profiles == false or not CustomNetTables then
        return
    end
    local profile = profiles_by_player[player_id]
    if not profile then
        return
    end
    local projection = {
        schema_version = tonumber(active_rule.schema_version),
        revision = profile.revision,
        player_id = player_id,
        reason = tostring(reason or "profile_changed"),
    }
    for _, row in ipairs(public_fields.rows or {}) do
        if row.enabled ~= false then
            projection[tostring(row.field_id)] = public_value(profile, row)
        end
    end
    CustomNetTables:SetTableValue(
        "survival_player_public_profiles",
        tostring(player_id),
        projection
    )
    local diagnostic_account_id = "<redacted>"
    local diagnostic_provider_id = provider_id or tostring(active_rule.provider_id)
    if diagnostic_provider_id == "local_fixture" then
        diagnostic_account_id = tostring(profile.account_id)
    end
    logger.info("PlayerProfile", string.format(
        "public_profile_published provider_id=%s player_id=%s account_id=%s revision=%s title_id=%s achievement_score=%s vip_badge=%s highest_difficulty=%s reason=%s",
        diagnostic_provider_id,
        tostring(player_id),
        diagnostic_account_id,
        tostring(projection.revision),
        tostring(projection.title_id),
        tostring(projection.achievement_score),
        tostring(projection.vip_badge),
        tostring(projection.highest_difficulty),
        tostring(projection.reason)
    ))
end

local function entitlement_projection(profile)
    local result = {}
    for entitlement_id, state in pairs(profile.entitlements) do
        result[entitlement_id] = state.active == true
    end
    return result
end

local function remember_update(profile, update_id)
    profile.processed_update_ids[update_id] = true
    profile.processed_update_order[#profile.processed_update_order + 1] = update_id
    local maximum = tonumber(active_rule.max_processed_update_ids) or 128
    while #profile.processed_update_order > maximum do
        local oldest = table.remove(profile.processed_update_order, 1)
        profile.processed_update_ids[oldest] = nil
    end
end

local function commit_snapshot(player_id, snapshot, reason)
    local previous = profiles_by_player[player_id]
    if previous and previous.account_id ~= snapshot.account_id then
        player_by_account[previous.account_id] = nil
    end
    local profile = {
        schema_version = snapshot.schema_version,
        account_id = snapshot.account_id,
        revision = snapshot.revision,
        entitlements = copy(snapshot.entitlements),
        achievements = copy(snapshot.achievements),
        save = copy(snapshot.save),
        public = copy(snapshot.public),
        processed_update_ids = {},
        processed_update_order = {},
    }
    profiles_by_player[player_id] = profile
    player_by_account[profile.account_id] = player_id
    revision_high_water_by_account[profile.account_id] = math.max(
        tonumber(revision_high_water_by_account[profile.account_id]) or 0,
        profile.revision
    )
    entitlement_service.replace_all(
        player_id,
        entitlement_projection(profile),
        "player_profile:" .. tostring(reason or "snapshot")
    )
    publish_public_profile(player_id, reason)
    event_bus.emit(events.PLAYER_PROFILE_CHANGED, {
        player_id = player_id,
        account_id = profile.account_id,
        revision = profile.revision,
        reason = tostring(reason or "snapshot"),
    })
end

local function merge_section(target, patch)
    for key, value in pairs(patch) do
        if value == json_decoder.null then
            target[key] = nil
        else
            target[key] = copy(value)
        end
    end
end

function M.apply_snapshot(player_id, snapshot, reason)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    local account_id = tostring(snapshot and snapshot.account_id or "")
    local ok, validation_error = validate_snapshot(snapshot, account_id)
    if not ok then
        return { ok = false, error = validation_error }
    end
    local existing_player_id = player_by_account[account_id]
    if existing_player_id ~= nil and existing_player_id ~= player_id then
        return { ok = false, error = "account_already_bound" }
    end
    local current = profiles_by_player[player_id]
    local high_water = tonumber(revision_high_water_by_account[account_id]) or 0
    if snapshot.revision < high_water then
        return {
            ok = false,
            error = "snapshot_revision_stale",
            current_revision = high_water,
        }
    end
    commit_snapshot(player_id, snapshot, reason or "snapshot_applied")
    return { ok = true, account_id = account_id, revision = snapshot.revision }
end

function M.load_player(player_id, reason, on_success, on_error)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    invalidate_player(player_id, "loading")
    local provider_ok, provider_error = ensure_provider()
    if not provider_ok then
        logger.warn("PlayerProfile", tostring(provider_error))
        return { ok = false, error = tostring(provider_error) }
    end
    local resolve_ok, account_id = pcall(provider.resolve_account_id, player_id)
    if not resolve_ok then
        return {
            ok = false,
            error = "account_resolve_failed:" .. tostring(account_id),
        }
    end
    if type(account_id) ~= "string" or account_id == "" then
        return { ok = false, error = "account_id_unavailable" }
    end
    local generation = (load_generation_by_player[player_id] or 0) + 1
    load_generation_by_player[player_id] = generation
    local completed = false
    local result = { ok = true, pending = true, generation = generation }
    local fetch_ok, fetch_error = pcall(provider.fetch_snapshot, account_id, function(snapshot)
        if load_generation_by_player[player_id] ~= generation or completed then
            return
        end
        completed = true
        if tostring(snapshot and snapshot.account_id or "") ~= tostring(account_id) then
            result = { ok = false, pending = false, error = "account_id_mismatch" }
            logger.warn("PlayerProfile", result.error)
            return
        end
        result = M.apply_snapshot(
            player_id,
            snapshot,
            reason or "snapshot_loaded"
        )
        result.pending = false
        if not result.ok then
            logger.warn("PlayerProfile", tostring(result.error))
            if type(on_error) == "function" then on_error(result.error) end
        elseif type(on_success) == "function" then
            on_success(result)
        end
    end, function(fetch_error_message)
        if load_generation_by_player[player_id] ~= generation or completed then
            return
        end
        completed = true
        result = { ok = false, pending = false, error = tostring(fetch_error_message) }
        logger.warn("PlayerProfile", tostring(fetch_error_message))
        if type(on_error) == "function" then on_error(result.error) end
    end)
    if not fetch_ok and load_generation_by_player[player_id] == generation
        and not completed then
        completed = true
        result = {
            ok = false,
            pending = false,
            error = "provider_fetch_failed:" .. tostring(fetch_error),
        }
        if type(on_error) == "function" then on_error(result.error) end
        logger.warn("PlayerProfile", result.error)
    end
    if completed then
        return result
    end
    return result
end

function M.apply_incremental(update)
    if type(update) == "string" then
        local ok, decoded = pcall(json_decoder.decode, update)
        if not ok then
            return { ok = false, error = "update_json_invalid" }
        end
        update = decoded
    end
    if type(update) ~= "table"
        or tonumber(update.schema_version) ~= tonumber(active_rule.schema_version) then
        return { ok = false, error = "schema_version_unsupported" }
    end
    local account_id = tostring(update.account_id or "")
    local player_id = player_by_account[account_id]
    local profile = player_id and profiles_by_player[player_id] or nil
    if not profile then
        return { ok = false, error = "profile_not_loaded", reload_required = true }
    end
    local update_id = tostring(update.update_id or "")
    if update_id == "" then
        return { ok = false, error = "update_id_invalid" }
    end
    if profile.processed_update_ids[update_id] then
        return { ok = true, duplicate = true, revision = profile.revision }
    end
    if not integer(update.base_revision) or update.base_revision ~= profile.revision then
        return { ok = false, error = "base_revision_mismatch", reload_required = true,
            current_revision = profile.revision }
    end
    if not integer(update.revision) or update.revision ~= update.base_revision + 1 then
        return { ok = false, error = "revision_gap", reload_required = true,
            current_revision = profile.revision }
    end
    local changes = update.changes
    if type(changes) ~= "table" or changes == json_decoder.null then
        return { ok = false, error = "changes_invalid" }
    end
    local gameplay_stats_mode = update.gameplay_stats_mode
    if gameplay_stats_mode ~= nil and gameplay_stats_mode ~= "isolated_test" then
        return { ok = false, error = "gameplay_stats_mode_unsupported" }
    end
    if gameplay_stats_mode == "isolated_test" then
        local save_patch = changes.save
        local sparse = type(save_patch) == "table"
            and save_patch.gameplay_stats or nil
        local expanded, isolation_error = isolated_gameplay_stats(sparse)
        if not expanded then
            return { ok = false, error = isolation_error }
        end
        changes = copy(changes)
        changes.save = copy(save_patch)
        changes.save.gameplay_stats = expanded
    end
    local allowed_sections = {
        entitlements = true,
        achievements = true,
        save = true,
        public = true,
    }
    for section in pairs(changes) do
        if not allowed_sections[section] then
            return { ok = false, error = "change_section_invalid:" .. tostring(section) }
        end
    end
    local next_profile = copy(profile)
    for _, section in ipairs({ "entitlements", "achievements", "save", "public" }) do
        local patch = changes[section]
        if patch ~= nil then
            if type(patch) ~= "table" or patch == json_decoder.null then
                return { ok = false, error = section .. "_patch_invalid" }
            end
            merge_section(next_profile[section], patch)
        end
    end
    local ok, validation_error = validate_entitlements(next_profile.entitlements)
    if ok then
        ok, validation_error = validate_achievements(next_profile.achievements)
    end
    if ok then
        ok, validation_error = validate_gameplay_stats(
            next_profile.save and next_profile.save.gameplay_stats
        )
    end
    if not ok then
        return { ok = false, error = validation_error }
    end
    next_profile.revision = update.revision
    remember_update(next_profile, update_id)
    profiles_by_player[player_id] = next_profile
    revision_high_water_by_account[next_profile.account_id] = math.max(
        tonumber(revision_high_water_by_account[next_profile.account_id]) or 0,
        next_profile.revision
    )
    entitlement_service.replace_all(
        player_id,
        entitlement_projection(next_profile),
        "player_profile:incremental"
    )
    publish_public_profile(player_id, "incremental")
    event_bus.emit(events.PLAYER_PROFILE_CHANGED, {
        player_id = player_id,
        account_id = next_profile.account_id,
        revision = next_profile.revision,
        reason = "incremental",
    })
    return { ok = true, revision = next_profile.revision }
end

local function get_profile_request(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    local profile = M.get_profile(player_id)
    if not profile then
        return { ok = false, error = "profile_not_loaded" }
    end
    return { ok = true, profile = profile }
end

function M.get_provider()
    if not ensure_provider() then return nil end
    return provider
end

function M.get_profile(player_id)
    local profile = profiles_by_player[tonumber(player_id)]
    return profile and copy(profile) or nil
end

-- Atomically replace one or more private save subsections. The candidate is
-- validated and persisted before it becomes the live profile, so inventory
-- ownership and a lottery item's gameplay-stat deltas cannot split across
-- two revisions.
function M.update_save_sections(player_id, replacements, reason)
    -- HTTP-authoritative rooms must never acknowledge a local-only permanent write.
    if provider and provider.archive_enabled and provider.archive_enabled() then
        return { ok = false, error = "remote_save_requires_server_transaction" }
    end
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 or type(replacements) ~= "table" then
        return { ok = false, error = "save_sections_invalid" }
    end
    local profile = profiles_by_player[player_id]
    if not profile or type(profile.save) ~= "table" then
        return { ok = false, error = "profile_not_loaded" }
    end
    local next_profile = copy(profile)
    local replacement_count = 0
    for raw_section, value in pairs(replacements) do
        local section = tostring(raw_section or "")
        if section == "" or type(value) ~= "table"
            or value == json_decoder.null then
            return { ok = false, error = "save_section_invalid:" .. section }
        end
        next_profile.save[section] = copy(value)
        replacement_count = replacement_count + 1
    end
    if replacement_count == 0 then
        return { ok = false, error = "save_sections_empty" }
    end
    local valid, validation_error = validate_gameplay_stats(
        next_profile.save.gameplay_stats)
    if not valid then return { ok = false, error = validation_error } end
    next_profile.revision = (tonumber(profile.revision) or 0) + 1
    if provider and type(provider.persist_save) == "function" then
        local persisted, persist_error = provider.persist_save(
            next_profile.account_id, next_profile.save, next_profile.revision)
        if persisted == false then
            return { ok = false, error = tostring(persist_error or "save_persist_failed") }
        end
    end
    profiles_by_player[player_id] = next_profile
    revision_high_water_by_account[next_profile.account_id] = math.max(
        tonumber(revision_high_water_by_account[next_profile.account_id]) or 0,
        next_profile.revision
    )
    publish_public_profile(player_id, reason or "save_changed")
    event_bus.emit(events.PLAYER_PROFILE_CHANGED, {
        player_id = player_id,
        account_id = next_profile.account_id,
        revision = next_profile.revision,
        reason = tostring(reason or "save_changed"),
    })
    return { ok = true, revision = next_profile.revision }
end

-- Apply a small account-scoped save section update from a server subsystem.
function M.update_save_section(player_id, section, value, reason)
    section = tostring(section or "")
    if section == "" then return { ok = false, error = "save_section_invalid" } end
    return M.update_save_sections(player_id, { [section] = value }, reason)
end

function M.get_public_profile(player_id)
    local profile = profiles_by_player[tonumber(player_id)]
    if not profile then
        return nil
    end
    local result = { schema_version = active_rule.schema_version,
        revision = profile.revision, player_id = tonumber(player_id) }
    for _, row in ipairs(public_fields.rows or {}) do
        if row.enabled ~= false then
            result[tostring(row.field_id)] = public_value(profile, row)
        end
    end
    return result
end

function M.init(options)
    profiles_by_player = {}
    player_by_account = {}
    load_generation_by_player = {}
    revision_high_water_by_account = {}
    register_server_convar("survival_player_profile_provider", "")
    register_server_convar("survival_fishing_api_token", "")
    register_server_convar("survival_fishing_reward_fixture", "")
    register_server_convar("survival_archive_http_enabled", "0")
    active_rule = nil
    for _, row in ipairs(rules.rows or {}) do
        if row.enabled ~= false then
            active_rule = row
            break
        end
    end
    if not active_rule then
        error("player profile rule missing")
    end
    provider = nil
    provider_id = nil
    injected_provider = options and options.provider ~= nil or false
    if injected_provider then
        provider = options.provider
        provider_id = "injected"
        if type(provider.init) ~= "function"
            or type(provider.resolve_account_id) ~= "function"
            or type(provider.fetch_snapshot) ~= "function" then
            error("player profile provider contract invalid")
        end
        provider.init()
    end
    event_bus.handle_request(events.PLAYER_PROFILE_GET_REQUEST, get_profile_request)
    if active_rule.load_on_hero_ready ~= false then
        event_bus.subscribe(events.HERO_READY, function(payload)
            M.load_player(payload.player_id, "hero_ready")
        end)
    end
end

return M
