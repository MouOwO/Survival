local catalog = require("config/asset_catalog")
local appearance = require("visual/model_appearance_service")
local logger = require("core/logger")

local M = {}

local function valid(entity)
    return entity and (type(entity.IsNull) ~= "function" or not entity:IsNull())
end

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

local function requested_asset_id(archetype, options)
    if type(archetype) ~= "table" then return nil, "archetype_missing" end
    options = options or {}

    -- Explicit challenge outfits always win over a default hero package.
    if nonempty(archetype.model_asset_id) then return nil, "special_outfit" end
    if options.special_outfit == true or options.persona == true
        or options.alternate_form == true or options.summoned == true then
        return nil, "excluded_identity"
    end

    local wave_number = tonumber(options.wave_number)
    if options.formal_wave == true
        and (not wave_number or wave_number < 6 or wave_number > 30) then
        return nil, "neutral_wave_visual"
    end
    if wave_number and (wave_number < 6 or wave_number > 30)
        and options.allow_outside_formal_wave ~= true then
        return nil, "wave_out_of_range"
    end

    local asset_id = tostring(
        options.default_wearable_asset_id
            or archetype.default_wearable_asset_id or ""
    )
    if asset_id == "" then return nil, "default_wearable_not_declared" end
    local asset = catalog.resolve(asset_id)
    if not asset or asset.asset_type ~= "model_bundle"
        or not nonempty(asset.primary_model) then
        return nil, "default_wearable_asset_invalid"
    end
    if options.model_path and options.model_path ~= asset.primary_model then
        return nil, "model_asset_mismatch"
    end
    return asset_id
end

function M.resolve(archetype, options)
    local asset_id, reason = requested_asset_id(archetype, options)
    if not asset_id then return nil, reason end
    return catalog.resolve(asset_id), nil
end

function M.apply(unit, archetype, options)
    if not valid(unit) then return false, "invalid_unit" end
    local asset, reason = M.resolve(archetype, options)
    if not asset then return false, reason end
    local ok, status = appearance.Apply(unit, asset)
    if not ok then
        logger.warn("MonsterHeroVisual", "apply failed asset="
            .. tostring(asset.asset_id) .. " reason=" .. tostring(status))
        return false, status or "appearance_apply_failed"
    end
    unit.survival_monster_default_wearable_asset_id = asset.asset_id
    return true, asset.asset_id
end

function M.clear(unit)
    if not valid(unit) then return false end
    -- Do not clear a challenge-specific appearance that this service did not
    -- create. Special outfits use the existing challenge visual service.
    if unit.survival_monster_default_wearable_asset_id ~= nil then
        appearance.Clear(unit)
    end
    unit.survival_monster_default_wearable_asset_id = nil
    return true
end

function M.precache_asset(asset_id, context)
    local asset = catalog.resolve(asset_id)
    if not asset or not nonempty(asset.primary_model) then return false end
    local ok = pcall(PrecacheResource, "model", asset.primary_model, context)
    for _, component in ipairs(asset.components or {}) do
        ok = pcall(PrecacheResource, "model", component.model_path, context) and ok
    end
    return ok
end

function M._asset_id_for_test(archetype, options)
    return requested_asset_id(archetype, options)
end

return M