package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local config = require("config/monster_visual_config")

local normal = assert(config.resolve(1, "normal", 1))
assert(normal.visual_asset_id == "vis_kobold_pack" and normal.visual_role == "main")
assert(normal.model_scale == 0.9, "wave 1 main scale changed")

local leader = assert(config.resolve(1, "wave_leader", nil))
assert(leader.visual_asset_id == "vis_kobold_foreman")
assert(leader.visual_role == "mini_boss" and leader.model_scale == 1.25)

local stage = assert(config.resolve(5, "assault_boss", nil))
assert(stage.visual_asset_id == "vis_spirit_bear_boss")
assert(stage.visual_role == "stage_boss" and stage.model_scale == 1.75)

local no_stage = assert(config.resolve(4, "assault_boss", nil))
assert(no_stage.visual_asset_id == "vis_ogre_bruiser",
    "assault boss did not fall back to configured mini boss")

for index = 1, 20 do
    local wave4 = assert(config.resolve(4, "normal", index))
    assert(wave4.visual_asset_id == "vis_ogre_bruiser",
        "unapproved support mix was enabled")
end

local mixed_wave = {
    main_visual_asset_id = "main",
    support_visual_asset_id = "support",
    main_scale = 1,
    support_scale = 0.8,
    support_every_nth = 5,
}
for index = 1, 12 do
    local asset_id, scale, role = config._select_role_for_test(
        mixed_wave,
        "normal",
        index
    )
    local support = index == 5 or index == 10
    assert(asset_id == (support and "support" or "main"))
    assert(scale == (support and 0.8 or 1))
    assert(role == (support and "support" or "main"))
end

local wave5_resources = config.resources_for_wave(5)
local resource_paths = {}
for _, resource in ipairs(wave5_resources) do
    resource_paths[resource.resource_type .. ":" .. resource.path] = true
end
assert(#wave5_resources == 2, "wave 5 resource deduplication changed")
assert(resource_paths["model:models/creeps/neutral_creeps/n_creep_furbolg/n_creep_furbolg_disrupter.vmdl"])
assert(resource_paths["model:models/heroes/lone_druid/spirit_bear.vmdl"])

assert(config.resolve(6, "normal", 1) == nil,
    "unimplemented wave visual unexpectedly resolved")

print("MONSTER_VISUAL_RESOLVER_PASS")