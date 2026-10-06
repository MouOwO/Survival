$ErrorActionPreference = 'Stop'
$voidRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$voidEngine = (Resolve-Path (Join-Path $voidRepo '../../..')).Path
$voidManifest = Get-Content (Join-Path $voidRepo 'art/effects/void_world_chasm/manifest.json') -Raw | ConvertFrom-Json
$voidOutput = Join-Path $voidRepo 'output/void_world_chasm'
New-Item -ItemType Directory -Force -Path $voidOutput | Out-Null
foreach ($resource in $voidManifest.outputs) {
    if ($resource -notmatch '^particles/survival/skills/void_world_chasm(?:_[a-z_]+)?\.vpcf$') { throw "Unexpected void World Chasm path: $resource" }
    $voidDestination = Join-Path $voidEngine ('content/dota_addons/survival/' + $resource)
    if (Test-Path -LiteralPath $voidDestination) {
        $voidBackup = Join-Path $voidOutput ('content_backup/' + $resource)
        if (-not (Test-Path -LiteralPath $voidBackup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $voidBackup) | Out-Null
            Copy-Item -LiteralPath $voidDestination -Destination $voidBackup
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $voidDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $voidRepo ('art/effects/void_world_chasm/source/' + $resource)) -Destination $voidDestination -Force
}
foreach ($resource in $voidManifest.outputs) {
    $voidDestination = Join-Path $voidEngine ('content/dota_addons/survival/' + $resource)
    $voidLog = @(& (Join-Path $voidEngine 'game/bin/win64/resourcecompiler.exe') -i $voidDestination -game (Join-Path $voidEngine 'game/dota') -fshallow -nop4 2>&1)
    $voidExitCode = $LASTEXITCODE
    $voidLog | Set-Content (Join-Path $voidOutput ('compile_' + [IO.Path]::GetFileName($resource) + '.log'))
    $voidLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($voidExitCode -ne 0 -or -not ($voidLog -match '0 failed')) { throw "Void World Chasm compile failed: $resource" }
    if (-not (Test-Path -LiteralPath (Join-Path $voidRepo ($resource + '_c')))) { throw "Compiled void particle missing: $resource" }
}
Write-Output ('VOID_WORLD_CHASM_COMPILE_PASS particles=' + $voidManifest.outputs.Count)
