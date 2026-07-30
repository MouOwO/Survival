local asset_catalog = require("config/asset_catalog")
local wave_rows = require("config/generated/wave_definitions")
local monster_archetypes = require("config/generated/monster_archetypes")
local asset_preload = require("systems/asset_preload_service")

local tower_modules = {
    require("config/generated/arrow_tower_base"),
    require("config/generated/tower_class_death"),
    require("config/generated/tower_class_mystery"),
    require("config/generated/tower_class_lightning"),
    require("config/generated/tower_class_machine_gun"),
    require("config/generated/tower_class_multi"),
    require("config/generated/tower_class_frost"),
    require("config/generated/tower_class_anti_air"),
}

local M = {}

local MINIMUM_WAVE = 10
local DEFAULT_DURATION_SECONDS = 10
local SESSION_ID = "dev_models"

local function append_model(result, seen_models, seen_assets, model_path, source)
    if type(model_path) ~= "string" or model_path == ""
        or seen_models[model_path] then
        return
    end
    seen_models[model_path] = true

    local row = asset_catalog.for_model(model_path)
    if not row then
        table.insert(result.missing, {
            model_path = model_path,
            source = source,
        })
        return
    end
    if seen_assets[row.asset_id] then return end

    seen_assets[row.asset_id] = true
    table.insert(result.asset_ids, row.asset_id)
    table.insert(result.models, {
        asset_id = row.asset_id,
        model_path = model_path,
        source = source,
    })
end

function M.collect_targets(minimum_wave)
    minimum_wave = tonumber(minimum_wave) or MINIMUM_WAVE
    local result = {
        asset_ids = {},
        models = {},
        missing = {},
        minimum_wave = minimum_wave,
    }
    local seen_models = {}
    local seen_assets = {}

    for _, module in ipairs(tower_modules) do
        for _, row in ipairs(module.rows or {}) do
            if row.enabled ~= false then
                append_model(
                    result,
                    seen_models,
                    seen_assets,
                    row.model_name,
                    "tower:" .. tostring(row.record_id or row.tower_id or "unknown")
                )
            end
        end
    end

    for _, row in ipairs(wave_rows.rows or {}) do
        if row.enabled ~= false
            and (tonumber(row.wave_number) or 0) >= minimum_wave then
            local archetype = monster_archetypes.by_id[row.archetype_id]
            append_model(
                result,
                seen_models,
                seen_assets,
                archetype and archetype.model_path or nil,
                "wave:" .. tostring(row.wave_number)
                    .. ":" .. tostring(row.archetype_id)
            )
        end
    end

    result.total = #result.asset_ids
    return result
end

function M.start(options)
    options = options or {}
    local targets = M.collect_targets(options.minimum_wave)
    if #targets.missing > 0 then
        return false, "dev_asset_catalog_missing", targets
    end

    local ok, status, snapshot = asset_preload.preload_gradually(
        targets.asset_ids,
        {
            session_id = SESSION_ID,
            duration_seconds = tonumber(options.duration_seconds)
                or DEFAULT_DURATION_SECONDS,
            dispatch_ratio = tonumber(options.dispatch_ratio) or 0.8,
            retry = true,
            on_dispatched = options.on_dispatched,
            on_complete = options.on_complete,
            on_window_complete = options.on_window_complete,
        }
    )
    snapshot = snapshot or {}
    snapshot.minimum_wave = targets.minimum_wave
    snapshot.missing = #targets.missing
    return ok, status, snapshot
end

M.MINIMUM_WAVE = MINIMUM_WAVE
M.DEFAULT_DURATION_SECONDS = DEFAULT_DURATION_SECONDS

return M