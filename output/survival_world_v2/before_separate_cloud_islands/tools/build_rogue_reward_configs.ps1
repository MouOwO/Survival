param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$csvRoot = Join-Path $root "data\csv\肉鸽奖励系统"
$outRoot = Join-Path $root "scripts\vscripts\config\generated"

function Escape-Lua([string]$value) {
    if ($null -eq $value) { return "" }
    return $value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')
}

function Convert-LuaValue([string]$raw, [string]$kind) {
    if ([string]::IsNullOrEmpty($raw)) { return $null }
    switch ($kind) {
        "number" {
            $number = 0.0
            if (-not [double]::TryParse($raw, [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
                throw "ROGUE_NUMBER_INVALID: $raw"
            }
            if ($number -eq [math]::Truncate($number)) { return ([int64]$number).ToString() }
            return $number.ToString("0.################", [Globalization.CultureInfo]::InvariantCulture)
        }
        "boolean" {
            if ($raw -in @("1", "true", "TRUE", "yes")) { return "true" }
            if ($raw -in @("0", "false", "FALSE", "no")) { return "false" }
            throw "ROGUE_BOOLEAN_INVALID: $raw"
        }
        default { return '"' + (Escape-Lua $raw) + '"' }
    }
}

function Read-RogueCsv([string]$name, [string]$baseRoot = $csvRoot) {
    $path = Join-Path $baseRoot $name
    if (-not (Test-Path -LiteralPath $path)) { throw "ROGUE_CSV_MISSING: $path" }
    $allLines = @(Get-Content -LiteralPath $path -Encoding UTF8)
    if ($allLines.Count -lt 4) { throw "ROGUE_CSV_EMPTY: $path" }
    $headers = $allLines[0].Split(',')
    $typeLine = @($allLines | Where-Object { $_.StartsWith('#types:') })
    if ($typeLine.Count -ne 1) { throw "ROGUE_TYPES_ROW_INVALID: $path" }
    $types = $typeLine[0].Substring(7).Split(',')
    if ($headers.Count -ne $types.Count) { throw "ROGUE_SCHEMA_MISMATCH: $path" }
    $dataLines = @($allLines | Select-Object -Skip 1 |
        Where-Object { $_ -and -not $_.StartsWith('#') })
    $rows = @($dataLines | ConvertFrom-Csv -Header $headers)
    return @{ Path = $path; Headers = $headers; Types = $types; Rows = $rows }
}

function Build-RogueLua($csv, [string]$outputName) {
    $rows = New-Object 'Collections.Generic.List[string]'
    $rows.Add('-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.')
    $rows.Add('-- Source: ' + [IO.Path]::GetFileName($csv.Path))
    $rows.Add('local M = {}')
    $rows.Add('M.rows = {')
    foreach ($row in $csv.Rows) {
        $parts = New-Object 'Collections.Generic.List[string]'
        for ($i = 0; $i -lt $csv.Headers.Count; $i++) {
            $key = $csv.Headers[$i]
            $raw = [string]$row.$key
            $value = Convert-LuaValue $raw $csv.Types[$i]
            if ($null -ne $value) { $parts.Add("$key = $value") }
        }
        $rows.Add('    { ' + ($parts -join ', ') + ' },')
    }
    $key = $csv.Headers[0]
    $rows.Add('}')
    $rows.Add('M.by_id = {}')
    $rows.Add('for _, row in ipairs(M.rows) do')
    $rows.Add(('    local key = row["{0}"]' -f $key))
    $rows.Add('    if key ~= nil then M.by_id[key] = row end')
    $rows.Add('end')
    $rows.Add('return M')
    $rows.Add('')
    $content = $rows -join "`n"
    $target = Join-Path $outRoot $outputName
    if ($CheckOnly) {
        if (-not (Test-Path -LiteralPath $target)) { throw "ROGUE_GENERATED_MISSING: $target" }
        if ([IO.File]::ReadAllText($target) -ne $content) { throw "ROGUE_GENERATED_STALE: $target" }
    } else {
        [IO.File]::WriteAllText($target, $content, [Text.UTF8Encoding]::new($false))
    }
}

$cards = Read-RogueCsv "rogue_reward_cards.csv"
$effects = Read-RogueCsv "rogue_reward_effects.csv"
$params = Read-RogueCsv "rogue_reward_effect_params.csv"
$lifecycle = Read-RogueCsv "rogue_reward_effect_lifecycle.csv"
$enums = Read-RogueCsv "enums.csv" (Join-Path $root "data\csv\公共规则")

$cardIds = @($cards.Rows | ForEach-Object { [string]$_.card_id })
$effectIds = @($effects.Rows | ForEach-Object { [string]$_.effect_id })
foreach ($row in $effects.Rows) {
    if ($cardIds -notcontains [string]$row.card_id) { throw "ROGUE_EFFECT_CARD_MISSING: $($row.effect_id)" }
}
foreach ($row in $params.Rows) {
    if ($effectIds -notcontains [string]$row.effect_id) { throw "ROGUE_PARAM_EFFECT_MISSING: $($row.param_id)" }
}
foreach ($row in $lifecycle.Rows) {
    if ($effectIds -notcontains [string]$row.effect_id) { throw "ROGUE_LIFECYCLE_EFFECT_MISSING: $($row.lifecycle_id)" }
}
$bossCount = @($cards.Rows | Where-Object { $_.type -eq 'boss' }).Count
$builderCount = @($cards.Rows | Where-Object { $_.type -eq 'builder_start' }).Count
if ($bossCount -ne 31) { throw "ROGUE_BOSS_CARD_COUNT: $bossCount" }
if ($builderCount -ne 21) { throw "ROGUE_BUILDER_CARD_COUNT: $builderCount" }
if (@($effects.Rows | Where-Object { $_.card_id -in @($cards.Rows | Where-Object type -eq 'builder_start' | ForEach-Object card_id) }).Count -ne 21) {
    throw "ROGUE_BUILDER_EFFECT_COUNT_INVALID"
}

Build-RogueLua $cards "rogue_reward_cards.lua"
Build-RogueLua $effects "rogue_reward_effects.lua"
Build-RogueLua $params "rogue_reward_effect_params.lua"
Build-RogueLua $lifecycle "rogue_reward_effect_lifecycle.lua"
Build-RogueLua $enums "enums.lua"
Write-Host ("ROGUE_REWARD_CONFIG_{0} PASS boss={1} builder={2} effects={3}" -f `
    ($(if ($CheckOnly) { "CHECK" } else { "BUILD" })), $bossCount, $builderCount, $effectIds.Count)