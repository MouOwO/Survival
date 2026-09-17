package.path = "scripts/vscripts/?.lua;" .. package.path

local archetypes = require("config/generated/monster_archetypes")
local catalog = require("config/asset_catalog")
local service = require("systems/monster_hero_visual_service")
local preload = require("systems/asset_preload_service")
local count = 0
local seen = {}
for _, row in ipairs(archetypes.rows) do
    local asset_id = row.default_wearable_asset_id or ""
    if asset_id:match("^monster_wave_") then
        count = count + 1
        assert(not seen[asset_id], "outfits shared a variant-specific asset ID")
        seen[asset_id] = true
        local asset = catalog.resolve(asset_id)
        assert(asset and asset.primary_model == row.model_path)
        assert(not row.normal_flying_model_path or row.normal_flying_model_path == row.model_path,
            "formal flying wave would replace approved body with legacy Visage")
        assert(service.resolve(row, { formal_wave = true, wave_number = 12, model_path = row.model_path }) == asset)
        assert(asset.portrait_unit_name and not asset.portrait_item_def)
        local resources = preload.resources_for_assets({ asset_id })
        local paths = {}
        for _, resource in ipairs(resources) do paths[resource.path] = true end
        assert(paths[asset.primary_model], "body missing from explicit bundle preload")
        for _, component in ipairs(asset.components) do
            assert(paths[component.model_path] and component.entity_class == "prop_dynamic")
        end
        for _, effect in ipairs(asset.effects) do assert(paths[effect.particle_path]) end
    end
end
assert(count == 39, "approved monster count changed")
for _, id in ipairs({ "flying_red_gargoyle", "dragon_red_large", "dragon_red_small" }) do
    local asset = catalog.resolve(archetypes.by_id[id].default_wearable_asset_id)
    assert(#asset.components == 0 and asset.model_skin == 1, "dragon form gained humanoid components or lost fire skin")
end
for _, id in ipairs({ "demon_purple_melee", "orc_brown_small", "sea_beast_small", "armored_horned_small" }) do
    local asset = catalog.resolve(archetypes.by_id[id].default_wearable_asset_id)
    assert(asset.model_skin == 1 and #asset.effects > 0, "Diretide outfit lost skin or glow")
end
assert(archetypes.by_id.orc_longnose_large.default_wearable_asset_id ~= archetypes.by_id.orc_longnose_small.default_wearable_asset_id)
print("WAVE_MONSTER_COSMETICS_PASS monsters=" .. count)
