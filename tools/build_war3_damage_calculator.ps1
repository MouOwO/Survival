param(
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$rulesCsv = Join-Path $root 'data\csv\公共规则\war3_damage_calculator_rules.csv'
$mysteryCsv = Join-Path $root 'data\csv\公共规则\war3_damage_calculator_mystery_experiment.csv'
$htmlPath = Join-Path $PSScriptRoot 'war3_damage_calculator\index.html'
$generatedRoot = Join-Path $root 'scripts\vscripts\config\generated'
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Read-Utf8([string]$path) {
    return [IO.File]::ReadAllText($path, $utf8)
}

function Read-DataRows([string]$path) {
    $lines = (Read-Utf8 $path) -split "`r?`n"
    if ($lines.Count -lt 3 -or -not $lines[1].StartsWith('#types:')) {
        throw "CSV_SCHEMA_INVALID: $path"
    }
    $content = @($lines[0]) + @($lines[2..($lines.Count - 1)] | Where-Object {
        $_.Trim() -and -not $_.TrimStart().StartsWith('#')
    })
    return @(($content -join "`n") | ConvertFrom-Csv)
}

function Number([object]$value, [string]$field) {
    $number = 0.0
    if (-not [double]::TryParse(
        [string]$value,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )) {
        throw "CSV_NUMBER_INVALID: $field=$value"
    }
    return $number
}

function Invariant([double]$value) {
    return $value.ToString('0.################', [Globalization.CultureInfo]::InvariantCulture)
}

function Lua-String([string]$value) {
    return '"' + $value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Boolean([object]$value, [string]$field) {
    $normalized = ([string]$value).Trim().ToLowerInvariant()
    if ($normalized -in @('1', 'true', 'yes')) { return $true }
    if ($normalized -in @('0', 'false', 'no')) { return $false }
    throw "CSV_BOOLEAN_INVALID: $field=$value"
}

function Write-Or-Check([string]$path, [string]$content) {
    $normalized = $content.Replace("`r`n", "`n").TrimEnd("`r", "`n") + "`n"
    if ($CheckOnly) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "GENERATED_FILE_MISSING: $path"
        }
        if ((Read-Utf8 $path).Replace("`r`n", "`n") -ne $normalized) {
            throw "GENERATED_FILE_STALE: $path"
        }
        return
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, $normalized, $utf8)
}

$rows = Read-DataRows $rulesCsv
$byId = @{}
foreach ($row in $rows) {
    if ($byId.ContainsKey($row.rule_id)) { throw "CSV_DUPLICATE_RULE: $($row.rule_id)" }
    $byId[$row.rule_id] = Number $row.value $row.rule_id
}
foreach ($required in @(
    'war3_positive_armor_factor',
    'war3_to_dota_ratio',
    'dota_positive_armor_numerator',
    'dota_positive_armor_base',
    'dota_positive_armor_denominator'
)) {
    if (-not $byId.ContainsKey($required)) { throw "CSV_REQUIRED_RULE_MISSING: $required" }
}
if ($rows.Count -ne 5) { throw 'CSV_RULE_SET_MUST_CONTAIN_ONLY_RUNTIME_ARMOR_CONSTANTS' }
foreach ($required in $byId.Keys) {
    if ($byId[$required] -le 0) { throw "ARMOR_RULE_INVALID: $required" }
}

$html = Read-Utf8 $htmlPath
$rulesLine = 'const RULES = Object.freeze({ war3PositiveArmorFactor: ' +
    (Invariant $byId.war3_positive_armor_factor) + ', war3ToDotaRatio: ' +
    (Invariant $byId.war3_to_dota_ratio) + ', dotaArmorNumerator: ' +
    (Invariant $byId.dota_positive_armor_numerator) + ', dotaArmorBase: ' +
    (Invariant $byId.dota_positive_armor_base) + ', dotaArmorDenominator: ' +
    (Invariant $byId.dota_positive_armor_denominator) + ' }); // CSV_RULES_END'
$pattern = 'const RULES = Object\.freeze\(\{[^\r\n]+\}\); // CSV_RULES_END'
if ([regex]::Matches($html, $pattern).Count -ne 1) { throw 'HTML_RULES_MARKER_INVALID' }
$generatedHtml = [regex]::Replace($html, $pattern, $rulesLine)

$mysteryRows = Read-DataRows $mysteryCsv
if ($mysteryRows.Count -ne 20) { throw 'MYSTERY_EXPERIMENT_PRESET_COUNT_INVALID' }
$mysteryIds = @{}
$mysteryObjects = foreach ($row in $mysteryRows) {
    if (-not $row.preset_id) { throw 'MYSTERY_EXPERIMENT_PRESET_ID_MISSING' }
    if ($mysteryIds.ContainsKey($row.preset_id)) { throw "MYSTERY_EXPERIMENT_DUPLICATE_PRESET: $($row.preset_id)" }
    $mysteryIds[$row.preset_id] = $true
    $preset = [ordered]@{
        presetId = [string]$row.preset_id
        routeId = [string]$row.route_id
        displayName = [string]$row.display_name
        level = Number $row.level "$($row.preset_id).level"
        panelAttackDamage = Number $row.panel_attack_damage "$($row.preset_id).panel_attack_damage"
        attackInterval = Number $row.attack_interval "$($row.preset_id).attack_interval"
        laserInitialDelay = Number $row.laser_initial_delay "$($row.preset_id).laser_initial_delay"
        laserInterval = Number $row.laser_interval "$($row.preset_id).laser_interval"
        laserBaseMultiplier = Number $row.laser_base_multiplier "$($row.preset_id).laser_base_multiplier"
        laserGrowthPerTick = Number $row.laser_growth_per_tick "$($row.preset_id).laser_growth_per_tick"
        laserMaxMultiplier = Number $row.laser_max_multiplier "$($row.preset_id).laser_max_multiplier"
        arcaneStackBonus = Number $row.arcane_stack_bonus "$($row.preset_id).arcane_stack_bonus"
        arcaneStackDuration = Number $row.arcane_stack_duration "$($row.preset_id).arcane_stack_duration"
        arcaneStackCap = Number $row.arcane_stack_cap "$($row.preset_id).arcane_stack_cap"
        eyeEnabled = Boolean $row.eye_enabled "$($row.preset_id).eye_enabled"
        eyeDamageMultiplier = Number $row.eye_damage_multiplier "$($row.preset_id).eye_damage_multiplier"
        eyePathHalfWidth = Number $row.eye_path_half_width "$($row.preset_id).eye_path_half_width"
        notes = [string]$row.notes
    }
    foreach ($positiveField in @(
        'panelAttackDamage', 'attackInterval', 'laserInitialDelay', 'laserInterval',
        'laserBaseMultiplier', 'laserMaxMultiplier', 'arcaneStackDuration', 'eyePathHalfWidth'
    )) {
        if ($preset[$positiveField] -le 0) { throw "MYSTERY_EXPERIMENT_VALUE_INVALID: $($row.preset_id).$positiveField" }
    }
    if ($preset.laserGrowthPerTick -lt 0 -or $preset.arcaneStackBonus -lt 0 -or
        $preset.arcaneStackCap -lt 0 -or $preset.eyeDamageMultiplier -lt 0) {
        throw "MYSTERY_EXPERIMENT_VALUE_INVALID: $($row.preset_id)"
    }
    [pscustomobject]$preset
}
foreach ($requiredId in @('mystery_lv02', 'arcane_cannon_lv05', 'arcane_eye_lv10')) {
    if (-not $mysteryIds.ContainsKey($requiredId)) { throw "MYSTERY_EXPERIMENT_REQUIRED_PRESET_MISSING: $requiredId" }
}
$mysteryJson = ConvertTo-Json @($mysteryObjects) -Compress -Depth 4
$mysteryLine = 'const MYSTERY_PRESETS = Object.freeze(' + $mysteryJson + '); // CSV_MYSTERY_PRESETS_END'
$mysteryPattern = 'const MYSTERY_PRESETS = Object\.freeze\([^\r\n]+\); // CSV_MYSTERY_PRESETS_END'
if ([regex]::Matches($generatedHtml, $mysteryPattern).Count -ne 1) { throw 'HTML_MYSTERY_PRESETS_MARKER_INVALID' }
$generatedHtml = [regex]::Replace($generatedHtml, $mysteryPattern, $mysteryLine)
Write-Or-Check $htmlPath $generatedHtml

$lua = @(
    '-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.',
    '-- Source: war3_damage_calculator_rules.csv',
    'local M = {}',
    'M.rows = {'
)
foreach ($row in $rows) {
    $lua += '    { rule_id = ' + (Lua-String $row.rule_id) +
        ', value = ' + (Invariant (Number $row.value $row.rule_id)) +
        ', display_name = ' + (Lua-String $row.display_name) +
        ', description = ' + (Lua-String $row.description) + ' },'
}
$lua += @(
    '}', 'M.by_id = {}', 'for _, row in ipairs(M.rows) do',
    '    local key = row["rule_id"]',
    '    if key ~= nil then M.by_id[key] = row end',
    'end', 'return M'
)
Write-Or-Check (Join-Path $generatedRoot 'war3_damage_calculator_rules.lua') ($lua -join "`n")

$csvRoot = Join-Path $root 'data\csv'
$csvNames = @(Get-ChildItem -LiteralPath $csvRoot -File -Recurse -Filter '*.csv' |
    Where-Object BaseName -ne 'war3_damage_calculator_mystery_experiment' |
    ForEach-Object BaseName | Sort-Object -Unique)
$index = @('-- AUTO-GENERATED CONFIG REGISTRY.', 'local M = {}', '')
foreach ($name in $csvNames) {
    $index += 'M["' + $name + '"] = require("config/generated/' + $name + '")'
}
$index += @('', 'return M')
Write-Or-Check (Join-Path $generatedRoot 'index.lua') ($index -join "`n")

Write-Output $(if ($CheckOnly) {
    'WAR3_CALCULATOR_GENERATED_CHECK_PASS'
} else {
    'WAR3_CALCULATOR_GENERATED_BUILD_PASS'
})