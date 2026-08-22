$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$routePath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "tower_class_mystery.csv" |
    Select-Object -First 1).FullName
$skillPath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "tower_skill_definitions.csv" |
    Select-Object -First 1).FullName
$assetPath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "asset_catalog.csv" |
    Select-Object -First 1).FullName
$routeCsv = Import-Csv -Encoding UTF8 -LiteralPath $routePath |
    Where-Object { $_.record_id -and -not $_.record_id.StartsWith("#") }
$skillCsv = Import-Csv -Encoding UTF8 -LiteralPath $skillPath |
    Where-Object { $_.skill_id -and -not $_.skill_id.StartsWith("#") }
$assetCsv = Import-Csv -Encoding UTF8 -LiteralPath $assetPath |
    Where-Object { $_.asset_id -and -not $_.asset_id.StartsWith("#") }
$assetIds = @{}
foreach ($asset in $assetCsv) { $assetIds[$asset.asset_id] = $true }

Check ($routeCsv.Count -eq 20) "MYSTERY_ROUTE_LEVEL_COUNT_INVALID"
foreach ($row in $routeCsv) {
    Check ([math]::Abs([double]$row.base_attack_speed - 1) -lt 0.000000001) `
        "MYSTERY_ROUTE_ATTACK_SPEED_INVALID_$($row.record_id)"
    Check ($assetIds.ContainsKey($row.model_asset_id)) `
        "MYSTERY_ROUTE_ASSET_MISSING_$($row.record_id)_$($row.model_asset_id)"
}

$mysteryRows = @($routeCsv | Where-Object { $_.stage_id -eq "mystery_tower" })
Check ($mysteryRows.Count -eq 5) "MYSTERY_TOWER_LEVEL_COUNT_INVALID"
foreach ($row in $mysteryRows) {
    Check ($row.model_asset_id -eq "tower_keeper_of_the_light") `
        "MYSTERY_TOWER_ASSET_INVALID_$($row.record_id)"
    Check ($row.model_name -eq "models/heroes/keeper_of_the_light/keeper_of_the_light.vmdl") `
        "MYSTERY_TOWER_MODEL_INVALID_$($row.record_id)"
}

$arcaneEyeRows = @($routeCsv | Where-Object { $_.stage_id -eq "arcane_eye" })
Check ($arcaneEyeRows.Count -eq 10) "ARCANE_EYE_LEVEL_COUNT_INVALID"
foreach ($row in $arcaneEyeRows) {
    Check ($row.model_asset_id -eq "tower_laser_death_prophet_brightshroud") `
        "ARCANE_EYE_ASSET_INVALID_$($row.record_id)"
    Check ($row.model_name -eq "models/heroes/death_prophet/death_prophet.vmdl") `
        "ARCANE_EYE_MODEL_INVALID_$($row.record_id)"
}

$expectedMultipliers = @(1.2, 1.4, 1.6, 1.8, 1.8)
for ($level = 1; $level -le 5; $level++) {
    $id = "laser_lv{0:d2}" -f $level
    $laser = $skillCsv | Where-Object { $_.skill_id -eq $id }
    Check ($null -ne $laser) "LASER_SKILL_MISSING_$id"
    Check ([math]::Abs([double]$laser.damage_interval - 1) -lt 0.000000001) `
        "LASER_INTERVAL_INVALID_$id"
    Check ([math]::Abs([double]$laser.damage_multiplier - $expectedMultipliers[$level - 1]) `
        -lt 0.000000001) "LASER_MULTIPLIER_INVALID_$id"
}

$eye = $skillCsv | Where-Object { $_.skill_id -eq "arcane_eye_lv01" }
Check ($null -ne $eye) "ARCANE_EYE_SKILL_MISSING"
Check ($eye.trigger_type -eq "on_laser_hit") "ARCANE_EYE_TRIGGER_INVALID"
Check ($eye.target_scope -eq "area" -and $eye.area_shape -eq "circle") `
    "ARCANE_EYE_SCOPE_INVALID"
Check ([double]$eye.area -eq 150) "ARCANE_EYE_RADIUS_INVALID"
Check ([math]::Abs([double]$eye.damage_multiplier - 0.3) -lt 0.000000001) `
    "ARCANE_EYE_MULTIPLIER_INVALID"

Write-Host "MYSTERY_TOWER_CONTRACT_PASS"