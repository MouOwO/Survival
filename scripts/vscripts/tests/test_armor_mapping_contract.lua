local function read(path)
    local file = assert(io.open(path, "rb"), "missing file: " .. path)
    local content = file:read("*a")
    file:close()
    return content
end

local monster_boundaries = {
    "scripts/vscripts/systems/wave_system.lua",
    "scripts/vscripts/systems/challenge_session_service.lua",
    "scripts/vscripts/systems/monster_spawn_service.lua",
}

for _, path in ipairs(monster_boundaries) do
    local source = read(path)
    assert(source:find("local runtime_armor = 0", 1, true),
        "monster boundary does not zero engine armor: " .. path)
    assert(source:find("CUSTOM_WAR3_MAPPING_VERSION", 1, true),
        "monster boundary does not use custom War3 mapping identity: " .. path)
    assert(source:find("survival_armor_mapping_version", 1, true),
        "monster boundary does not store mapping version: " .. path)
    assert(source:find("survival_base_war3_armor", 1, true),
        "monster boundary does not store base War3 armor: " .. path)
    assert(source:find("survival_effective_war3_armor", 1, true),
        "monster boundary does not store effective War3 armor: " .. path)
    assert(source:find("survival_minimum_war3_armor", 1, true),
        "monster boundary does not store War3 armor floor: " .. path)
end

local hero_adapter = read(
    "scripts/vscripts/systems/hero_stat_adapter.lua"
)
assert(hero_adapter:find("armor_balance.from_war3(base_war3_armor)", 1, true),
    "hero armor boundary no longer uses the linear compatibility API")
assert(not hero_adapter:find("from_war3_modern", 1, true),
    "hero armor boundary must not use nonlinear monster mapping")

local training_room = read(
    "scripts/vscripts/systems/training_room_service.lua"
)
assert(training_room:find(
    "SetPhysicalArmorBaseValue(tonumber(action.target_armor) or 100000)",
    1,
    true
), "endless training target no longer preserves requested engine armor")

local projection = read("scripts/vscripts/ui/combat_stat_projection.lua")
assert(projection:find("to_war3_for_mapping", 1, true),
    "UI projection does not select the inverse by mapping version")
assert(projection:find("modern_physical_reduction_pct", 1, true),
    "UI projection does not use the modern reduction formula")

local reduction = read(
    "scripts/vscripts/modifiers/modifier_research_technology.lua"
)
assert(reduction:find("survival_war3_armor_reduction", 1, true),
    "fixed reduction does not maintain War3-domain state")
assert(reduction:find("CUSTOM_WAR3_MAPPING_VERSION", 1, true),
    "fixed reduction does not isolate custom War3 monsters")

local filter = read("scripts/vscripts/combat/damage_filter_service.lua")
assert(filter:find("war3_physical_damage_multiplier", 1, true),
    "damage filter does not apply the custom War3 formula")
assert(filter:find("DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR", 1, true),
    "damage filter does not bypass native physical armor")

local diagnostic = read(
    "scripts/vscripts/debug/armor_engine_diagnostic.lua"
)
for _, armor in ipairs({ "0", "25", "50", "100", "150", "200", "224", "225", "250" }) do
    assert(diagnostic:find(armor, 1, true),
        "engine diagnostic is missing armor fixture " .. armor)
end
assert(diagnostic:find("DAMAGE_TYPE_PHYSICAL", 1, true)
        and diagnostic:find("DAMAGE_TYPE_MAGICAL", 1, true)
        and diagnostic:find("DAMAGE_TYPE_PURE", 1, true),
    "engine diagnostic does not cover all three damage types")

print("ARMOR_MAPPING_CONTRACT_PASS")