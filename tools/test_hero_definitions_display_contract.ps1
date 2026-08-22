$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$csvPath = Join-Path $root 'data\csv\英雄系统\hero_definitions.csv'
$luaPath = Join-Path $root 'scripts\vscripts\config\generated\hero_definitions.lua'
$routerPath = Join-Path $root 'scripts\vscripts\ui\ui_request_router.lua'
$servicePath = Join-Path $root 'scripts\vscripts\systems\hero_combat_stat_service.lua'
$adapterPath = Join-Path $root 'scripts\vscripts\systems\hero_stat_adapter.lua'

$rows = Import-Csv -Path $csvPath | Where-Object { $_.enabled -eq '1' -or $_.enabled -eq 'true' }
if ($rows.Count -lt 1) { throw 'HERO_DEFINITIONS_EMPTY' }

$lua = Get-Content -Raw -Encoding UTF8 $luaPath
$router = Get-Content -Raw -Encoding UTF8 $routerPath
$service = Get-Content -Raw -Encoding UTF8 $servicePath
$adapter = Get-Content -Raw -Encoding UTF8 $adapterPath
foreach ($required in @(
    'health = safe_number(unit, "GetHealth", 0)',
    'max_health = safe_number(unit, "GetMaxHealth", 0)',
    'or tonumber(unit.survival_base_war3_armor)',
    'unit.survival_base_war3_armor = base_war3_armor',
    'health = current_health or safe_get(state.unit, "GetMaxHealth", 1)'
)) {
    if (($router + "`n" + $service + "`n" + $adapter) -notlike "*$required*") {
        throw "HERO_DISPLAY_SNAPSHOT_FIELD_MISSING field=$required"
    }
}
$seen = @{}
foreach ($row in $rows) {
    foreach ($field in @('hero_id', 'unit_name', 'base_health', 'base_armor')) {
        if ([string]::IsNullOrWhiteSpace([string]$row.$field)) {
            throw "HERO_DEFINITION_FIELD_MISSING hero=$($row.hero_id) field=$field"
        }
    }
    if ($seen.ContainsKey($row.hero_id)) { throw "HERO_DEFINITION_DUPLICATE hero=$($row.hero_id)" }
    $seen[$row.hero_id] = $true
    $id = [regex]::Escape($row.hero_id)
    $unit = [regex]::Escape($row.unit_name)
    $heroPrefix = 'hero_id = "' + $id + '"'
    $unitPattern = $heroPrefix + '.*unit_name = "' + $unit + '"'
    $healthPattern = $heroPrefix + '.*base_health = ' + [regex]::Escape($row.base_health)
    $armorPattern = $heroPrefix + '.*base_war3_armor = ' + [regex]::Escape($row.base_armor)
    if ($lua -notmatch $unitPattern) {
        throw "HERO_DEFINITION_GENERATED_MAPPING_MISSING hero=$($row.hero_id)"
    }
    if ($lua -notmatch $healthPattern) {
        throw "HERO_DEFINITION_GENERATED_HEALTH_MISSING hero=$($row.hero_id)"
    }
    if ($lua -notmatch $armorPattern) {
        throw "HERO_DEFINITION_GENERATED_ARMOR_MISSING hero=$($row.hero_id)"
    }
}

Write-Output "HERO_DEFINITIONS_DISPLAY_CONTRACT_PASS heroes=$($rows.Count)"