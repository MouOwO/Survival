-- Verify real config resolution across initial creation and all upgrade levels.
package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local buildings = require("config/buildings_config")
local mines = require("config/gold_mine_config")
local catalog = require("config/asset_catalog")
local levels = require("config/generated/building_levels")
local construction = require("config/generated/building_construction_rules")
local expected = {
    building_research_lab = "research_lab",
    building_advanced_research_lab = "advanced_research_lab",
    main_city = "main_city",
    building_farm = "population_farm",
    hero_altar = "hero_altar",
    building_challenge = "challenge_arena",
    gold_mine = "gold_mine",
}
local seen, checked = {}, 0
local function check(data, mesh)
    local path = "models/survival_buildings/" .. mesh .. ".vmdl"
    assert(data.model_name == path, mesh .. " reverted to a shared model")
    assert(data.model_scale == 1, mesh .. " must fit the requested four-cell footprint")
    assert(data.model_yaw == 0, mesh .. " must use its baked south-facing geometry")
    local asset = assert(catalog.for_model(path), "missing preload registration")
    assert(asset.enabled and asset.load_group == "initial_required")
    assert(asset.model_scale == data.model_scale, "preload scale disagrees with building scale")
    assert(asset.resident_policy == "permanent")
    local model = assert(io.open(path .. "_c", "rb"), "missing compiled model")
    assert(model:seek("end") > 1024); model:close()
    checked = checked + 1
end
for id, mesh in pairs(expected) do
    assert(not seen[mesh], "duplicate model"); seen[mesh] = true
    assert(construction.by_id[id].build_visual_scale == 1)
    local definition = assert(buildings[id], id)
    assert(definition.footprint.x == 2 and definition.footprint.y == 2)
    if id == "gold_mine" then
        assert(mines.max_mine_level == 30)
        for level = 1, mines.max_mine_level do
            check(mines.level_data(level), mesh .. string.format("_lv%02d", math.ceil(level / 3)))
        end
    else
        for level, data in pairs(definition.levels) do
            local variant = mesh
            if id == "main_city" or id == "building_farm" then
                variant = mesh .. string.format("_lv%02d", level)
            end
            check(data, variant)
        end
    end
end
for _, row in ipairs(levels.rows) do
    local id = ({building_main_city="main_city",building_gold_mine="gold_mine",building_hero_altar="hero_altar"})[row.building_id] or row.building_id
    if expected[id] then
        local mesh = expected[id]
        if id == "gold_mine" then mesh = mesh .. string.format("_lv%02d", math.ceil(row.level / 3))
        elseif id == "main_city" or id == "building_farm" then mesh = mesh .. string.format("_lv%02d", row.level) end
        assert(row.model_name == "models/survival_buildings/" .. mesh .. ".vmdl")
    end
end
assert(buildings.main_city.hull_radius == 48, "city hull must match scaled convex collider")
assert(checked == 44)
print("UNIQUE_BUILDING_MODELS_PASS variants=24 levels=" .. checked)
