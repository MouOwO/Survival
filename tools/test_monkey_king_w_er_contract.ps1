$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$csv = (Resolve-Path (Join-Path $root "data\csv\*\monkey_king_exclusive_runtime.csv")).Path
$runtime = Join-Path $root "scripts\vscripts\config\generated\monkey_king_exclusive_runtime.lua"
$skills = Join-Path $root "scripts\vscripts\config\generated\hero_skill_definitions.lua"
$skillCsv = (Resolve-Path (Join-Path $root "data\csv\*\hero_skill_definitions.csv")).Path
$abilities = Join-Path $root "scripts\npc\npc_abilities_custom.txt"
$service = Join-Path $root "scripts\vscripts\systems\monkey_king_exclusive_service.lua"
$stats = Join-Path $root "scripts\vscripts\systems\hero_combat_stat_service.lua"
$clone = Join-Path $root "scripts\vscripts\modifiers\modifier_monkey_king_clone.lua"
$fusion = Join-Path $root "scripts\vscripts\systems\tower_fusion_service.lua"
$tower = Join-Path $root "scripts\vscripts\modifiers\modifier_tower_attack_effects.lua"
$towerCritical = Join-Path $root "scripts\vscripts\systems\tower_attack_critical.lua"
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Text($path) { return [System.IO.File]::ReadAllText($path, $strictUtf8) }
function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$csvText = Text $csv
$runtimeText = Text $runtime
$skillsText = Text $skills
$abilitiesText = Text $abilities
$serviceText = Text $service
$statsText = Text $stats
$cloneText = Text $clone
$fusionText = Text $fusion
$towerText = Text $tower
$towerCriticalText = Text $towerCritical

foreach ($contract in @(
    "w_critical_damage_pct = 2000",
    "w_clone_critical_damage_bonus_pct = 1000",
    "w_clone_permanent = true",
    "e_critical_chance_pct = 20",
    "e_attack_multiplier = 3",
    "e_attribute_multiplier = 5"
)) {
    Check ($runtimeText.Contains($contract)) ("GENERATED_RUNTIME_CHANGED: " + $contract)
}
foreach ($contract in @(
    "w_critical_damage_pct",
    "w_clone_critical_damage_bonus_pct",
    "w_clone_permanent",
    "e_critical_chance_pct"
)) {
    Check ($csvText.Contains($contract)) ("CSV_SCHEMA_MISSING: " + $contract)
}
Check ($skillsText.Contains("skill_monkey_king_swiftness")) "E_SKILL_DESCRIPTION_MISSING"
Check ($skillsText.Contains("skill_monkey_king_fury")) "W_CLONE_DESCRIPTION_MISSING"
Check ($skillsText.Contains("skill_monkey_king_agility")) "R_SKILL_DESCRIPTION_MISSING"
$heroSkills = @(Import-Csv $skillCsv | Where-Object { $_.skill_id -notlike "#*" })
Check ($heroSkills.Count -gt 0) "HERO_SKILL_CSV_EMPTY"
foreach ($skill in $heroSkills) {
    $definition = [regex]::Match($skillsText,
        '\{ skill_id = "' + [regex]::Escape($skill.skill_id) + '"[^\r\n]+')
    Check ($definition.Success) ("HERO_SKILL_GENERATED_MISSING: " + $skill.skill_id)
    Check ($definition.Value.Contains('skill_type = "' + $skill.skill_type + '"')) `
        ("HERO_SKILL_TYPE_NOT_SYNCHRONIZED: " + $skill.skill_id)
    $ability = [regex]::Match($abilitiesText,
        '"' + [regex]::Escape($skill.ability_name) + '"\s*\{(?<body>[^}]+)\}')
    Check ($ability.Success) ("HERO_SKILL_KV_MISSING: " + $skill.ability_name)
    $behavior = [regex]::Match($ability.Groups["body"].Value,
        '"AbilityBehavior"\s*"(?<behavior>[^"]+)"').Groups["behavior"].Value
    if ($skill.skill_type -eq "passive") {
        Check ($behavior -eq "DOTA_ABILITY_BEHAVIOR_PASSIVE") `
            ("HERO_PASSIVE_CAST_BEHAVIOR: " + $skill.ability_name)
    }
}
$monkeyR = @($heroSkills | Where-Object { $_.skill_id -eq "skill_monkey_king_agility" })
Check ($monkeyR.Count -eq 1 -and $monkeyR[0].skill_type -eq "passive") "R_MUST_BE_PASSIVE"
foreach ($localizationPath in @(
    (Join-Path $root "panorama\localization\addon_schinese.txt"),
    (Join-Path $root "resource\addon_schinese.txt"),
    (Join-Path $root "resource\localization\addon_schinese.txt")
)) {
    $localizationText = Text $localizationPath
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_monkey_king_agility_Description")) "R_TOOLTIP_NOT_SYNCHRONIZED"
}
foreach ($localizationPath in @(
    (Join-Path $root "panorama\localization\addon_english.txt"),
    (Join-Path $root "resource\addon_english.txt"),
    (Join-Path $root "resource\localization\addon_english.txt")
)) {
    $localizationText = Text $localizationPath
    Check (-not $localizationText.Contains("Activate with no cooldown")) "R_STALE_ACTIVE_TOOLTIP_EN_REMAINS"
    Check ($localizationText.Contains("The ultimate tower inherits the hero's final attack and critical damage; the tower's own D ability can still move it.")) "R_TOOLTIP_EN_NOT_SYNCHRONIZED"
}
Check ($statsText.Contains("monkey_critical_chance_pct")) "E_CRITICAL_SNAPSHOT_MISSING"
Check ($serviceText.Contains("survival_critical_chance_pct")) "CLONE_CRITICAL_CHANCE_INHERITANCE_MISSING"
Check ($serviceText.Contains("w_clone_critical_damage_bonus_pct")) "CLONE_CRITICAL_DAMAGE_BONUS_MISSING"
Check ($serviceText.Contains("survival_permanent_summon")) "CLONE_PERMANENCE_MARK_MISSING"
Check ($serviceText.Contains("clone:SetHullRadius(0)")) "CLONE_ZERO_HULL_MISSING"
Check ($serviceText.Contains('hero_cosmetic_service.sync_appearance(current.clone, current.source_hero)')) "CLONE_NATIVE_COSMETIC_MIRROR_MISSING"
Check ($cloneText.Contains("function modifier_monkey_king_clone:CheckState()")) "CLONE_COLLISION_STATE_MISSING"
Check ($cloneText.Contains("[MODIFIER_STATE_NO_UNIT_COLLISION] = true")) "CLONE_NO_UNIT_COLLISION_MISSING"
Check ($cloneText.Contains("RollCriticalAttackRecord")) "CLONE_CRITICAL_ROLL_MISSING"
Check ($fusionText.Contains("hero_r_active")) "R_SKILL_STATE_CHECK_MISSING"
Check ($fusionText.Contains("HERO_COMBAT_STATS_CHANGED")) "R_REFRESH_SUBSCRIPTION_MISSING"
Check ($towerText.Contains('require("systems/tower_attack_critical").roll')) "R_TOWER_CRITICAL_CONSUMER_MISSING"
Check ($towerCriticalText.Contains("survival_inherited_critical_chance_pct") `
    -and $towerCriticalText.Contains("survival_inherited_critical_damage_pct") `
    -and $towerCriticalText.Contains('source = "monkey_king_r"')) "R_TOWER_CRITICAL_INHERITANCE_MISSING"
Write-Host "MONKEY_KING_W_ER_CONTRACT_PASS"
