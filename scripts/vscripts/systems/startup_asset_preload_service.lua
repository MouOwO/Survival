local preload = require("systems/asset_preload_service")
local catalog = require("config/asset_catalog")
local visual_config = require("config/monster_visual_config")
local archetypes = require("config/generated/monster_archetypes")
local encounters = require("config/generated/monster_encounters")
local members = require("config/generated/encounter_members")
local wave_rows = require("config/generated/wave_definitions")
local difficulties = require("config/difficulty_config")
local wave_builder = require("systems/wave_difficulty_builder")
local spawn_sequence = require("systems/wave_spawn_sequence")
local archive_definitions = require("config/generated/archive_challenge_definitions")
local endless_rules = require("config/generated/archive_endless_rules")

local M = {}
local FIRST_WAVE, LAST_WAVE = 1, 10
local manifest, configuration_error
local started = false
local dispatch_error
local REQUEST_TIMEOUT_SECONDS, RETRY_SECONDS = 90, 5
local deadlines, next_retry_at = {}, 0

local function now()
    return type(Time) == "function" and Time() or os.clock()
end

local function resource_key(resource)
    return resource.resource_type .. ":" .. resource.path
end

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

local function sorted_keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
    return result
end

local function build_manifest()
    local asset_ids, model_paths, extras, errors = {}, {}, {}, {}
    local function add_model(path)
        if nonempty(path) then model_paths[path] = true end
    end
    local function add_asset(id)
        if not nonempty(id) then return end
        if not catalog.resolve(id) then
            errors[#errors + 1] = "startup_asset_missing:" .. id
            return
        end
        asset_ids[id] = true
    end
    local function add_definition(definition, wave, row)
        if not definition or definition.enabled == false then
            errors[#errors + 1] = "startup_archetype_missing:"
                .. tostring(row and row.archetype_id or "unknown")
            return
        end
        local model = definition.model_path
        if wave and spawn_sequence.is_normal(row)
            and (row.movement_type_override or definition.movement_type) == "flying"
            and nonempty(definition.normal_flying_model_path) then
            model = definition.normal_flying_model_path
        end
        add_model(model)
        if nonempty(definition.model_asset_id) then
            add_asset(definition.model_asset_id)
        elseif not wave or wave >= 6 then
            add_asset(definition.default_wearable_asset_id)
        end
        if nonempty(definition.projectile_model) then
            extras[#extras + 1] = {
                resource_type = "particle", path = definition.projectile_model,
            }
        end
    end

    -- Build the same effective waves as wave_system for every selectable
    -- difficulty, so derived/overridden difficulty rows cannot escape preload.
    for _, difficulty in ipairs(difficulties.rows) do
        if difficulty.enabled ~= false then
            local built, reason = wave_builder.build(wave_rows.rows, difficulty.difficulty_id)
            if not built then
                errors[#errors + 1] = "startup_wave_config:"
                    .. tostring(difficulty.difficulty_id) .. ":" .. tostring(reason)
            else
                for number = FIRST_WAVE, math.min(LAST_WAVE, built.total_waves) do
                    for _, row in ipairs(built.waves[number] or {}) do
                        add_definition(archetypes.by_id[row.archetype_id], number, row)
                    end
                end
            end
        end
    end
    for number = FIRST_WAVE, LAST_WAVE do
        for _, resource in ipairs(visual_config.resources_for_wave(number)) do
            extras[#extras + 1] = resource
        end
    end

    -- Includes manual encounters, not only auto_spawn: rebirth bosses,
    -- practice-room monsters, challenge bosses and all ten-sin stage members.
    local enabled_encounters = {}
    for _, encounter in ipairs(encounters.rows) do
        if encounter.enabled ~= false then
            enabled_encounters[encounter.encounter_id] = true
            if nonempty(encounter.archetype_id) then
                add_definition(archetypes.by_id[encounter.archetype_id], nil, encounter)
            end
        end
    end
    for _, member in ipairs(members.rows) do
        if member.enabled ~= false and enabled_encounters[member.encounter_id] then
            add_definition(archetypes.by_id[member.archetype_id], nil, member)
        end
    end
    for _, definition in ipairs(archive_definitions.rows) do
        if definition.enabled ~= false then add_definition(definition) end
    end
    local endless = endless_rules.by_id.default
    if endless and endless.enabled ~= false then add_definition(endless) end

    local resources = preload.resources_for_assets(sorted_keys(asset_ids),
        preload.resources_for_models(sorted_keys(model_paths), extras))
    -- A shared model can first appear as a plain archetype model and later as
    -- an exact-model visual proxy. Preserve that proxy after deduplication.
    local proxies = {}
    for _, resource in ipairs(extras) do
        if resource.resource_type == "model" and nonempty(resource.async_unit_name) then
            proxies[resource.path] = resource.async_unit_name
        end
    end
    for _, resource in ipairs(resources) do
        if resource.resource_type == "model" and not nonempty(resource.async_unit_name) then
            resource.async_unit_name = proxies[resource.path]
        end
    end
    table.sort(resources, function(a, b)
        return a.resource_type .. ":" .. a.path < b.resource_type .. ":" .. b.path
    end)
    table.sort(errors)
    return resources, errors[1]
end

local function ensure_manifest()
    if manifest then return end
    local ok, resources, error_code = pcall(build_manifest)
    if ok then
        manifest, configuration_error = resources, error_code
    else
        manifest, configuration_error = {}, "startup_asset_configuration_failed"
    end
    if #manifest == 0 and not configuration_error then
        configuration_error = "startup_asset_manifest_empty"
    end
end

local function has_runtime_proxy(resource)
    if resource.resource_type ~= "model" then return false end
    local asset = resource.asset_id and catalog.resolve(resource.asset_id)
        or catalog.for_model(resource.path)
    -- queue_resources prioritizes the catalog over an explicit model proxy.
    -- Shared worker/monster models can resolve to an initial-only catalog row;
    -- precache those synchronously rather than routing to a nonexistent proxy.
    if asset then
        return asset.primary_model == resource.path and nonempty(asset.async_unit_name)
    end
    return nonempty(resource.async_unit_name)
end

-- Must run from the engine Precache(context) entry point. Keep opaque runtime
-- precache contexts out of init: standalone effects/attachments have no safe
-- runtime API. Main models with exact proxies still use engine async callbacks.
function M.precache(context)
    -- A fresh map can reuse Lua modules in tools. Reset the observer for the
    -- new resource lifetime; runtime retry deliberately does not do this.
    manifest, configuration_error, dispatch_error = nil, nil, nil
    started, deadlines, next_retry_at = false, {}, 0
    ensure_manifest()
    local static = {}
    for _, resource in ipairs(manifest) do
        if not has_runtime_proxy(resource) then static[#static + 1] = resource end
    end
    return preload.precache_resources(context, static)
end

local function resource_status(resource, current)
    local status = preload.resource_status(resource.resource_type, resource.path)
    -- A bundle may fail before it can mark all expanded resources. Its
    -- terminal failure must not leave this gate waiting forever.
    if status ~= "ready" and resource.asset_id then
        local asset_status = preload.status(resource.asset_id).status
        if asset_status == "failed" or asset_status == "retired" then
            status = "failed"
        end
    end
    if status ~= "ready" and status ~= "failed" and status ~= "retired"
        and deadlines[resource_key(resource)] and current >= deadlines[resource_key(resource)] then
        return "timeout"
    end
    return status
end

function M.snapshot()
    ensure_manifest()
    local ready, failed, first_failure = 0, 0, nil
    local current = now()
    for _, resource in ipairs(manifest) do
        local status = resource_status(resource, current)
        if status == "ready" then ready = ready + 1
        elseif status == "failed" or status == "retired" or status == "timeout" then
            failed = failed + 1
            local prefix = status == "timeout" and "startup_resource_timeout:" or "startup_resource_failed:"
            first_failure = first_failure or prefix .. resource_key(resource)
        end
    end
    local error_code = configuration_error or dispatch_error or first_failure
    return {
        total = #manifest, ready = ready, failed = failed,
        progress = #manifest > 0 and 100 * ready / #manifest or 0,
        complete = started and #manifest > 0 and ready == #manifest
            and failed == 0 and not error_code or false,
        error = error_code,
    }
end

-- Call after asset_preload_service.init(). Urgent requests start immediately:
-- startup must work during CUSTOM_GAME_SETUP when game time is not advancing.
-- No units are created, and no assets are retired/unloaded by this service.
function M.init()
    ensure_manifest()
    if started then return M.snapshot() end
    started = true
    local pending = {}
    local current = now()
    next_retry_at = current + RETRY_SECONDS
    for _, resource in ipairs(manifest) do
        if preload.resource_status(resource.resource_type, resource.path) ~= "ready" then
            deadlines[resource_key(resource)] = current + REQUEST_TIMEOUT_SECONDS
        end
        if preload.resource_status(resource.resource_type, resource.path) ~= "failed" then
            pending[#pending + 1] = resource
        end
    end
    local ok = pcall(preload.queue_resources, pending, { urgent = true, priority = 10000 })
    if not ok then dispatch_error = "startup_resource_dispatch_failed" end
    return M.snapshot()
end

function M.retry()
    local state = M.snapshot()
    if not started then return { ok = false, error = "startup_assets_not_started" } end
    if state.complete then return { ok = true, complete = true } end
    if configuration_error then return { ok = false, error = configuration_error } end
    local current = now()
    if current < next_retry_at then
        return { ok = false, error = "startup_assets_retry_throttled", retry_after = next_retry_at - current }
    end
    local pending = {}
    for _, resource in ipairs(manifest) do
        local status = resource_status(resource, current)
        if status == "failed" or status == "retired" or status == "timeout"
            or (dispatch_error and status ~= "ready") then
            pending[#pending + 1] = resource
        end
    end
    if #pending == 0 then return { ok = false, error = "startup_assets_still_loading" } end
    next_retry_at = current + RETRY_SECONDS
    for _, resource in ipairs(pending) do
        deadlines[resource_key(resource)] = current + REQUEST_TIMEOUT_SECONDS
    end
    dispatch_error = nil
    local called, accepted, reason = pcall(preload.retry_resources, pending, { priority = 10000 })
    if not called then dispatch_error = "startup_resource_dispatch_failed"
    elseif reason == "resource_requires_map_reload" then dispatch_error = "startup_assets_require_map_reload" end
    return { ok = called and accepted == true, error = dispatch_error or (not accepted and reason or nil),
        retry_after = RETRY_SECONDS }
end

return M
