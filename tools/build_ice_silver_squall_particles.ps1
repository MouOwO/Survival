$ErrorActionPreference = 'Stop'
$iceRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iceEngine = (Resolve-Path (Join-Path $iceRepo '../../..')).Path
$iceManifest = Get-Content (Join-Path $iceRepo 'art/effects/ice_silver_squall/manifest.json') -Raw | ConvertFrom-Json
$iceOutput = Join-Path $iceRepo 'output/ice_silver_squall'
New-Item -ItemType Directory -Force -Path $iceOutput | Out-Null
foreach ($resource in $iceManifest.outputs) {
    if ($resource -notmatch '^particles/survival/skills/ice_cone_silver_squall_(?:fall|impact|field)(?:_[a-z_]+)?\.vpcf$') { throw "Unexpected Silver Squall resource path: $resource" }
    $iceDestination = Join-Path $iceEngine ('content/dota_addons/survival/' + $resource)
    if (Test-Path -LiteralPath $iceDestination) {
        $iceBackup = Join-Path $iceOutput ('content_backup/' + $resource)
        if (-not (Test-Path -LiteralPath $iceBackup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $iceBackup) | Out-Null
            Copy-Item -LiteralPath $iceDestination -Destination $iceBackup
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $iceDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $iceRepo ('art/effects/ice_silver_squall/source/' + $resource)) -Destination $iceDestination -Force
}
foreach ($resource in $iceManifest.outputs) {
    $iceDestination = Join-Path $iceEngine ('content/dota_addons/survival/' + $resource)
    $iceLog = @(& (Join-Path $iceEngine 'game/bin/win64/resourcecompiler.exe') -i $iceDestination -game (Join-Path $iceEngine 'game/dota') -fshallow -nop4 2>&1)
    $iceExitCode = $LASTEXITCODE
    $iceLog | Set-Content (Join-Path $iceOutput ('compile_' + [IO.Path]::GetFileName($resource) + '.log'))
    $iceLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($iceExitCode -ne 0 -or -not ($iceLog -match '0 failed')) { throw "Silver Squall particle compile failed: $resource" }
    if (-not (Test-Path -LiteralPath (Join-Path $iceRepo ($resource + '_c')))) { throw "Compiled Silver Squall particle missing: $resource" }
}
Write-Output ('ICE_SILVER_SQUALL_COMPILE_PASS particles=' + $iceManifest.outputs.Count)
