param(
    [string[]]$Names = @('combat_stats','ability_tooltip','hud_takeover','production_progress','lumberjack_fusion_queue','ui_bootstrap','shop_remaining_5d5c1152eb','shop_ui','shop_tooltip_remaining_5d5c1152eb'),
    [string[]]$StyleNames = @('remaining_5d5c1152eb')
)
$ErrorActionPreference = 'Stop'
$taskRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskEngine = (Resolve-Path (Join-Path $taskRepo '../../..')).Path
$taskContent = Join-Path $taskEngine 'content/dota_addons/survival/panorama/scripts/custom_game'
$taskRuntime = Join-Path $taskRepo 'panorama/scripts/custom_game'
$taskCompiler = Join-Path $taskEngine 'game/bin/win64/resourcecompiler.exe'
$taskCheckpoint = Join-Path $taskRepo ('output/prerequisite_shading_20261008/ui_build_' + (Get-Date -Format yyyyMMdd_HHmmss))
$taskRecords = @()
New-Item -ItemType Directory -Force -Path $taskCheckpoint | Out-Null
foreach ($taskName in ($Names | Select-Object -Unique)) {
    if ($taskName -notmatch '^[a-z0-9_]+$') { throw "Invalid script name: $taskName" }
    $taskSource = Join-Path $taskRepo "panorama/src/scripts/custom_game/$taskName.js"
    $taskDestination = Join-Path $taskContent "$taskName.js"
    $taskArtifact = Join-Path $taskRuntime "$taskName.vjs_c"
    & node --check $taskSource
    if ($LASTEXITCODE -ne 0) { throw "Syntax error: $taskName" }
    $taskRecord = [pscustomobject]@{
        name=$taskName; source=$taskSource; content=$taskDestination; artifact=$taskArtifact
        contentExisted=(Test-Path -LiteralPath $taskDestination)
        artifactExisted=(Test-Path -LiteralPath $taskArtifact)
        contentBackup=(Join-Path $taskCheckpoint "$taskName.content.js")
        artifactBackup=(Join-Path $taskCheckpoint "$taskName.game.vjs_c")
        sourceHash=(Get-FileHash -LiteralPath $taskSource).Hash
        compiledHash=$null
    }
    Copy-Item -LiteralPath $taskSource -Destination (Join-Path $taskCheckpoint "$taskName.source.js")
    if ($taskRecord.contentExisted) { Copy-Item -LiteralPath $taskDestination -Destination $taskRecord.contentBackup }
    if ($taskRecord.artifactExisted) { Copy-Item -LiteralPath $taskArtifact -Destination $taskRecord.artifactBackup }
    $taskRecords += $taskRecord
}
foreach ($taskName in ($StyleNames | Select-Object -Unique)) {
    if ($taskName -notmatch '^[a-z0-9_]+$') { throw "Invalid style name: $taskName" }
    $taskSource = Join-Path $taskRepo "panorama/src/styles/custom_game/$taskName.css"
    $taskDestination = Join-Path $taskEngine "content/dota_addons/survival/panorama/styles/custom_game/$taskName.css"
    $taskArtifact = Join-Path $taskRepo "panorama/styles/custom_game/$taskName.vcss_c"
    $taskRecord = [pscustomobject]@{
        name=('style_' + $taskName); source=$taskSource; content=$taskDestination; artifact=$taskArtifact
        contentExisted=(Test-Path -LiteralPath $taskDestination)
        artifactExisted=(Test-Path -LiteralPath $taskArtifact)
        contentBackup=(Join-Path $taskCheckpoint "$taskName.content.css")
        artifactBackup=(Join-Path $taskCheckpoint "$taskName.game.vcss_c")
        sourceHash=(Get-FileHash -LiteralPath $taskSource).Hash
        compiledHash=$null
    }
    Copy-Item -LiteralPath $taskSource -Destination (Join-Path $taskCheckpoint "$taskName.source.css")
    if ($taskRecord.contentExisted) { Copy-Item -LiteralPath $taskDestination -Destination $taskRecord.contentBackup }
    if ($taskRecord.artifactExisted) { Copy-Item -LiteralPath $taskArtifact -Destination $taskRecord.artifactBackup }
    $taskRecords += $taskRecord
}
try {
    foreach ($taskRecord in $taskRecords) {
        Copy-Item -LiteralPath $taskRecord.source -Destination $taskRecord.content -Force
        $taskStarted = Get-Date
        $taskLog = @(& $taskCompiler -i $taskRecord.content -game (Join-Path $taskEngine 'game/dota') -f -nop4 2>&1)
        $taskCode = $LASTEXITCODE
        $taskLog | Set-Content -LiteralPath (Join-Path $taskCheckpoint ($taskRecord.name + '.compile.log'))
        if ($taskCode -ne 0 -or -not ($taskLog -match '0 failed')) { throw "Compile failed: $($taskRecord.name)" }
        $taskResult = Get-Item -LiteralPath $taskRecord.artifact
        if ($taskResult.Length -le 0 -or $taskResult.LastWriteTime -lt $taskStarted) { throw "Stale/empty artifact: $($taskRecord.name)" }
        if ((Get-FileHash -LiteralPath $taskRecord.content).Hash -ne $taskRecord.sourceHash -or
            (Get-FileHash -LiteralPath $taskRecord.source).Hash -ne $taskRecord.sourceHash) { throw "Source changed during build: $($taskRecord.name)" }
        $taskRecord.compiledHash = (Get-FileHash -LiteralPath $taskRecord.artifact).Hash
        Write-Output ('UI_COMPILE_PASS ' + $taskRecord.name)
    }
    $taskRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskCheckpoint 'manifest.json')
    Write-Output ('UI_CHECKPOINT ' + $taskCheckpoint)
} catch {
    foreach ($taskRecord in $taskRecords) {
        if ($taskRecord.contentExisted) { Copy-Item -LiteralPath $taskRecord.contentBackup -Destination $taskRecord.content -Force }
        elseif (Test-Path -LiteralPath $taskRecord.content) { Remove-Item -LiteralPath $taskRecord.content }
        if ($taskRecord.artifactExisted) { Copy-Item -LiteralPath $taskRecord.artifactBackup -Destination $taskRecord.artifact -Force }
        elseif (Test-Path -LiteralPath $taskRecord.artifact) { Remove-Item -LiteralPath $taskRecord.artifact }
    }
    throw
}
