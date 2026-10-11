$ErrorActionPreference = 'Stop'
$meteorRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$meteorEngine = (Resolve-Path (Join-Path $meteorRepo '../../..')).Path
$meteorManifest = Get-Content (Join-Path $meteorRepo 'art/effects/meteor_snapfire_ground/manifest.json') -Raw | ConvertFrom-Json
$meteorOutput = Join-Path $meteorRepo 'output/meteor_snapfire_ground'
New-Item -ItemType Directory -Force -Path $meteorOutput | Out-Null
foreach ($resource in $meteorManifest.outputs) {
    if ($resource -notmatch '^particles/survival/skills/meteor_snapfire_ground(?:_[a-z_]+)?\.vpcf$') { throw "Unexpected Meteor ground resource: $resource" }
    $meteorDestination = Join-Path $meteorEngine ('content/dota_addons/survival/' + $resource)
    New-Item -ItemType Directory -Force -Path (Split-Path $meteorDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $meteorRepo ('art/effects/meteor_snapfire_ground/source/' + $resource)) -Destination $meteorDestination -Force
}
foreach ($resource in $meteorManifest.outputs) {
    $meteorDestination = Join-Path $meteorEngine ('content/dota_addons/survival/' + $resource)
    $meteorLog = @(& (Join-Path $meteorEngine 'game/bin/win64/resourcecompiler.exe') -i $meteorDestination -game (Join-Path $meteorEngine 'game/dota') -fshallow -nop4 2>&1)
    $meteorExitCode = $LASTEXITCODE
    $meteorLog | Set-Content (Join-Path $meteorOutput ('compile_' + [IO.Path]::GetFileName($resource) + '.log'))
    $meteorLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($meteorExitCode -ne 0 -or -not ($meteorLog -match '0 failed')) { throw "Meteor ground compile failed: $resource" }
    if (-not (Test-Path -LiteralPath (Join-Path $meteorRepo ($resource + '_c')))) { throw "Missing compiled Meteor ground: $resource" }
}
Write-Output ('METEOR_SNAPFIRE_GROUND_COMPILE_PASS layers=' + $meteorManifest.outputs.Count)
