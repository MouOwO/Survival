$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$csv = (Resolve-Path (Join-Path $root "data\csv\*\blademaster_exclusive_runtime.csv")).Path
$runtime = Join-Path $root "scripts\vscripts\config\generated\blademaster_exclusive_runtime.lua"
$skills = Join-Path $root "scripts\vscripts\config\generated\hero_skill_definitions.lua"
$service = Join-Path $root "scripts\vscripts\systems\blademaster_exclusive_service.lua"
$damageFilter = Join-Path $root "scripts\vscripts\combat\damage_filter_service.lua"
$stats = Join-Path $root "scripts\vscripts\systems\hero_combat_stat_service.lua"
$fusion = Join-Path $root "scripts\vscripts\systems\tower_fusion_service.lua"
$skillSystem = Join-Path $root "scripts\vscripts\systems\hero_skill_system.lua"
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Text($path) { return [System.IO.File]::ReadAllText($path, $strictUtf8) }
function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$csvText = Text $csv
$runtimeText = Text $runtime
$skillsText = Text $skills
$serviceText = Text $service
$damageFilterText = Text $damageFilter
$statsText = Text $stats
$fusionText = Text $fusion
$skillSystemText = Text $skillSystem
$gameModeText = Text (Join-Path $root "scripts\vscripts\addon_game_mode.lua")
$rewardEffectsText = Text (Join-Path $root "scripts\vscripts\config\generated\reward_effects.lua")
$localizationPaths = @(
    (Join-Path $root "panorama\localization\addon_schinese.txt"),
    (Join-Path $root "resource\addon_schinese.txt"),
    (Join-Path $root "resource\localization\addon_schinese.txt")
)

foreach ($contract in @(
    "q_critical_chance_pct = 30",
    "q_critical_damage_bonus_pct = 1500",
    "q_radius = 600",
    "w_clone_critical_damage_bonus_pct = 750",
    "w_clone_permanent = true",
    "e_duration = 3",
    "e_tick_interval = 1",
    "e_attribute_multiplier = 25",
    "e_radius = 600",
    "r_attack_interval_reduction = 0.1",
    "r_growth_interval = 150",
    "r_growth_pct = 1",
    "r_attack_multiplier = 3"
)) {
    Check ($runtimeText.Contains($contract)) ("GENERATED_RUNTIME_MISSING: " + $contract)
    Check ($csvText.Contains($contract.Split(" = ")[0])) ("CSV_SCHEMA_MISSING: " + $contract)
}
Check ($skillsText.Contains("skill_blademaster_exclusive")) "Q_DESCRIPTION_MISSING"
Check ($skillsText.Contains("skill_blademaster_agility")) "W_DESCRIPTION_MISSING"
Check ($skillsText.Contains("skill_blademaster_swiftness")) "E_DESCRIPTION_MISSING"
Check ($skillsText.Contains("skill_blademaster_mobility")) "R_DESCRIPTION_MISSING"
Check ($serviceText.Contains("HERO_FINAL_CRITICAL_ATTACK_DAMAGE, q_replicate")) "Q_FINAL_CRITICAL_EVENT_MISSING"
Check (-not $serviceText.Contains("HERO_MAIN_ATTACK_LANDED, q_replicate")) "Q_MAIN_ATTACK_EVENT_REMAINS"
Check ($serviceText.Contains("payload.critical ~= true")) "Q_CRITICAL_GATE_MISSING"
Check ($serviceText.Contains("payload.final_damage")) "Q_FINAL_DAMAGE_PAYLOAD_MISSING"
Check ($serviceText.Contains("non_recursive = true")) "SECONDARY_DAMAGE_RECURSION_GUARD_MISSING"
Check ($serviceText.Contains('local Q_VISUAL_UNIT = "npc_dota_hero_legion_commander"')) "Q_VISUAL_UNIT_MISSING"
Check ($serviceText.Contains('local Q_VISUAL_ABILITY = "legion_commander_overwhelming_odds"')) "Q_NATIVE_ABILITY_MISSING"
Check ($serviceText.Contains("create_visual_caster(Q_VISUAL_UNIT")) "Q_VISUAL_CASTER_MISSING"
Check ($serviceText.Contains("hide_unit_and_wearables(unit)")) "Q_VISUAL_HIDE_MISSING"
Check ($serviceText.Contains("DOTA_UNIT_ORDER_CAST_POSITION")) "Q_POSITION_ORDER_MISSING"
Check ($serviceText.Contains("AbilityIndex = native:entindex()")) "Q_POSITION_ABILITY_MISSING"
Check ($gameModeText.Contains('require("systems/blademaster_exclusive_service").init()')) "BLADEMASTER_SERVICE_INIT_MISSING"
Check ($serviceText.Contains("q_impact_visual(target:GetAbsOrigin(), attacker, payload.player_id)")) "Q_VISUAL_TARGET_POSITION_MISSING"
Check ($serviceText.Contains("e_tick_interval")) "E_PERIODIC_TICK_MISSING"
Check ($serviceText.Contains('local E_VISUAL_UNIT = "npc_dota_hero_juggernaut"')) "E_VISUAL_UNIT_MISSING"
Check ($serviceText.Contains('local E_VISUAL_ABILITY = "juggernaut_blade_fury"')) "E_NATIVE_ABILITY_MISSING"
Check ($serviceText.Contains("create_visual_caster(E_VISUAL_UNIT")) "E_VISUAL_CASTER_MISSING"
Check ($serviceText.Contains("CastAbilityNoTarget(native, player_id)")) "E_NATIVE_CAST_MISSING"
Check ($serviceText.Contains("survival_visual_only = true")) "VISUAL_ONLY_MARK_MISSING"
Check ($serviceText.Contains("SetHullRadius(0)")) "VISUAL_ZERO_HULL_MISSING"
Check ($serviceText.Contains("storms[id].visual_caster = create_storm_visual(") -and
    $serviceText.Contains("storms[id].position, payload.attacker")) "E_PARTICLE_TARGET_POSITION_MISSING"
Check ($serviceText.Contains("remove_visual_caster(storm.visual_caster)")) "E_VISUAL_CLEANUP_MISSING"
Check (-not $serviceText.Contains("E_OUTER_PARTICLE")) "E_OUTER_PARTICLE_REMAINS"
Check (-not $serviceText.Contains("e_visual_outer_count")) "E_OUTER_COUNT_CONFIG_REMAINS"
Check ($damageFilterText.Contains("attacker.survival_visual_only == true")) "VISUAL_DAMAGE_FILTER_MISSING"
Check ($serviceText.Contains("remove_visual_casters_for_owner(victim)")) "OWNER_DEATH_VISUAL_CLEANUP_MISSING"
Check ($serviceText.Contains("victim.survival_blademaster_visual_caster == true")) "VISUAL_SELF_DEATH_CLEANUP_MISSING"
Check ($serviceText.Contains("w_clone_critical_damage_bonus_pct")) "W_CLONE_CRITICAL_BONUS_MISSING"
Check ($serviceText.Contains("BLADEMASTER_BONUS_STATS_GET_REQUEST")) "R_GROWTH_REQUEST_MISSING"
Check ($statsText.Contains("blademaster_config.r_attack_multiplier")) "R_ATTACK_MULTIPLIER_PROJECTION_MISSING"
Check ($statsText.Contains("blademaster_config.q_critical_chance_pct")) "Q_CRITICAL_CHANCE_PROJECTION_MISSING"
Check ($fusionText.Contains("skill_blademaster_mobility")) "R_TOWER_INHERITANCE_MISSING"
Check ($skillSystemText.Contains('payload.hero_id == "hero_blademaster"')) "VIP_GATE_MISSING"
Check ($skillSystemText.Contains("state.unit:AddAbility(definition.ability_name)")) "ABILITY_REGISTRATION_MISSING"
Check ($skillSystemText.Contains("local function desired_ability_names(state)")) "ABILITY_BAR_ORDER_MISSING"
Check ($skillSystemText.Contains("local function rebuild_ability_layout(state, desired)")) "ABILITY_BAR_REBUILD_MISSING"
Check ($skillSystemText.Contains("local ability = state.unit:AddAbility(name)")) "ABILITY_ADD_ORDER_MISSING"
Check (-not $skillSystemText.Contains("SetAbilityIndex")) "UNRELIABLE_ABILITY_REINDEX_REMAINS"
foreach ($localizationPath in $localizationPaths) {
    $localizationText = Text $localizationPath
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_blademaster_exclusive")) "Q_LOCALIZATION_MISSING"
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_blademaster_agility")) "W_LOCALIZATION_MISSING"
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_blademaster_swiftness")) "E_LOCALIZATION_MISSING"
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_blademaster_mobility")) "R_LOCALIZATION_MISSING"
}
Check ($rewardEffectsText.Contains('skill_id = "skill_monkey_king_fury"')) "REWARD_SKILL_ID_MISSING"
Check ($skillSystemText.Contains("event_bus.subscribe(events.HERO_SKILL_REWARD_REQUEST, on_skill_reward)")) "REWARD_CONSUMER_MISSING"
Write-Host "BLADEMASTER_EXCLUSIVE_CONTRACT_PASS"