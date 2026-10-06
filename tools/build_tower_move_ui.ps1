$ErrorActionPreference = 'Stop'
$moveRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$moveEngine = (Resolve-Path (Join-Path $moveRepo '../../..')).Path
$moveContent = [IO.Path]::GetFullPath((Join-Path $moveEngine 'content/dota_addons/survival/panorama'))
$moveCompiler = Join-Path $moveEngine 'game/bin/win64/resourcecompiler.exe'
$moveLogs = Join-Path $moveRepo ('output/tower_move_ui/' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$moveFiles = @('scripts/custom_game/building_move.js', 'scripts/custom_game/combat_stats.js', 'scripts/custom_game/survival_grid_placement.js', 'scripts/custom_game/handoff_hud.js')
New-Item -ItemType Directory -Force -Path $moveLogs | Out-Null
foreach ($relative in $moveFiles) {
    $source = Join-Path $moveRepo ('panorama/src/' + $relative)
    $destination = [IO.Path]::GetFullPath((Join-Path $moveContent $relative))
    if (-not $destination.StartsWith($moveContent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Tower move UI target outside content: $destination"
    }
    $backup = Join-Path $moveLogs ('before/' + $relative)
    if (Test-Path -LiteralPath $destination) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $compileLog = @(& $moveCompiler -i $destination -game (Join-Path $moveEngine 'game/dota') -fshallow -nop4 2>&1)
    $compileExit = $LASTEXITCODE
    $compileLog | Set-Content (Join-Path $moveLogs ([IO.Path]::GetFileName($relative) + '.log'))
    $compileLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($compileExit -ne 0 -or -not ($compileLog -match '0 failed')) { throw "Tower move UI compile failed: $relative" }
    $compiled = Join-Path $moveRepo ('panorama/' + ($relative -replace '\.js$', '.vjs_c'))
    if (-not (Test-Path -LiteralPath $compiled)) { throw "Tower move compiled resource missing: $compiled" }
}
Write-Output 'TOWER_MOVE_UI_DEPLOY_PASS'
