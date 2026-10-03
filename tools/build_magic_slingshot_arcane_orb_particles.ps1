$ErrorActionPreference = 'Stop'
$orbRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$orbEngine = (Resolve-Path (Join-Path $orbRepo '../../..')).Path
$orbManifest = Get-Content (Join-Path $orbRepo 'art/effects/magic_slingshot_arcane_orb/manifest.json') -Raw | ConvertFrom-Json
$orbOutput = Join-Path $orbRepo 'output/magic_slingshot_arcane_orb'
New-Item -ItemType Directory -Force -Path $orbOutput | Out-Null
foreach ($resource in $orbManifest.outputs) {
    if ($resource -ne 'particles/survival/skills/magic_slingshot_arcane_orb.vpcf') { throw "Unexpected Arcane Orb path: $resource" }
    $orbDestination = Join-Path $orbEngine ('content/dota_addons/survival/' + $resource)
    if (Test-Path -LiteralPath $orbDestination) {
        $orbBackup = Join-Path $orbOutput ('content_backup/' + $resource)
        if (-not (Test-Path -LiteralPath $orbBackup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $orbBackup) | Out-Null
            Copy-Item -LiteralPath $orbDestination -Destination $orbBackup
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $orbDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $orbRepo ('art/effects/magic_slingshot_arcane_orb/source/' + $resource)) -Destination $orbDestination -Force
    $orbLog = @(& (Join-Path $orbEngine 'game/bin/win64/resourcecompiler.exe') -i $orbDestination -game (Join-Path $orbEngine 'game/dota') -fshallow -nop4 2>&1)
    $orbExitCode = $LASTEXITCODE
    $orbLog | Set-Content (Join-Path $orbOutput ('compile_' + [IO.Path]::GetFileName($resource) + '.log'))
    $orbLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($orbExitCode -ne 0 -or -not ($orbLog -match '0 failed')) { throw "Arcane Orb compile failed: $resource" }
    if (-not (Test-Path -LiteralPath (Join-Path $orbRepo ($resource + '_c')))) { throw "Compiled Arcane Orb missing: $resource" }
}
Write-Output ('MAGIC_SLINGSHOT_ARCANE_ORB_COMPILE_PASS particles=' + $orbManifest.outputs.Count)
