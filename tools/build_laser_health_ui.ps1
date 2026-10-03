$ErrorActionPreference = 'Stop'
$healthRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$healthEngine = (Resolve-Path (Join-Path $healthRepo '../../..')).Path
$healthContent = Join-Path $healthEngine 'content/dota_addons/survival'
$healthLogs = Join-Path $healthRepo 'output/laser_health_ui'
$healthFiles = @('scripts/custom_game/hero_world_health_bar.js', 'styles/custom_game/hero_world_health_bar.css')
New-Item -ItemType Directory -Force -Path $healthLogs | Out-Null
foreach ($relative in $healthFiles) {
    $source = Join-Path $healthRepo ('panorama/src/' + $relative)
    $destination = Join-Path $healthContent ('panorama/' + $relative)
    if (Test-Path -LiteralPath $destination) {
        $backup = Join-Path $healthLogs ('before/' + $relative)
        if (-not (Test-Path -LiteralPath $backup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
            Copy-Item -LiteralPath $destination -Destination $backup
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $log = @(& (Join-Path $healthEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $healthEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $healthLogs ('compile_' + [IO.Path]::GetFileName($relative) + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Health UI compile failed: $relative" }
}
