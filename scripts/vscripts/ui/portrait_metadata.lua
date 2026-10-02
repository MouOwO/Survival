local asset_catalog = require("config/asset_catalog")

local M = {}

-- Shared presentation-only metadata; callers pass a UI snapshot copy.
function M.apply(unit, snapshot)
    snapshot = snapshot or {}
    snapshot.model_asset_id = ""
    snapshot.portrait_unit_name = ""
    snapshot.portrait_item_def = ""

    if not unit then return snapshot end
    local asset_id = tostring(unit.survival_model_asset_id or "")
    if asset_id == "" then
        -- Monster hero visuals keep their asset identity separately from the
        -- building model_asset_id field; use it for the independent portrait
        -- ScenePanel without changing the world appearance ownership.
        asset_id = tostring(unit.survival_monster_default_wearable_asset_id or "")
    end
    local asset = asset_catalog.get(asset_id)
    if not asset then
        local hero_id = tostring(unit.survival_hero_id or "")
        if hero_id == "" then hero_id = tostring(snapshot.hero_id or "") end
        if hero_id ~= "" then
            asset_id = "hero_permanent_" .. hero_id
            asset = asset_catalog.get(asset_id)
        end
    end
    if not asset and unit.survival_monkey_king_clone == true then
        asset_id = "hero_permanent_hero_monkey_king"
        asset = asset_catalog.get(asset_id)
    end
    if not asset then return snapshot end

    snapshot.model_asset_id = tostring(asset.asset_id or asset_id or "")
    -- Native wearable tower stages, Boss hero bundles, and explicitly opted-in
    -- permanent heroes use the custom portrait ScenePanel. Their world model is
    -- intentionally independent of the portrait unit, so the client can render
    -- the standard Valve hero portrait while the selected entity keeps its
    -- decorated body in-world.
    local is_boss_portrait = asset.load_group == "monster_default_wearables"
        and tostring(asset.portrait_unit_name or "") ~= ""
    local is_split_hero_portrait = (asset.asset_id == "hero_permanent_hero_blademaster"
        or asset.asset_id == "hero_permanent_hero_doom")
        and tostring(asset.portrait_unit_name or "") ~= ""
    local is_seven_sins_portrait = asset.asset_id
        == "challenge_monster_terrorblade_fractal_horns"
        and asset.portrait_unit_name == "npc_dota_hero_terrorblade"
    local is_challenge_portrait = tostring(asset.asset_id or ""):find("challenge_monster_", 1, true) == 1
        and tostring(asset.portrait_unit_name or ""):find("npc_dota_hero_", 1, true) == 1
    if asset.native_wearable_stage == nil
        and not is_challenge_portrait
        and not is_seven_sins_portrait
        and not is_boss_portrait
        and not is_split_hero_portrait then
        return snapshot
    end
    snapshot.portrait_unit_name = tostring(asset.portrait_unit_name or "")
    snapshot.portrait_item_def = tostring(asset.portrait_item_def or "")
    return snapshot
end

return M
