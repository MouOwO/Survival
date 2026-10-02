$ErrorActionPreference = 'Stop'
$trialRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$trialEngine = (Resolve-Path (Join-Path $trialRepo '../../..')).Path
$trialManifest = Get-Content (Join-Path $trialRepo 'art/effects/tower_trial/manifest.json') -Raw | ConvertFrom-Json
foreach ($row in $trialManifest.outputs) {
    $destination = Join-Path $trialEngine ('content/dota_addons/survival/' + $row.resource)
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $trialRepo ('art/effects/tower_trial/source/' + $row.resource)) -Destination $destination -Force
}
foreach ($row in $trialManifest.outputs) {
    $destination = Join-Path $trialEngine ('content/dota_addons/survival/' + $row.resource)
    $log = @(& (Join-Path $trialEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $trialEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $trialRepo ('output/tower_trial/compile_' + [IO.Path]::GetFileName($row.resource) + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Tower trial compile failed: $($row.resource)" }
}
