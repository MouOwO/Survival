$ErrorActionPreference = 'Stop'
$missileRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$missileEngine = (Resolve-Path (Join-Path $missileRepo '../../..')).Path
$missileManifest = Get-Content (Join-Path $missileRepo 'art/effects/techies_missiles/manifest.json') -Raw | ConvertFrom-Json
foreach ($row in $missileManifest.outputs) {
    $destination = Join-Path $missileEngine ('content/dota_addons/survival/' + $row.resource)
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $missileRepo ('art/effects/techies_missiles/source/' + $row.resource)) -Destination $destination -Force
    $log = @(& (Join-Path $missileEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $missileEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $missileRepo ('output/techies_anti_air/compile_' + [IO.Path]::GetFileName($row.resource) + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Techies missile compile failed: $($row.resource)" }
}
