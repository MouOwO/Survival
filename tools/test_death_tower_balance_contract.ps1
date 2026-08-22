$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$routePath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "tower_class_death.csv" |
    Select-Object -First 1).FullName
$skillPath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "tower_skill_definitions.csv" |
    Select-Object -First 1).FullName
$routeCsv = Import-Csv -Encoding UTF8 -LiteralPath $routePath |
    Where-Object { $_.record_id -and -not $_.record_id.StartsWith("#") }
$skillCsv = Import-Csv -Encoding UTF8 -LiteralPath $skillPath |
    Where-Object { $_.skill_id -and -not $_.skill_id.StartsWith("#") }

Check ($routeCsv.Count -eq 20) "DEATH_ROUTE_LEVEL_COUNT_INVALID"
foreach ($row in $routeCsv) {
    Check ([math]::Abs([double]$row.base_attack_speed - 1.25) -lt 0.000000001) `
        "DEATH_ROUTE_ATTACK_SPEED_INVALID_$($row.record_id)"
    Check ([math]::Abs((1 / [double]$row.base_attack_speed) - 0.8) -lt 0.000000001) `
        "DEATH_ROUTE_ATTACK_INTERVAL_INVALID_$($row.record_id)"
}

$boneExpectedAttackCounts = @(9, 8, 7, 6, 6)
for ($level = 1; $level -le 5; $level++) {
    $skillId = "bone_cannon_lv{0:D2}" -f $level
    $bone = $skillCsv | Where-Object { $_.skill_id -eq $skillId }
    Check ($null -ne $bone) "BONE_CANNON_SKILL_MISSING_$skillId"
    Check ([double]$bone.damage_multiplier -eq 5) `
        "BONE_CANNON_DAMAGE_MULTIPLIER_INVALID_$skillId"
    Check ([int]$bone.trigger_attack_count -eq $boneExpectedAttackCounts[$level - 1]) `
        "BONE_CANNON_ATTACK_COUNT_INVALID_$skillId"
    Check ($bone.description -match "5" -and $bone.description -notmatch "10") `
        "BONE_CANNON_DESCRIPTION_INVALID_$skillId"
}

$grenade = $skillCsv | Where-Object { $_.skill_id -eq "death_grenade_lv01" }
Check ($null -ne $grenade) "DEATH_GRENADE_SKILL_MISSING"
Check ([double]$grenade.trigger_chance_pct -eq 10) `
    "DEATH_GRENADE_CHANCE_INVALID"
Check ($grenade.trigger_type -eq "on_critical_hit") `
    "DEATH_GRENADE_TRIGGER_INVALID"
Check ($grenade.target_scope -eq "single" -and $grenade.area_shape -eq "none") `
    "DEATH_GRENADE_TARGET_SCOPE_INVALID"
Check ([string]::IsNullOrWhiteSpace($grenade.area)) `
    "DEATH_GRENADE_AREA_NOT_REMOVED"
Check ([double]$grenade.damage_multiplier -eq 1) `
    "DEATH_GRENADE_DAMAGE_MULTIPLIER_INVALID"

Write-Host "DEATH_TOWER_BALANCE_CONTRACT_PASS"