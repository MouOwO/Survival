$ErrorActionPreference = 'Stop'
$earthRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$earthEngine = (Resolve-Path (Join-Path $earthRepo '../../..')).Path
$earthContent = Join-Path $earthEngine 'content/dota_addons/survival'
& node (Join-Path $PSScriptRoot 'map_c6/build-earth-phoenix-impact.cjs') --check
if ($LASTEXITCODE -ne 0) { throw 'Earth Phoenix source verification failed' }
$earthManifest = Get-Content -LiteralPath (Join-Path $earthRepo 'art/effects/earth_phoenix_impact/manifest.json') -Raw | ConvertFrom-Json
$earthSuffixes = @('', 'scorch_b', 'embers', 'glow', 'ground_flare', 'light', 'scorch', 'shockwave',
    'shockwave_dust', 'shockwave_dust_glow', 'sparks', 'sphere', 'sphere_model', 'sphere_shockwave',
    'flek', 'star_sphere', 'shake')
$earthAllowed = @(foreach ($earthRadius in @(75, 125, 300)) {
    foreach ($earthSuffix in $earthSuffixes) {
        $earthStem = 'particles/survival/skills/earth_phoenix_impact_' + $earthRadius
        if ($earthSuffix) { $earthStem += '_' + $earthSuffix }
        $earthStem + '.vpcf'
    }
})
$earthAllowed += 'particles/survival/skills/earth_phoenix_impact_core.vpcf'
$earthFiles = @($earthManifest.outputs)
if ($earthFiles.Count -ne 52 -or @($earthFiles | Select-Object -Unique).Count -ne 52 -or
    @(Compare-Object $earthAllowed $earthFiles).Count -ne 0) {
    throw 'Earth Phoenix build only accepts the exact 52 approved resource paths'
}
$earthLogs = Join-Path $earthRepo ('output/earth_phoenix_impact/compile/' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $earthLogs | Out-Null
# Install all children before compiling any parent. No other addon paths sync.
foreach ($earthRelative in $earthFiles) {
    $earthSource = Join-Path $earthRepo ('art/effects/earth_phoenix_impact/source/' + $earthRelative)
    $earthDestination = Join-Path $earthContent $earthRelative
    if (Test-Path -LiteralPath $earthDestination) {
        $earthBackup = Join-Path $earthLogs ('before/' + $earthRelative)
        New-Item -ItemType Directory -Force -Path (Split-Path $earthBackup) | Out-Null
        Copy-Item -LiteralPath $earthDestination -Destination $earthBackup
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $earthDestination) | Out-Null
    Copy-Item -LiteralPath $earthSource -Destination $earthDestination -Force
}
foreach ($earthRelative in $earthFiles) {
    $earthDestination = Join-Path $earthContent $earthRelative
    $earthName = [IO.Path]::GetFileNameWithoutExtension($earthRelative)
    $earthLog = @(& (Join-Path $earthEngine 'game/bin/win64/resourcecompiler.exe') -i $earthDestination -game (Join-Path $earthEngine 'game/dota') -fshallow -nop4 2>&1)
    $earthExit = $LASTEXITCODE
    $earthLog | Set-Content -LiteralPath (Join-Path $earthLogs ($earthName + '.log'))
    $earthLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($earthExit -ne 0 -or -not ($earthLog -match '0 failed')) { throw ('Earth Phoenix compile failed: ' + $earthName) }
    if (-not (Test-Path -LiteralPath (Join-Path $earthRepo ($earthRelative + '_c')))) {
        throw ('Compiled Earth Phoenix resource is missing: ' + $earthRelative)
    }
}
Write-Output ('EARTH_PHOENIX_IMPACT_COMPILE_PASS resources=' + $earthFiles.Count + ' logs=' + $earthLogs)
