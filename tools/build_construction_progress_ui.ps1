$ErrorActionPreference = 'Stop'
$constructionRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$constructionEngine = (Resolve-Path (Join-Path $constructionRepo '../../..')).Path
$constructionContent = Join-Path $constructionEngine 'content/dota_addons/survival/panorama'
$constructionLogs = Join-Path $constructionRepo 'output/build_astral/ui'
$constructionFiles = @('scripts/custom_game/building_construction_progress.js', 'styles/custom_game/building_construction_progress.css', 'layout/custom_game/survival_hud.xml')
New-Item -ItemType Directory -Force -Path $constructionLogs | Out-Null
foreach ($relative in $constructionFiles) {
    $destination = Join-Path $constructionContent $relative
    $backup = Join-Path $constructionLogs ('before/' + $relative)
    if ((Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $backup)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $constructionRepo ('panorama/src/' + $relative)) -Destination $destination -Force
}
foreach ($relative in $constructionFiles) {
    $destination = Join-Path $constructionContent $relative
    $log = @(& (Join-Path $constructionEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $constructionEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $constructionLogs ('compile_' + [IO.Path]::GetFileName($relative) + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Construction UI compile failed: $relative" }
}
