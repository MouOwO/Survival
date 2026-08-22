$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$routeCsv = Import-Csv -Encoding UTF8 -LiteralPath (Join-Path $root `
    "data/csv/建筑与工人系统/防御塔/tower_class_anti_air.csv") |
    Where-Object { $_.record_id -and -not $_.record_id.StartsWith("#") }
$skillCsv = Import-Csv -Encoding UTF8 -LiteralPath (Join-Path $root `
    "data/csv/建筑与工人系统/防御塔/tower_skill_definitions.csv") |
    Where-Object { $_.skill_id -and -not $_.skill_id.StartsWith("#") }
$buffCsv = Import-Csv -Encoding UTF8 -LiteralPath (Join-Path $root `
    "data/csv/建筑与工人系统/防御塔/buff_definitions.csv") |
    Where-Object { $_.buff_id -and -not $_.buff_id.StartsWith("#") }

Check ($routeCsv.Count -eq 20) "ANTI_AIR_ROUTE_LEVEL_COUNT_INVALID"
Check (($routeCsv | Where-Object { $_.stage_id -eq "anti_air_tower" }).Count -eq 5) `
    "ANTI_AIR_STAGE_ONE_COUNT_INVALID"
Check (($routeCsv | Where-Object { $_.stage_id -eq "anti_air_artillery" }).Count -eq 5) `
    "ANTI_AIR_STAGE_TWO_COUNT_INVALID"
Check (($routeCsv | Where-Object { $_.stage_id -eq "airspace_overlord" }).Count -eq 10) `
    "ANTI_AIR_STAGE_THREE_COUNT_INVALID"

$expectedMissiles = @(4, 5, 6, 7, 7)
$expectedIntervals = @(0.333, 0.25, 0.2, 0.167, 0.167)
$expectedStuns = @(2, 3, 4, 5, 5)
for ($level = 1; $level -le 5; $level++) {
    $suffix = "{0:D2}" -f $level
    $missile = $skillCsv | Where-Object { $_.skill_id -eq "anti_air_missile_lv$suffix" }
    $net = $skillCsv | Where-Object { $_.skill_id -eq "drag_net_lv$suffix" }
    Check ([double]$missile.damage_multiplier -eq 1.9) `
        "ANTI_AIR_DAMAGE_MULTIPLIER_INVALID_LV$level"
    Check ([int]$missile.max_targets -eq $expectedMissiles[$level - 1]) `
        "ANTI_AIR_MISSILE_COUNT_INVALID_LV$level"
    Check ([double]$missile.barrage_interval -eq $expectedIntervals[$level - 1]) `
        "ANTI_AIR_BARRAGE_INTERVAL_INVALID_LV$level"
    $span = ([int]$missile.max_targets - 1) * [double]$missile.barrage_interval
    Check ($span -le 1.0020001) "ANTI_AIR_BARRAGE_SPAN_INVALID_LV$level"
    Check ([int]$net.trigger_chance_pct -eq $expectedStuns[$level - 1]) `
        "ANTI_AIR_STUN_CHANCE_INVALID_LV$level"
    Check ([double]$net.duration -eq 3) "ANTI_AIR_STUN_DURATION_INVALID_LV$level"
}

foreach ($row in $routeCsv) {
    Check ([double]$row.base_attack_speed -eq 1) `
        "ANTI_AIR_ROUND_RATE_INVALID_$($row.record_id)"
    Check ($row.skill_ids -match "anti_air_missile_lv0[1-5]") `
        "ANTI_AIR_MISSILE_SKILL_MISSING_$($row.record_id)"
}
foreach ($row in ($routeCsv | Where-Object { $_.stage_id -eq "anti_air_artillery" })) {
    $suffix = "{0:D2}" -f [int]$row.level
    Check ($row.skill_ids -match "drag_net_lv$suffix") `
        "ANTI_AIR_ARTILLERY_STUN_LEVEL_INVALID_$($row.record_id)"
}
foreach ($row in ($routeCsv | Where-Object { $_.stage_id -eq "airspace_overlord" })) {
    Check ($row.skill_ids -match "anti_air_missile_lv05" -and
        $row.skill_ids -match "drag_net_lv05") `
        "ANTI_AIR_FINAL_STAGE_INHERITANCE_INVALID_$($row.record_id)"
}

$damageBuff = $buffCsv | Where-Object { $_.buff_id -eq "debuff_airspace_damage_taken" }
$speedBuff = $buffCsv | Where-Object { $_.buff_id -eq "debuff_airspace_attack_slow" }
Check ($damageBuff.effect_type -eq "damage_taken_pct" -and
    [double]$damageBuff.default_value -eq 20) "AIRSPACE_DAMAGE_BUFF_INVALID"
Check ($speedBuff.effect_type -eq "attack_speed_pct" -and
    [double]$speedBuff.default_value -eq -20) "AIRSPACE_SPEED_BUFF_INVALID"

$challenge = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/challenge_session_service.lua") -Raw
$wave = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/wave_system.lua") -Raw
$spawn = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/monster_spawn_service.lua") -Raw
$filter = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/combat/damage_filter_service.lua") -Raw
$attackModifier = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/modifiers/modifier_tower_attack_effects.lua") -Raw

foreach ($source in @($challenge, $wave, $spawn)) {
    Check ($source.Contains("survival_movement_type")) `
        "FLYING_CSV_IDENTITY_PROJECTION_MISSING"
    Check ($source.Contains("survival_movement_type_override")) `
        "FLYING_CSV_OVERRIDE_PROJECTION_MISSING"
}
Check ($filter.Contains("multiplier = multiplier * 1.2")) `
    "AIRSPACE_FINAL_MULTIPLIER_ORDER_MISSING"
Check ($filter.IndexOf("multiplier = multiplier * 1.2") -gt
    $filter.IndexOf("* boss_multiplier")) "AIRSPACE_MULTIPLIER_BEFORE_BOSS"
Check ($attackModifier.Contains("tonumber(skill.barrage_interval)")) `
    "ANTI_AIR_BARRAGE_INTERVAL_NOT_CONFIG_DRIVEN"
Check (-not $attackModifier.Contains("ANTI_AIR_MISSILE_INTERVAL")) `
    "ANTI_AIR_LEGACY_FIXED_INTERVAL_REMAINS"
Check ($attackModifier.Contains("interval * (missile_index - 1)")) `
    "ANTI_AIR_ABSOLUTE_MISSILE_SCHEDULE_MISSING"

Write-Host "ANTI_AIR_TOWER_CONTRACT_PASS"