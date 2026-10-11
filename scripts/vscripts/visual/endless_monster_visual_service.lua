local appearance = require("visual/model_appearance_service")
local details = require("visual/monster_cosmetic_details")
local ornaments = require("visual/endless_monster_ornaments")

local M = {}

local function valid(unit)
    return unit and (type(unit.IsNull) ~= "function" or not unit:IsNull())
end

local function call(unit, name, ...)
    if unit and type(unit[name]) == "function" then
        local ok, result = pcall(unit[name], unit, ...)
        return ok and result ~= false, result
    end
    return false
end

function M.clear(unit)
    if not unit then return false end
    if not unit.survival_endless_monster_visual
        and not unit.survival_endless_monster_ornaments_state then return true end
    -- Clear our ownership first: native removal can re-enter death cleanup.
    local owned = unit.survival_endless_monster_visual
    unit.survival_endless_monster_visual = nil
    unit.survival_endless_visual_id = nil
    ornaments.clear(unit)
    if owned then
        details.clear(unit)
        appearance.Clear(unit)
    end
    return true
end

function M.on_death(unit)
    if not unit then return false end
    if unit.survival_endless_monster_visual then details.stop_particles(unit) end
    if valid(unit) and unit.survival_monster_corpse == true
        and unit.survival_wave_cleanup ~= true then return true end
    return M.clear(unit)
end

function M.apply(unit, visual)
    if not valid(unit) then return false, "invalid_unit" end
    if type(visual) ~= "table" or not visual.visual_id or not visual.model_path then
        return false, "endless_visual_missing"
    end
    -- Each wave owns a cached immutable row. Copy only native component scale
    -- overrides; never write a unit or scaled transforms back into config.
    local asset = {}
    for key, value in pairs(visual) do asset[key] = value end
    asset.components = {}
    for _, component in ipairs(visual.components or {}) do
        local copy = {}
        for key, value in pairs(component) do copy[key] = value end
        copy.model_scale = (tonumber(component.model_scale) or 1) * visual.model_scale
        asset.components[#asset.components + 1] = copy
    end
    local previous = unit.survival_endless_monster_visual
    if previous and previous.visual == visual and appearance.Matches(unit, asset) then
        local ok, reason = ornaments.apply(unit, visual)
        return ok, reason
    end
    M.clear(unit)
    -- Register before native calls so failure or a nested cleanup owns all
    -- subsequently created components, even before appearance is committed.
    local state = { visual = visual, asset = asset }
    unit.survival_endless_monster_visual = state
    local ok, reason = pcall(function()
        local has_model, current = call(unit, "GetModelName")
        if not has_model or current ~= visual.model_path then
            assert(call(unit, "SetModel", visual.model_path), "endless_model_set_failed")
            call(unit, "SetOriginalModel", visual.model_path)
        end
        assert(call(unit, "SetModelScale", visual.model_scale), "endless_scale_set_failed")
        local applied, status, native_components = appearance.Apply(unit, asset, { fresh_unit = true })
        assert(applied, status or "endless_components_failed")
        assert(unit.survival_endless_monster_visual == state and valid(unit), "endless_visual_superseded")
        details.apply(unit, asset, native_components)
        local ornament_ok, ornament_reason = ornaments.apply(unit, visual)
        assert(ornament_ok, ornament_reason or "endless_ornaments_failed")
        assert(unit.survival_endless_monster_visual == state and valid(unit), "endless_visual_superseded")
        call(unit, "ResetSequenceInfo")
        call(unit, "SetPlaybackRate", 1)
    end)
    if not ok then
        if unit.survival_endless_monster_visual == state then M.clear(unit) end
        return false, tostring(reason)
    end
    unit.survival_endless_visual_id = visual.visual_id
    return true, visual.visual_id
end

return M
