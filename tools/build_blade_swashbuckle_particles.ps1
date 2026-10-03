$ErrorActionPreference = 'Stop'
$bladeRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bladeEngine = (Resolve-Path (Join-Path $bladeRepo '../../..')).Path
$bladeManifest = Get-Content (Join-Path $bladeRepo 'art/effects/blade_swashbuckle/manifest.json') -Raw | ConvertFrom-Json
$bladeOutput = Join-Path $bladeRepo 'output/blade_swashbuckle'
New-Item -ItemType Directory -Force -Path $bladeOutput | Out-Null
foreach ($resource in $bladeManifest.outputs) {
    if ($resource -notmatch '^particles/survival/skills/blade_swashbuckle(?:_(?:images|bumper|bumper_halo|jab_embers|light))?\.vpcf$') {
        throw "Unexpected blade Swashbuckle resource path: $resource"
    }
    $bladeDestination = Join-Path $bladeEngine ('content/dota_addons/survival/' + $resource)
    if (Test-Path -LiteralPath $bladeDestination) {
        $bladeBackup = Join-Path $bladeOutput ('content_backup/' + $resource)
        if (-not (Test-Path -LiteralPath $bladeBackup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $bladeBackup) | Out-Null
            Copy-Item -LiteralPath $bladeDestination -Destination $bladeBackup
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $bladeDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $bladeRepo ('art/effects/blade_swashbuckle/source/' + $resource)) -Destination $bladeDestination -Force
}
foreach ($resource in $bladeManifest.outputs) {
    $bladeDestination = Join-Path $bladeEngine ('content/dota_addons/survival/' + $resource)
    $bladeLog = @(& (Join-Path $bladeEngine 'game/bin/win64/resourcecompiler.exe') -i $bladeDestination -game (Join-Path $bladeEngine 'game/dota') -fshallow -nop4 2>&1)
    $bladeExitCode = $LASTEXITCODE
    $bladeLog | Set-Content (Join-Path $bladeOutput ('compile_' + [IO.Path]::GetFileName($resource) + '.log'))
    $bladeLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($bladeExitCode -ne 0 -or -not ($bladeLog -match '0 failed')) { throw "Blade Swashbuckle particle compile failed: $resource" }
    if (-not (Test-Path -LiteralPath (Join-Path $bladeRepo ($resource + '_c')))) { throw "Compiled runtime particle missing: $resource" }
}
Write-Output ('BLADE_SWASHBUCKLE_COMPILE_PASS particles=' + $bladeManifest.outputs.Count)
