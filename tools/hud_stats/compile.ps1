param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$hudStatsRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$hudStatsEngine=[IO.Path]::GetFullPath((Join-Path $hudStatsRepo '../../..'))
$hudStatsContent=Join-Path $hudStatsEngine 'content/dota_addons/Survival/panorama'
$hudStatsCompiler=Join-Path $hudStatsEngine 'game/bin/win64/resourcecompiler.exe'
$hudStatsFiles=@('scripts/custom_game/topnav_remaining_5d5c1152eb.js','scripts/custom_game/geometry_remaining_5d5c1152eb.js')
$hudStatsBackup=Join-Path $hudStatsRepo ('output/hud_stats/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$hudStatsRecords=@()
foreach($relative in $hudStatsFiles){
    $source=Join-Path $hudStatsRepo ('panorama/src/'+$relative)
    $content=Join-Path $hudStatsContent $relative
    $artifact=Join-Path $hudStatsRepo ('panorama/'+($relative -replace '\.js$','.vjs_c'))
    if(-not(Test-Path -LiteralPath $source) -or -not(Test-Path -LiteralPath $content) -or -not(Test-Path -LiteralPath $artifact)){throw "Missing HUD source/runtime: $relative"}
    $hudStatsRecords+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;compiledHash=$null;sourceBackup=(Join-Path $hudStatsBackup ('source/'+$relative));contentBackup=(Join-Path $hudStatsBackup ('content/'+$relative));runtimeBackup=(Join-Path $hudStatsBackup ('runtime/'+$relative+'.vjs_c'))}
}
if($CheckOnly){'HUD_STATS_COMPILE_CHECK_PASS 2 scripts, native icons require no replacement textures';return}
foreach($record in $hudStatsRecords){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    Copy-Item -LiteralPath $record.content -Destination $record.contentBackup
    Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup
}
try {
    foreach($record in $hudStatsRecords){
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        $start=(Get-Date).ToUniversalTime()
        $log=@(& $hudStatsCompiler -i $record.content -game (Join-Path $hudStatsEngine 'game/dota') -fshallow -nop4 2>&1)
        $log|Set-Content -LiteralPath (Join-Path $hudStatsBackup (([IO.Path]::GetFileName($record.source))+'.log')) -Encoding utf8
        if($LASTEXITCODE -ne 0 -or -not($log -match '0 failed')){throw "HUD compile failed: $($record.relative)"}
        if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $start){throw "HUD source drift or stale artifact: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
        Write-Output ('HUD_STATS_COMPILE_PASS '+$record.relative)
    }
}catch{
    foreach($record in $hudStatsRecords){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force;Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}
    throw
}
$hudStatsReport=Join-Path $hudStatsRepo 'design_refs/hud_stats_20261014/compile.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hudStatsReport)|Out-Null
@{at=(Get-Date -Format o);success=$true;backup=$hudStatsBackup;records=$hudStatsRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $hudStatsReport -Encoding utf8
