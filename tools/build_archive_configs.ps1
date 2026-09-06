$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
# Reuse the CSV serializer without executing its lottery build entry point.
$builder = Get-Content (Join-Path $PSScriptRoot 'build_lottery_configs.ps1') -Raw
$start = $builder.IndexOf('function Escape-Lua')
Invoke-Expression $builder.Substring($start, $builder.LastIndexOf('Get-ChildItem $sourceRoot') - $start)
$outputRoot = Join-Path $repo 'scripts/vscripts/config/generated'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$sourceRoot = Join-Path $repo 'data/csv/存档系统'
Get-ChildItem $sourceRoot -Filter '*.csv' | ForEach-Object { Build-One $_ }
foreach ($name in @('player_gameplay_stats', 'entitlement_definitions', 'map_level_effect_rules')) {
    $file = Get-ChildItem (Join-Path $repo 'data/csv') -Recurse -Filter ($name + '.csv') | Select-Object -First 1
    Build-One $file
}
& (Join-Path $PSScriptRoot 'build_archive_challenge_assets.ps1')
Write-Host 'ARCHIVE_CONFIG_BUILD_PASS'
