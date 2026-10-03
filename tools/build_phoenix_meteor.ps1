param([switch]$ImpactOnly)
$ErrorActionPreference = 'Stop'
$meteorRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$meteorEngine = (Resolve-Path (Join-Path $meteorRepo '../../..')).Path
$meteorContent = Join-Path $meteorEngine 'content/dota_addons/survival'
$meteorImpact = Get-Content -LiteralPath (Join-Path $meteorRepo 'art/effects/skill_visuals/manifest.json') -Raw | ConvertFrom-Json
$meteorFiles = @($meteorImpact.impact.outputs | Where-Object { $_ -ne 'particles/survival/skills/meteor_phoenix_impact.vpcf' })
$meteorFiles += 'particles/survival/skills/meteor_phoenix_impact.vpcf'
if (-not $ImpactOnly) { $meteorFiles = @('particles/survival/skills/meteor_phoenix_fall.vpcf') + $meteorFiles }
if (-not $meteorImpact.impact.outputs -or $meteorImpact.impact.outputs.Count -ne 17) {
    throw 'Missing complete 17-layer Phoenix impact manifest; run the meteor particle generator first'
}
$meteorLogs = Join-Path $meteorRepo ('output/meteor_phoenix_20261002/compile/' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $meteorLogs | Out-Null
foreach ($relative in $meteorFiles) {
    if ($relative -notmatch '^particles/survival/skills/meteor_phoenix_(impact(?:_[^.]+|/[^.]+)?|fall)\.vpcf$') {
        throw "Unexpected Phoenix resource path: $relative"
    }
    $destination = Join-Path $meteorContent $relative
    $backup = Join-Path $meteorLogs ('before/' + $relative)
    if ((Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $backup)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $meteorRepo ('art/effects/skill_visuals/source/' + $relative)) -Destination $destination -Force
}
# Install the entire graph before compiling a root that references its children.
foreach ($relative in $meteorFiles) {
    $destination = Join-Path $meteorContent $relative
    $name = [IO.Path]::GetFileNameWithoutExtension($relative)
    $log = @(& (Join-Path $meteorEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $meteorEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $meteorLogs ($name + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Phoenix meteor compile failed: $name" }
}
Write-Output ('PHOENIX_METEOR_BUILD_PASS resources=' + $meteorFiles.Count + ' logs=' + $meteorLogs)
