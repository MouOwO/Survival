$ErrorActionPreference = 'Stop'
$laserRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$laserEngine = (Resolve-Path (Join-Path $laserRepo '../../..')).Path
$laserContent = Join-Path $laserEngine 'content/dota_addons/survival'
$laserManifest = Get-Content (Join-Path $laserRepo 'art/effects/laser/manifest.json') -Raw | ConvertFrom-Json
$laserLogs = Join-Path $laserRepo 'output/laser_head_polish'
New-Item -ItemType Directory -Force -Path $laserLogs | Out-Null
foreach ($row in $laserManifest.outputs) {
    $source = Join-Path $laserRepo ('art/effects/laser/source/' + $row.resource)
    $destination = Join-Path $laserContent $row.resource
    if (Test-Path -LiteralPath $destination) {
        $backup = Join-Path $laserLogs ('before/' + $row.resource)
        if (-not (Test-Path -LiteralPath $backup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
            Copy-Item -LiteralPath $destination -Destination $backup
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}
foreach ($row in $laserManifest.outputs) {
    $destination = Join-Path $laserContent $row.resource
    $log = @(& (Join-Path $laserEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $laserEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $laserLogs ('compile_' + [IO.Path]::GetFileNameWithoutExtension($row.resource) + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|Unknown class|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Laser compile failed: $($row.resource)" }
}
