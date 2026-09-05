$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repo 'data\csv\抽奖系统'
$outputRoot = Join-Path $repo 'scripts\vscripts\config\generated'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Escape-Lua([string]$value) {
    $escaped = $value.Replace('\', '\\').Replace('"', '\"')
    $escaped = $escaped.Replace("`r", '\r').Replace("`n", '\n')
    return $escaped
}

function Convert-LuaValue([string]$raw, [string]$type) {
    $raw = $raw.Trim()
    if ($raw -eq '') { return $null }
    switch ($type) {
        'number' {
            $parsed = 0.0
            if (-not [double]::TryParse($raw,
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$parsed)) { throw "invalid number: $raw" }
            return $raw
        }
        'boolean' {
            return $(if ($raw.ToLowerInvariant() -in @('1','true','yes','y','on')) {
                'true'
            } else { 'false' })
        }
        'list' {
            $separator = $(if ($raw.Contains('|')) { '|' } else { ',' })
            $values = @($raw.Split($separator) | Where-Object { $_.Trim() -ne '' } |
                ForEach-Object { '"' + (Escape-Lua $_.Trim()) + '"' })
            return '{' + ($values -join ', ') + '}'
        }
        default { return '"' + (Escape-Lua $raw) + '"' }
    }
}

function Build-One([IO.FileInfo]$source) {
    $lines = [IO.File]::ReadAllLines($source.FullName)
    if ($lines.Count -lt 3) { throw "CSV too short: $($source.FullName)" }
    $headers = @($lines[0].Split(','))
    $typeLine = $lines | Where-Object { $_.StartsWith('#types:') } |
        Select-Object -First 1
    if (-not $typeLine) { throw "#types row missing: $($source.FullName)" }
    $types = @($typeLine.Substring(7).Split(',') | ForEach-Object { $_.Trim() })
    if ($headers.Count -ne $types.Count) {
        throw "header/type count mismatch: $($source.Name)"
    }
    $rows = @(Import-Csv $source.FullName | Where-Object {
        $first = [string]$_.($headers[0])
        $first -ne '' -and -not $first.StartsWith('#')
    })
    $out = [Collections.Generic.List[string]]::new()
    $out.Add('-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.')
    $out.Add("-- Source: $($source.Name)")
    $out.Add('local M = {}')
    $out.Add('M.rows = {')
    foreach ($row in $rows) {
        $parts = [Collections.Generic.List[string]]::new()
        for ($index = 0; $index -lt $headers.Count; $index++) {
            $converted = Convert-LuaValue ([string]$row.($headers[$index])) $types[$index]
            if ($null -ne $converted) {
                $parts.Add("$($headers[$index]) = $converted")
            }
        }
        $out.Add('    { ' + ($parts -join ', ') + ' },')
    }
    $out.Add('}')
    $out.Add('M.by_id = {}')
    $out.Add('for _, row in ipairs(M.rows) do')
    $out.Add('    local key = row["' + $headers[0] + '"]')
    $out.Add('    if key ~= nil then M.by_id[key] = row end')
    $out.Add('end')
    $out.Add('return M')
    $out.Add('')
    $target = Join-Path $outputRoot ($source.BaseName + '.lua')
    [IO.File]::WriteAllText($target, ($out -join "`n"), $utf8NoBom)
    Write-Host "LOTTERY_CONFIG_BUILT $($source.Name)"
}

Get-ChildItem $sourceRoot -File -Filter '*.csv' | Sort-Object Name |
    ForEach-Object { Build-One $_ }
Write-Host 'LOTTERY_CONFIG_BUILD_PASS'
