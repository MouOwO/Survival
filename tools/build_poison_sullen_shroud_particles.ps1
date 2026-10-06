$ErrorActionPreference = 'Stop'
$poisonRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$poisonEngine = (Resolve-Path (Join-Path $poisonRepo '../../..')).Path
$poisonManifest = Get-Content (Join-Path $poisonRepo 'art/effects/poison_sullen_shroud/manifest.json') -Raw | ConvertFrom-Json
$poisonOutput = Join-Path $poisonRepo 'output/poison_sullen_shroud'
New-Item -ItemType Directory -Force -Path $poisonOutput | Out-Null
foreach ($resource in $poisonManifest.outputs) {
    if ($resource -notmatch '^particles/survival/skills/poison_sullen_shroud(?:_(?:projection_dark|projection|rings|rings_b|warp|burst|ray|ray_b|motes|bubbles|core|caustic|model))?\.vpcf$') {
        throw "Unexpected poison Ghost Shroud resource path: $resource"
    }
    $poisonDestination = Join-Path $poisonEngine ('content/dota_addons/survival/' + $resource)
    if (Test-Path -LiteralPath $poisonDestination) {
        $poisonBackup = Join-Path $poisonOutput ('content_backup/' + $resource)
        if (-not (Test-Path -LiteralPath $poisonBackup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $poisonBackup) | Out-Null
            Copy-Item -LiteralPath $poisonDestination -Destination $poisonBackup
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $poisonDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $poisonRepo ('art/effects/poison_sullen_shroud/source/' + $resource)) -Destination $poisonDestination -Force
}
foreach ($resource in $poisonManifest.outputs) {
    $poisonDestination = Join-Path $poisonEngine ('content/dota_addons/survival/' + $resource)
    $poisonLog = @(& (Join-Path $poisonEngine 'game/bin/win64/resourcecompiler.exe') -i $poisonDestination -game (Join-Path $poisonEngine 'game/dota') -fshallow -nop4 2>&1)
    $poisonExitCode = $LASTEXITCODE
    $poisonLog | Set-Content (Join-Path $poisonOutput ('compile_' + [IO.Path]::GetFileName($resource) + '.log'))
    $poisonLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($poisonExitCode -ne 0 -or -not ($poisonLog -match '0 failed')) { throw "Poison Ghost Shroud particle compile failed: $resource" }
    if (-not (Test-Path -LiteralPath (Join-Path $poisonRepo ($resource + '_c')))) { throw "Compiled poison particle missing: $resource" }
}
Write-Output ('POISON_SULLEN_SHROUD_COMPILE_PASS particles=' + $poisonManifest.outputs.Count)
