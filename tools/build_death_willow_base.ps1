$ErrorActionPreference = 'Stop'
$willowRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$willowEngine = (Resolve-Path (Join-Path $willowRepo '../../..')).Path
$willowManifest = Get-Content -LiteralPath (Join-Path $willowRepo 'art/effects/death_willow/manifest.json') -Raw | ConvertFrom-Json
$willowLogs = Join-Path $willowRepo 'output/death_reference_base_20261002/compile'
New-Item -ItemType Directory -Force -Path $willowLogs | Out-Null
foreach ($willowRow in $willowManifest.outputs) {
    $willowTarget = Join-Path $willowEngine ('content/dota_addons/survival/' + $willowRow.resource)
    New-Item -ItemType Directory -Force -Path (Split-Path $willowTarget) | Out-Null
    Copy-Item -LiteralPath (Join-Path $willowRepo ('art/effects/death_willow/source/' + $willowRow.resource)) -Destination $willowTarget -Force
}
foreach ($willowRow in $willowManifest.outputs) {
    $willowTarget = Join-Path $willowEngine ('content/dota_addons/survival/' + $willowRow.resource)
    $willowResult = @(& (Join-Path $willowEngine 'game/bin/win64/resourcecompiler.exe') -i $willowTarget -game (Join-Path $willowEngine 'game/dota') -fshallow -nop4 2>&1)
    $willowResult | Set-Content -LiteralPath (Join-Path $willowLogs ([IO.Path]::GetFileName($willowRow.resource) + '.log'))
    $willowResult | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($willowResult -match '0 failed')) { throw "Willow base compile failed: $($willowRow.resource)" }
}
Write-Output 'DEATH_WILLOW_COMPILE_PASS'
