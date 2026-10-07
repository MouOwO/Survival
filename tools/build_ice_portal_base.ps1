$ErrorActionPreference = 'Stop'
$portalRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$portalEngine = (Resolve-Path (Join-Path $portalRepo '../../..')).Path
& node (Join-Path $PSScriptRoot 'map_c6/build-ice-portal-base.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Ice portal source generation failed' }
$portalBackup = Join-Path $portalRepo ('output/ice_base_reference_20261006/content_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
foreach ($portalStyle in @('ice_portal', 'amber_portal')) {
$portalManifest = Get-Content (Join-Path $portalRepo ('art/effects/' + $portalStyle + '/manifest.json')) -Raw | ConvertFrom-Json
foreach ($row in $portalManifest.outputs) {
    $target = Join-Path $portalEngine ('content/dota_addons/Survival/' + $row.resource)
    if (Test-Path -LiteralPath $target) {
        $saved = Join-Path $portalBackup $row.resource
        New-Item -ItemType Directory -Force (Split-Path -Parent $saved) | Out-Null
        Copy-Item -LiteralPath $target -Destination $saved -Force
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $portalRepo ('art/effects/' + $portalStyle + '/source/' + $row.resource)) -Destination $target -Force
}
foreach ($row in $portalManifest.outputs) {
    $target = Join-Path $portalEngine ('content/dota_addons/Survival/' + $row.resource)
    $portalLog = @(& (Join-Path $portalEngine 'game/bin/win64/resourcecompiler.exe') -i $target -game (Join-Path $portalEngine 'game/dota') -fshallow -nop4 2>&1)
    $portalLog | Set-Content -LiteralPath (Join-Path $portalRepo ('output/ice_base_reference_20261006/' + $portalStyle + '_' + [IO.Path]::GetFileName($row.resource) + '.log'))
    $portalLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($portalLog -match '0 failed') -or $portalLog -match 'LoadKV3ObjectInPlace error|ERROR:') { throw "Portal compile failed: $($row.resource)" }
}
}
Write-Output 'ICE_AND_AMBER_PORTAL_COMPILE_PASS'
