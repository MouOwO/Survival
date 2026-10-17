[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [string]$SourceRoot='panorama/src',
    [string]$Report='output/shop_v10_20261017/compile_live.json'
)
$ErrorActionPreference='Stop'
$shopRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$shopEngine=[IO.Path]::GetFullPath((Join-Path $shopRepo '../../..'))
$shopContent=Join-Path $shopEngine 'content/dota_addons/Survival/panorama'
$shopCompiler=Join-Path $shopEngine 'game/bin/win64/resourcecompiler.exe'
$shopSources=@('scripts/custom_game/shop_v10_assets.js','scripts/custom_game/black_lion_market.js','scripts/custom_game/commerce_remaining_5d5c1152eb.js','styles/custom_game/black_lion_market.css','layout/custom_game/survival_hud.xml')
$shopBackup=Join-Path $shopRepo ('output/shop_v10_20261017/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
if(-not(Test-Path -LiteralPath $shopCompiler -PathType Leaf)){throw 'Dota2 resource compiler is missing.'}
$shopRecords=@()
foreach($relative in $shopSources){
    $source=Join-Path $shopRepo ($SourceRoot+'/'+$relative)
    $content=Join-Path $shopContent $relative
    $runtimeRelative=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c'
    $artifact=Join-Path $shopRepo ('panorama/'+$runtimeRelative)
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing source: $relative"}
    $shopRecords+=[pscustomobject]@{relative=$relative;runtimeRelative=$runtimeRelative;source=$source;content=$content;artifact=$artifact;sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;compiledHash=$null;contentExisted=(Test-Path -LiteralPath $content -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf);sourceBackup=(Join-Path $shopBackup ('source/'+$relative));contentBackup=(Join-Path $shopBackup ('content/'+$relative));runtimeBackup=(Join-Path $shopBackup ('runtime/'+$runtimeRelative))}
}
if($CheckOnly){'SHOP_V10_PANORAMA_CHECK_PASS 5 sources';return}
foreach($record in $shopRecords){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
try {
    foreach($record in $shopRecords){
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $record.content)|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        $started=(Get-Date).ToUniversalTime()
        $log=@(& $shopCompiler -i $record.content -game (Join-Path $shopEngine 'game/dota') -fshallow -nop4 2>&1)
        $compilerExit=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $shopBackup (([IO.Path]::GetFileName($record.source))+'.log')) -Encoding utf8
        if($compilerExit -ne 0 -or -not($log -match 'OK: [1-9][0-9]* compiled, 0 failed,')){throw "Compile failed: $($record.relative); see $shopBackup"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing runtime output: $($record.runtimeRelative)"}
        if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $started){throw "Source drift or stale output: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
        Write-Output ('SHOP_V10_PANORAMA_COMPILED '+$record.relative)
    }
} catch {
    $compileFailure=$_
    foreach($record in $shopRecords){
        if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}
        elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
        if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}
        elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
    }
    throw $compileFailure
}
$reportFile=Join-Path $shopRepo $Report
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportFile)|Out-Null
@{at=(Get-Date -Format o);success=$true;backup=$shopBackup;records=$shopRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $reportFile -Encoding utf8
