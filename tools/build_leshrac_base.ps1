$ErrorActionPreference = 'Stop'
$edictRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$edictEngine = (Resolve-Path (Join-Path $edictRepo '../../..')).Path
$edictManifest = Get-Content (Join-Path $edictRepo 'art/effects/leshrac_base/manifest.json') -Raw | ConvertFrom-Json
foreach ($row in $edictManifest.outputs) {
    $destination = Join-Path $edictEngine ('content/dota_addons/survival/' + $row.resource)
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $edictRepo ('art/effects/leshrac_base/source/' + $row.resource)) -Destination $destination -Force
}
foreach ($row in $edictManifest.outputs) {
    $destination = Join-Path $edictEngine ('content/dota_addons/survival/' + $row.resource)
    $log = @(& (Join-Path $edictEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $edictEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $edictRepo ('output/leshrac_base/compile_' + [IO.Path]::GetFileName($row.resource) + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Leshrac base compile failed: $($row.resource)" }
}
