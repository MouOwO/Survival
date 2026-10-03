$ErrorActionPreference = 'Stop'
$growthRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$growthEngine = (Resolve-Path (Join-Path $growthRepo '../../..')).Path
$growthManifest = Get-Content (Join-Path $growthRepo 'art/effects/tinker_growth/manifest.json') -Raw | ConvertFrom-Json
foreach ($row in $growthManifest.outputs) {
    $destination = Join-Path $growthEngine ('content/dota_addons/survival/' + $row.resource)
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $growthRepo ('art/effects/tinker_growth/source/' + $row.resource)) -Destination $destination -Force
}
foreach ($row in $growthManifest.outputs) {
    if ($row.compile -eq $false) { continue }
    $destination = Join-Path $growthEngine ('content/dota_addons/survival/' + $row.resource)
    $log = @(& (Join-Path $growthEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $growthEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $growthRepo ('output/tinker_growth/compile_' + [IO.Path]::GetFileName($row.resource) + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|Unknown|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Tinker growth compile failed: $($row.resource)" }
}
