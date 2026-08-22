package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local expected_model = "models/props_structures/radiant_ancient001.vmdl"
local visuals = require("config/generated/building_visual_levels")
local buildings = require("config/buildings_config")

local visual = assert((visuals.by_id or {}).hero_altar_visual_lv01,
    "hero altar level-one visual is missing")
assert(visual.building_id == "building_hero_altar" and visual.level == 1,
    "hero altar visual is mapped to the wrong building level")
assert(visual.model_name == expected_model,
    "hero altar completion visual must preserve the selectable Ancient model")

local altar = assert(buildings.hero_altar, "hero altar runtime config is missing")
assert(altar.selectable == true, "hero altar must remain selectable")
assert(altar.unit_name == "building_hero_altar",
    "hero altar must use its npc_dota_creature unit")
assert(altar.levels and altar.levels[1]
        and altar.levels[1].model_name == expected_model,
    "hero altar runtime level did not merge the Ancient visual")
assert(#(altar.abilities or {}) >= 1,
    "hero altar must retain its summon abilities")

local file = assert(io.open("scripts/npc/npc_units_custom.txt", "rb"),
    "npc_units_custom.txt is missing")
local kv = file:read("*a")
file:close()
local block = assert(kv:match('"building_hero_altar"%s*(%b{})'),
    "hero altar unit KV block is missing")
assert(block:find('"BaseClass"%s+"npc_dota_creature"'),
    "hero altar must remain an interactive creature unit")
assert(block:find('"Model"%s+"' .. expected_model:gsub("%.", "%%.") .. '"'),
    "hero altar unit KV fallback model does not match the completion visual")
assert(block:find('"BoundsHullName"%s+"DOTA_HULL_SIZE_BARRACKS"'),
    "hero altar collision hull is missing")

print("HERO_ALTAR_INTERACTION_CONFIG_PASS")