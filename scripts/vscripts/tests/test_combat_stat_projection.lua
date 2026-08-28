package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

local armor_balance = require("config/armor_balance")
local projection = require("ui/combat_stat_projection")

local function close(actual, expected, label)
    assert(math.abs((tonumber(actual) or 0) - expected) < 0.0001,
        string.format("%s: expected %.6f, got %s",
            label, expected, tostring(actual)))
end

close(armor_balance.to_war3(10 / 3), 10, "runtime armor to UI")
close(armor_balance.from_war3(10), 10 / 3, "UI armor to runtime")
local modern_runtime = armor_balance.from_war3_modern(675)
close(armor_balance.to_war3_modern(modern_runtime), 675,
    "modern runtime armor to UI")

local runtime = {
    attack_min = 1000,
    attack_max = 1000,
    attack_speed = 1,
    runtime_armor = 10 / 3,
    strength = 20,
    agility = 30,
    intellect = 40,
    model_asset_id = "hero_permanent_hero_blademaster",
    portrait_unit_name = "npc_dota_hero_juggernaut",
    portrait_item_def = "9059",
}
local projected = projection.for_ui(runtime)
close(projected.armor, 10, "projected armor")
close(projected.runtime_armor, 10 / 3, "preserved runtime armor")
close(projected.attack_min, 1000, "projected attack")
close(projected.attack_speed, 1, "projected attack speed")
assert(projected.armor_unit == "war3_display", "armor unit marker mismatch")
assert(projected.stat_units_version == 2, "stat unit version mismatch")
assert(projected.stat_tooltips.armor.unit == "war3_display",
    "armor tooltip unit mismatch")
assert(projected.model_asset_id == runtime.model_asset_id
        and projected.portrait_unit_name == runtime.portrait_unit_name
        and projected.portrait_item_def == runtime.portrait_item_def,
    "UI projection dropped portrait metadata")
close(projected.stat_tooltips.armor.display_value, 10,
    "armor tooltip display value")
close(projected.stat_tooltips.armor.runtime_value, 10 / 3,
    "armor tooltip runtime value")
close(projected.stat_tooltips.armor.physical_reduction_pct,
    armor_balance.modern_physical_reduction_pct(10 / 3),
    "armor tooltip physical reduction")
close(projected.stat_tooltips.attack.minimum, 1000,
    "attack tooltip minimum")
close(projected.stat_tooltips.attack_speed.attack_interval, 1,
    "attack tooltip interval")
close(projected.stat_tooltips.attributes.agility, 30,
    "attribute tooltip value")
assert(runtime.armor == nil and runtime.stat_units_version == nil,
    "UI projection mutated the authoritative runtime snapshot")

local repeated = projection.for_ui(projected)
close(repeated.armor, 10, "projection must be idempotent")
close(repeated.stat_tooltips.armor.display_value, 10,
    "tooltip projection must be idempotent")
close(projection.physical_reduction_pct(-5),
    armor_balance.modern_physical_reduction_pct(-5),
    "negative armor amplification")

local modern_projected = projection.for_ui({
    runtime_armor = modern_runtime,
    armor_mapping_version = armor_balance.MODERN_MAPPING_VERSION,
})
close(modern_projected.armor, 675, "modern projected armor")
close(modern_projected.runtime_armor, modern_runtime,
    "modern projected runtime armor")
assert(modern_projected.armor_mapping_version
    == armor_balance.MODERN_MAPPING_VERSION,
    "modern armor mapping version mismatch")
local modern_repeated = projection.for_ui(modern_projected)
close(modern_repeated.armor, 675, "modern projection must be idempotent")

print("COMBAT_STAT_PROJECTION_PASS")