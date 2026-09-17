package.path = "scripts/vscripts/?.lua;" .. package.path
local catalog = require("config/asset_catalog")
local stages = require("config/generated/asset_native_wearable_stages").rows
local declarations = require("config/generated/asset_native_wearables").rows
local counts = {}
for _, row in ipairs(declarations) do counts[row.asset_id] = (counts[row.asset_id] or 0) + 1 end

local applied, carrier_refreshes = {}, 0
package.loaded["visual/model_appearance_service"] = {
    Matches = function(unit, asset) return applied[unit] == asset end,
    Refresh = function(unit, asset)
        applied[unit] = asset
        local components = {}
        for _, row in ipairs(asset.components) do components[row.component_id] = { owner = unit } end
        return true, asset.asset_id, components
    end,
    Clear = function(unit) applied[unit] = nil end,
}
package.loaded["visual/native_wearable_carrier_service"] = {
    IsNativeWearableAsset = function(asset) return #asset.native_wearables > 0 end,
    Matches = function() return false end,
    Has = function() return false end,
    Refresh = function()
        carrier_refreshes = carrier_refreshes + 1
        return false, "obsolete_carrier_path"
    end,
    Clear = function(unit)
        if unit.survival_native_wearable_hide_mode then
            unit.alpha = unit.survival_native_wearable_original_alpha or 255
            unit.survival_native_wearable_hide_mode = nil
        end
    end,
}
package.loaded["systems/asset_preload_service"] = { is_ready = function() return true end }
ParticleManager = {
    CreateParticle = function() return 1 end,
    DestroyParticle = function() end,
    ReleaseParticleIndex = function() end,
}
local visual = require("systems/building_visual_service")
for index, stage in ipairs(stages) do
    local asset = catalog.get(stage.asset_id)
    assert(#asset.native_wearables == counts[stage.asset_id], "native declarations registered twice")
    local unit = { model = "models/props_structures/radiant_tower001.vmdl", alpha = 0,
        survival_native_wearable_hide_mode = "render_alpha", survival_native_wearable_original_alpha = 255 }
    function unit:entindex() return index end
    function unit:SetModel(path) self.model = path; self.model_changes = (self.model_changes or 0) + 1 end
    function unit:SetOriginalModel(path) self.original_model = path end
    function unit:SetModelScale(scale) self.scale = scale end
    function unit:SetSkin(skin) self.skin = skin end
    function unit:SetRenderAlpha(alpha) self.alpha = alpha end
    local data = { model_asset_id = stage.asset_id }
    assert(visual.apply(unit, data), "hero tower fell back to the previous building model")
    assert(unit.model == stage.body_model and unit.original_model == stage.body_model and unit.alpha == 255)
    assert(applied[unit] == asset and visual.matches(unit, data), "hero components did not remain on the Building")
    assert(visual.apply(unit, data) and unit.model_changes == 1, "unchanged tower reset its main model")
    visual.clear(unit)
    assert(applied[unit] == nil)
end
assert(#stages == 21 and carrier_refreshes == 0, "tower reactivated the obsolete native carrier")
print("TOWER_HERO_VISUAL_REGRESSION_PASS stages=21")
