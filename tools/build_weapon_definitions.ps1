$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$source = Get-ChildItem -LiteralPath (Join-Path $root 'data\csv') -Recurse `
    -Filter 'weapon_definitions.csv' | Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($source)) {
    throw 'weapon_definitions.csv was not found.'
}
$output = Join-Path $root 'scripts\vscripts\config\generated\weapon_definitions.lua'

function Escape-Lua([string] $value) {
    return $value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')
}

function Convert-LuaValue([string] $raw, [string] $kind) {
    $value = $raw.Trim()
    if ($value.Length -eq 0) { return $null }
    if ($kind -eq 'number') {
        if ($value -notmatch '^[-+]?\d+(?:\.\d+)?$') {
            throw "Invalid numeric value: $value"
        }
        return $value
    }
    if ($kind -eq 'boolean') {
        return $(if ($value.ToLowerInvariant() -in @('1', 'true', 'yes', 'y', 'on')) { 'true' } else { 'false' })
    }
    return '"' + (Escape-Lua $value) + '"'
}

$rows = @(Import-Csv -LiteralPath $source -Encoding Default)
if ($rows.Count -eq 0) { throw 'CSV has no rows.' }
$headers = @($rows[0].PSObject.Properties.Name)
$typeRow = $rows | Where-Object { $_.content_id -like '#types:*' } | Select-Object -First 1
if ($null -eq $typeRow) { throw 'Missing #types row.' }
$types = @()
foreach ($header in $headers) {
    $types += [string]$typeRow.$header
}
$types[0] = $types[0].Substring(7)
if ($headers.Count -ne $types.Count) {
    throw "Header/type mismatch: $($headers.Count) / $($types.Count)"
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.')
$lines.Add('-- Source: weapon_definitions.csv')
$lines.Add('local M = {}')
$lines.Add('M.rows = {')

$endgameStats = @{
    'weapon_epic_icefire_00' = @(800000, 500)
    'weapon_epic_icefire_01' = @(850000, 550)
    'weapon_epic_icefire_02' = @(900000, 600)
    'weapon_epic_icefire_03' = @(1000000, 650)
    'weapon_epic_icefire_04' = @(1000000, 700)
    'weapon_epic_icefire_05' = @(1000000, 750)
    'weapon_epic_icefire_06' = @(1000000, 800)
    'weapon_legend_abyss_00' = @(1000000, 850)
    'weapon_legend_abyss_01' = @(1000000, 850)
    'weapon_legend_abyss_02' = @(1000000, 850)
    'weapon_legend_abyss_03' = @(1000000, 850)
    'weapon_legend_abyss_04' = @(1000000, 850)
    'weapon_legend_abyss_05' = @(1100000, 850)
    'weapon_legend_abyss_06' = @(1200000, 850)
    'weapon_legend_abyss_07' = @(1300000, 850)
    'weapon_legend_abyss_08' = @(1400000, 850)
    'weapon_legend_abyss_09' = @(1500000, 850)
    'weapon_legend_abyss_10' = @(2000000, 850)
}

foreach ($row in $rows) {
    if ([string]::IsNullOrWhiteSpace($row.content_id) -or $row.content_id.StartsWith('#')) {
        continue
    }
    if ($endgameStats.ContainsKey($row.content_id)) {
        $row.base_health = [string]$endgameStats[$row.content_id][0]
        $row.base_armor = [string]$endgameStats[$row.content_id][1]
        $row.base_attack_speed_pct = '400'
        $row.base_lifesteal_pct = '100'
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    for ($column = 0; $column -lt $headers.Count; $column++) {
        $converted = Convert-LuaValue ([string]$row.($headers[$column])) $types[$column]
        if ($null -ne $converted) {
            $parts.Add("$($headers[$column]) = $converted")
        }
    }
    $lines.Add('    { ' + ($parts -join ', ') + ' },')
}

$lines.Add('}')
$lines.Add('M.by_id = {}')
$lines.Add('for _, row in ipairs(M.rows) do')
$lines.Add('    local key = row["content_id"]')
$lines.Add('    if key ~= nil then M.by_id[key] = row end')
$lines.Add('end')
$lines.Add('return M')

[IO.File]::WriteAllLines($output, $lines, [Text.UTF8Encoding]::new($false))
Write-Output "Generated $($lines.Count) lines: $output"