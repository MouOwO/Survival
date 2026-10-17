param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$builderRepo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$builderEngine = (Resolve-Path (Join-Path $builderRepo '../../..')).Path
$builderSource = Join-Path $builderRepo 'panorama/src'
$builderContent = Join-Path $builderEngine 'content/dota_addons/Survival/panorama'
$builderRuntime = Join-Path $builderRepo 'panorama'
$builderCompiler = Join-Path $builderEngine 'game/bin/win64/resourcecompiler.exe'
$builderScope = @('images/custom_game/portrait_builder_io/coolinterior.png','layout/custom_game/builder_portrait_assets.xml','scripts/custom_game/portrait_presentation.js','scripts/custom_game/combat_stats.js')
$builderBackup = Join-Path $builderRepo ('output/builder_scene_20261016/compile_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
function Get-BuilderHash([string]$Path) { if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }; return $null }
function Builder-Child([string]$Root,[string]$Relative) {
    $builderPath = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $builderPath.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped named root.' }
    return $builderPath
}
$builderRecords = foreach ($relative in $builderScope) {
    $artifactRelative = $relative -replace '\.js$','.vjs_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c'
    $source = Builder-Child $builderSource $relative
    $content = Builder-Child $builderContent $relative
    $artifact = Builder-Child $builderRuntime $artifactRelative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $relative" }
    [pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=(Get-BuilderHash $source);
        contentBefore=(Get-BuilderHash $content);artifactBefore=(Get-BuilderHash $artifact);
        contentBackup=(Join-Path $builderBackup ('content/'+$relative));artifactBackup=(Join-Path $builderBackup ('runtime/'+$artifactRelative));
        artifactHash=$null;bytes=0}
}
[xml]$builderAssets = Get-Content -LiteralPath (Join-Path $builderSource 'layout/custom_game/builder_portrait_assets.xml') -Raw
if ($builderAssets.SelectNodes('//include').Count -or $builderAssets.SelectNodes('//Image').Count -ne 1) { throw 'Unexpected asset preload dependencies.' }
if ($CheckOnly) { @{scope=$builderScope;records=$builderRecords} | ConvertTo-Json -Depth 4; return }
[void][IO.Directory]::CreateDirectory($builderBackup)
foreach ($record in $builderRecords) {
    foreach ($file in @($record.contentBackup,$record.artifactBackup)) {[void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))}
    if ($record.contentBefore) { Copy-Item -LiteralPath $record.content -Destination $record.contentBackup }
    if ($record.artifactBefore) { Copy-Item -LiteralPath $record.artifact -Destination $record.artifactBackup }
}
$builderStarted = [DateTime]::UtcNow
try {
    foreach ($record in $builderRecords) {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $record.content))
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
    }
    foreach ($record in @($builderRecords | Where-Object {$_.relative -notlike '*.png'})) {
        $force = if ($record.relative -like '*.xml') {'-f'} else {'-fshallow'}
        $log = @(& $builderCompiler -i $record.content -game (Join-Path $builderEngine 'game/dota') $force -nop4 2>&1)
        $builderExit = $LASTEXITCODE
        $log | Set-Content -LiteralPath (Join-Path $builderBackup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if ($builderExit -ne 0 -or -not ($log -match '\b0 failed\b')) { throw "Compile failed: $($record.relative)" }
        Write-Output ('BUILDER_PORTRAIT_UI_COMPILE_PASS '+$record.relative)
    }
    foreach ($record in $builderRecords) {
        if ((Get-BuilderHash $record.source) -ne $record.sourceHash -or (Get-BuilderHash $record.content) -ne $record.sourceHash) { throw 'Source/Content drift.' }
        $info = Get-Item -LiteralPath $record.artifact
        if ($info.Length -le 0 -or $info.LastWriteTimeUtc -lt $builderStarted) { throw 'Artifact is empty or stale.' }
        $record.artifactHash = Get-BuilderHash $record.artifact; $record.bytes=$info.Length
    }
    @{success=$true;backup=$builderBackup;records=$builderRecords;startedUtc=$builderStarted.ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $builderBackup 'result.json') -Encoding UTF8
} catch {
    foreach ($record in $builderRecords) {
        if ($record.contentBefore) {Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}
        elseif (Test-Path -LiteralPath $record.content -PathType Leaf) {Remove-Item -LiteralPath $record.content}
        if ($record.artifactBefore) {Copy-Item -LiteralPath $record.artifactBackup -Destination $record.artifact -Force}
        elseif (Test-Path -LiteralPath $record.artifact -PathType Leaf) {Remove-Item -LiteralPath $record.artifact}
    }
    throw
}
Write-Output ('BUILDER_PORTRAIT_UI_REPORT '+(Join-Path $builderBackup 'result.json'))
