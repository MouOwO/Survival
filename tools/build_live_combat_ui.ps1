param([string[]]$Names = @('combat_stats', 'archive_180de7e38b_titles_compact_v6', 'topnav_remaining_5d5c1152eb'))
$ErrorActionPreference = 'Stop'
$combatRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$combatEngine = (Resolve-Path (Join-Path $combatRepo '../../..')).Path
$combatContent = Join-Path $combatEngine 'content/dota_addons/survival/panorama/scripts/custom_game'
$combatCompiler = Join-Path $combatEngine 'game/bin/win64/resourcecompiler.exe'
$combatCheckpoint = Join-Path $combatRepo ('output/live_combat_ui_build/' + (Get-Date -Format yyyyMMdd_HHmmss))
$combatNames = $Names
New-Item -ItemType Directory -Path $combatCheckpoint -Force | Out-Null
$combatRecords = @()
foreach ($combatName in $combatNames) {
    $combatSource = Join-Path $combatRepo ('panorama/src/scripts/custom_game/' + $combatName + '.js')
    $combatDestination = Join-Path $combatContent ($combatName + '.js')
    $combatArtifact = Join-Path $combatRepo ('panorama/scripts/custom_game/' + $combatName + '.vjs_c')
    & node --check $combatSource
    if ($LASTEXITCODE -ne 0) { throw "Syntax failed: $combatName" }
    $combatRelativeParent = Split-Path $combatName -Parent
    if ($combatRelativeParent) { New-Item -ItemType Directory -Path (Join-Path $combatCheckpoint $combatRelativeParent) -Force | Out-Null }
    Copy-Item -LiteralPath $combatDestination -Destination (Join-Path $combatCheckpoint ($combatName + '.content.js'))
    Copy-Item -LiteralPath $combatArtifact -Destination (Join-Path $combatCheckpoint ($combatName + '.game.vjs_c'))
    $combatRecords += [pscustomobject]@{ name = $combatName; source = $combatSource; content = $combatDestination; artifact = $combatArtifact }
}
try {
    foreach ($combatRecord in $combatRecords) {
        Copy-Item -LiteralPath $combatRecord.source -Destination $combatRecord.content -Force
        $combatLog = @(& $combatCompiler -i $combatRecord.content -game (Join-Path $combatEngine 'game/dota') -fshallow -nop4 2>&1)
        $combatResult = $LASTEXITCODE
        $combatLog | Set-Content -LiteralPath (Join-Path $combatCheckpoint ($combatRecord.name + '.compile.log'))
        if ($combatResult -ne 0 -or -not ($combatLog -match '0 failed')) { throw "Compile failed: $($combatRecord.name)" }
        if ((Get-Item -LiteralPath $combatRecord.artifact).Length -le 0) { throw "Empty artifact: $($combatRecord.name)" }
        if ((Get-FileHash -LiteralPath $combatRecord.source).Hash -ne (Get-FileHash -LiteralPath $combatRecord.content).Hash) { throw "Content mismatch: $($combatRecord.name)" }
        Write-Output ('LIVE_COMBAT_UI_COMPILE_PASS ' + $combatRecord.name)
    }
    $combatRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $combatCheckpoint 'manifest.json')
} catch {
    foreach ($combatRecord in $combatRecords) {
        Copy-Item -LiteralPath (Join-Path $combatCheckpoint ($combatRecord.name + '.content.js')) -Destination $combatRecord.content -Force
        Copy-Item -LiteralPath (Join-Path $combatCheckpoint ($combatRecord.name + '.game.vjs_c')) -Destination $combatRecord.artifact -Force
    }
    throw
}
Write-Output ('LIVE_COMBAT_UI_CHECKPOINT ' + $combatCheckpoint)
