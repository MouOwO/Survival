$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$routePath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "tower_class_machine_gun.csv" |
    Select-Object -First 1).FullName
$skillPath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "tower_skill_definitions.csv" |
    Select-Object -First 1).FullName
$routeCsv = Import-Csv -Encoding UTF8 -LiteralPath $routePath |
    Where-Object { $_.record_id -and -not $_.record_id.StartsWith("#") }
$skillCsv = Import-Csv -Encoding UTF8 -LiteralPath $skillPath |
    Where-Object { $_.skill_id -and -not $_.skill_id.StartsWith("#") }

$expectedBonuses = @(0.4, 0.6, 0.8, 1.0, 1.0)
$expectedIntervals = @(0.178571, 0.15625, 0.138889, 0.125, 0.125)
$expectedHits = @(6, 7, 8, 8, 8)

Check ($routeCsv.Count -eq 20) "MACHINE_GUN_ROUTE_LEVEL_COUNT_INVALID"
foreach ($row in $routeCsv) {
    Check ([double]$row.base_attack_speed -eq 1) `
        "MACHINE_GUN_ROUND_RATE_INVALID_$($row.record_id)"
}

for ($level = 1; $level -le 5; $level++) {
    $suffix = "{0:D2}" -f $level
    $skill = $skillCsv | Where-Object { $_.skill_id -eq "machine_gun_lv$suffix" }
    $expectedBonus = $expectedBonuses[$level - 1]
    Check ($null -ne $skill) "MACHINE_GUN_SKILL_MISSING_LV$level"
    Check ([math]::Abs([double]$skill.damage_multiplier - $expectedBonus) -lt 0.000000001) `
        "MACHINE_GUN_ATTACK_SPEED_BONUS_INVALID_LV$level"
    Check ([math]::Abs([double]$skill.barrage_interval - $expectedIntervals[$level - 1]) -lt 0.000000001) `
        "MACHINE_GUN_HIT_INTERVAL_INVALID_LV$level"
    Check ([int]$skill.max_targets -eq $expectedHits[$level - 1]) `
        "MACHINE_GUN_HIT_COUNT_INVALID_LV$level"
}

$buildingSystem = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/building_system.lua") -Raw
$upgradeSystem = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/building_upgrade_system.lua") -Raw
$modifier = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/modifiers/modifier_tower_attack_effects.lua") -Raw

Check ($buildingSystem.Contains("unit:SetBaseAttackTime(1 / speed)")) `
    "MACHINE_GUN_BUILDING_BASE_ATTACK_TIME_PROJECTION_MISSING"
Check ($upgradeSystem.Contains(
    "unit:SetBaseAttackTime(unit.survival_research_base_attack_time)")) `
    "MACHINE_GUN_UPGRADE_BASE_ATTACK_TIME_PROJECTION_MISSING"
Check ($modifier.Contains("start_machine_gun_sequence")) `
    "MACHINE_GUN_SEQUENCE_MISSING"
Check ($modifier.Contains("roll_tower_critical(tower, target)")) `
    "MACHINE_GUN_PER_HIT_CRITICAL_MISSING"
Check ($modifier.Contains("tonumber(skill.barrage_interval)")) `
    "MACHINE_GUN_INTERVAL_NOT_CONFIG_DRIVEN"
Check ($modifier.Contains("tonumber(skill.max_targets)")) `
    "MACHINE_GUN_HIT_COUNT_NOT_CONFIG_DRIVEN"
Check ($modifier.Contains('tower:SetRangedProjectileName("")')) `
    "MACHINE_GUN_NATIVE_PROJECTILE_NOT_HIDDEN"
Check ($upgradeSystem.Contains('string.match(skill_id, "^machine_gun_")')) `
    "MACHINE_GUN_UPGRADE_PROJECTILE_CLEAR_MISSING"
Check ($modifier.Contains("stop_machine_gun_sequences(self)")) `
    "MACHINE_GUN_SEQUENCE_CLEANUP_MISSING"
Check ($modifier.Contains("machine_gun_sequence_is_current")) `
    "MACHINE_GUN_SEQUENCE_GENERATION_GUARD_MISSING"
Check ($modifier.Contains("modifier_tower_attack_effects:OnRefresh()")) `
    "MACHINE_GUN_REFRESH_CLEANUP_MISSING"
Check ($modifier.Contains('"buff_explosive_gatling_attack_speed"')) `
    "MACHINE_GUN_GATLING_INTERVAL_BUFF_MISSING"

Write-Host "MACHINE_GUN_ATTACK_INTERVAL_CONTRACT_PASS"