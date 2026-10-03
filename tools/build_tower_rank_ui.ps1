param([switch]$SkipManifest)
$ErrorActionPreference = 'Stop'
$rankRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rankEngine = (Resolve-Path (Join-Path $rankRepo '../../..')).Path
$rankContent = Join-Path $rankEngine 'content/dota_addons/survival/panorama'
$rankCompiler = Join-Path $rankEngine 'game/bin/win64/resourcecompiler.exe'
$rankOutput = Join-Path $rankRepo ('output/tower_rank_build/' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$rankFiles = @(
    'scripts/custom_game/world_health_bar_anchor.js',
    'scripts/custom_game/tower_rank_ui.js',
    'styles/custom_game/tower_rank_ui.css',
    'layout/custom_game/tower_rank_ui.xml'
)
if (-not $SkipManifest) { $rankFiles += 'layout/custom_game/custom_ui_manifest.xml' }
foreach ($rankRelative in $rankFiles) {
    $rankSource = Join-Path $rankRepo ('panorama/src/' + $rankRelative)
    $rankDestination = Join-Path $rankContent $rankRelative
    if (-not (Test-Path -LiteralPath $rankSource)) { throw "Missing rank UI source: $rankRelative" }
    if (Test-Path -LiteralPath $rankDestination) {
        $rankBackup = Join-Path $rankOutput ('before/' + $rankRelative)
        New-Item -ItemType Directory -Force -Path (Split-Path $rankBackup) | Out-Null
        Copy-Item -LiteralPath $rankDestination -Destination $rankBackup
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $rankDestination) | Out-Null
    Copy-Item -LiteralPath $rankSource -Destination $rankDestination -Force
}
New-Item -ItemType Directory -Force -Path $rankOutput | Out-Null
foreach ($rankRelative in $rankFiles) {
    $rankLog = @(& $rankCompiler -i (Join-Path $rankContent $rankRelative) -game (Join-Path $rankEngine 'game/dota') -f -nop4 2>&1)
    $rankLog | Set-Content (Join-Path $rankOutput ([IO.Path]::GetFileName($rankRelative) + '.log'))
    $rankLog | Where-Object { $_ -match 'RESOURCE COMPILE|OK:|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($rankLog -match '0 failed')) { throw "Rank UI compilation failed: $rankRelative" }
}
Write-Output 'TOWER_RANK_UI_BUILD_PASS'
