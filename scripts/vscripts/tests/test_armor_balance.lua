package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

local armor_balance = require("config/armor_balance")
local waves = require("config/generated/wave_definitions")
local archetypes = require("config/generated/monster_archetypes")
local buildings = require("config/buildings_config")
local equipment = require("config/equipment_level_definitions")
local tower_skills = require("config/generated/tower_skill_definitions")
local essences = require("config/seven_sins_essences")
local technologies = require("config/generated/technology_definitions")
local event_bus = require("core/event_bus")
local events = require("core/events")
local equipment_stats = require("systems/equipment_stat_aggregation_service")
local research_effect_service = require("research/research_effect_service")

local function close(actual, expected, label)
    assert(math.abs((tonumber(actual) or 0) - expected) < 0.0001,
        string.format("%s: expected %.6f, got %s",
            label, expected, tostring(actual)))
end

for _, pair in ipairs({
    { 0, 0 },
    { -15, -5 },
}) do
    close(armor_balance.from_war3(pair[1]), pair[2],
        "War3 armor " .. tostring(pair[1]))
end

for _, war3_armor in ipairs({ 0, 17, 23, 30, 60, 90, 150, 300,
    600, 675, 750, 1439, 2800, 4990 }) do
    local runtime = armor_balance.from_war3_modern(war3_armor)
    assert(runtime < 225 or war3_armor <= 0,
        "modern positive armor must remain below the engine asymptote")
    close(armor_balance.to_war3_modern(runtime), war3_armor,
        "modern armor round trip " .. tostring(war3_armor))
end

close(armor_balance.from_war3_modern(300), 225 * 300 / 950,
    "modern 300 armor")
close(armor_balance.from_war3_modern(675), 225 * 675 / 1325,
    "modern 675 armor")
close(armor_balance.from_war3_modern(4990), 225 * 4990 / 5640,
    "modern 4990 armor")
local target_runtime_armor = armor_balance.from_war3_modern(117)
local target_multiplier = armor_balance.dota_positive_damage_multiplier(
    target_runtime_armor
)
close(target_runtime_armor, 225 * 117 / 767, "117 modern runtime armor")
close(801 * target_multiplier, 801 / (1 + 0.02 * 117),
    "801 damage against 117 War3 armor")
close(1401 * target_multiplier, 1401 / (1 + 0.02 * 117),
    "1401 damage against 117 War3 armor")
close(armor_balance.from_war3_modern(-15), -5,
    "modern negative armor keeps legacy mapping")
assert(armor_balance.to_war3_modern(225) == nil,
    "modern armor asymptote must not have a finite inverse")
close(armor_balance.modern_physical_reduction_pct(
    armor_balance.from_war3_modern(675)
), 100 * 0.02 * 675 / (1 + 0.02 * 675),
    "modern mapping preserves target physical reduction")
local burning_ignore_compensation =
    armor_balance.physical_armor_ignore_compensation(target_runtime_armor, 30, true)
close(
    target_multiplier
        * burning_ignore_compensation,
    1 / (1 + 0.02 * 117 * 0.7),
    "Burning Great Arrow ignores 30 percent of War3 armor"
)
close(armor_balance.physical_armor_ignore_compensation(39, 0, false), 1,
    "zero armor ignore preserves native physical armor")
close(armor_balance.effective_war3_armor(1000, 75), 925,
    "effective War3 armor reduction")
close(armor_balance.effective_war3_armor(1000, 1200, 100), 100,
    "effective War3 armor floor")
close(armor_balance.effective_war3_armor(1000, 1200), -200,
    "effective War3 armor can become negative")

local boss_wave = (waves.by_id or {}).n1_wave_05_5b
assert(boss_wave, "known wave boss is missing")
local boss_war3_armor = boss_wave.war3_armor or boss_wave.armor
close(boss_war3_armor, 117, "wave fixture uses current War3 armor")
close(armor_balance.from_war3_modern(boss_war3_armor),
    225 * 117 / 767,
    "wave armor converts once")
close(armor_balance.from_war3_modern(boss_war3_armor),
    225 * 117 / 767,
    "wave respawn remains idempotent from source config")

local ten_sin = (archetypes.by_id or {}).ten_sin_07
assert(ten_sin, "known ten-sins archetype is missing")
local ten_sin_war3_armor = ten_sin.war3_armor or ten_sin.armor
close(armor_balance.from_war3_modern(ten_sin_war3_armor),
    225 * ten_sin_war3_armor / (650 + ten_sin_war3_armor),
    "challenge armor")

close(buildings.wall.levels[1].armor, 10 / 3, "wall level 1 armor")
close(buildings.arrow_tower.pre_class_levels[5].armor, 3,
    "tower level armor")

local iron = (equipment.by_id or {}).equipment_iron_armor_02
local infernal = (equipment.by_id or {}).equipment_infernal_armor_01
local function effect_value(definition, effect_type)
    for _, effect in ipairs(definition and definition.effects or {}) do
        if effect.effect_type == effect_type then return effect.value end
    end
    return nil
end
close(effect_value(iron, "armor_flat"), 30,
    "iron armor keeps War3 value before engine boundary")
close(effect_value(infernal, "armor_flat"), 150,
    "infernal armor keeps War3 value before engine boundary")

event_bus.reset()
event_bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, function()
    return {
        ok = true,
        snapshot = { counts = { equipment_iron_armor_02 = 1 } },
    }
end)
equipment_stats.init()
local equipment_response = event_bus.request(
    events.EQUIPMENT_STATS_GET_REQUEST,
    { player_id = 0 }
)
close(equipment_response.snapshot.values.armor_flat, 30,
    "equipment aggregation exposes War3 armor")
close(armor_balance.from_war3(equipment_response.snapshot.values.armor_flat),
    10, "equipment armor converts exactly once at engine boundary")

local lust = (essences.by_content_id or {}).item_seven_sins_lust_essence
close(lust.effect_value, 1, "fixed armor reduction")

local wall_armor = (technologies.by_id or {}).researcher_super_wall_armor_10
local hero_shred = (technologies.by_id or {}).researcher_hero_armor_reduction_06
assert(wall_armor and hero_shred, "fixed armor technology fixtures are missing")
close(wall_armor.war3_effect_value, 30, "wall technology War3 audit value")
close(wall_armor.effect_value, 10, "wall technology runtime value")
close(hero_shred.war3_effect_value, 3, "hero shred War3 audit value")
close(hero_shred.effect_value, 1, "hero shred runtime value")

local research_projection = research_effect_service.new({
    GetAllLevels = function()
        return { ["ARS-02"] = 30, ["ARS-04"] = 3, ["ARS-09"] = 6 }
    end,
    GetTeam = function() return 2 end,
}):Recalculate(0)
close(research_projection.legacy.lumberjack.armor_reduction_per_attack,
    1, "legacy lumberjack shred runtime value")
close(research_projection.legacy.wall.technology_armor_bonus,
    10, "legacy wall armor runtime value")
close(research_projection.legacy.hero.armor_reduction_per_attack,
    1, "legacy hero shred runtime value")

local found_percentage = false
for _, row in ipairs(tower_skills.rows or {}) do
    if tostring(row.skill_id or ""):find("piercing_ballista", 1, true) then
        local value = tonumber(row.attack_armor_reduction)
        if value then
            assert(value >= 15, "percentage armor reduction was scaled")
            found_percentage = true
            break
        end
    end
end
assert(found_percentage, "percentage armor reduction fixture is missing")

print("ARMOR_BALANCE_PASS")