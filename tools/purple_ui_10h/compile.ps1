param([string]$Scope='design_refs/purple_ui_10h/work/compile_scope.json')
$ErrorActionPreference='Stop'
$uiTaskRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$uiTaskEngine=(Resolve-Path (Join-Path $uiTaskRepo '../../..')).Path
$uiTaskContent=Join-Path $uiTaskEngine 'content/dota_addons/Survival/panorama'
$uiTaskRuntime=Join-Path $uiTaskRepo 'panorama'
$uiTaskCompiler=Join-Path $uiTaskEngine 'game/bin/win64/resourcecompiler.exe'
$uiTaskBackup=Join-Path $uiTaskRepo ('output/purple_ui_10h/compile_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $uiTaskBackup -Force|Out-Null
$uiTaskFiles=Get-Content -LiteralPath (Join-Path $uiTaskRepo $Scope) -Raw|ConvertFrom-Json
$uiTaskRecords=@()
foreach($uiTaskRel in $uiTaskFiles){
    if($uiTaskRel -notmatch '^(scripts|styles|layout)/custom_game/(?:[a-z0-9_]+/)*[a-z0-9_]+\.(js|css|xml)$'){throw "Invalid scoped path: $uiTaskRel"}
    $uiTaskSource=Join-Path $uiTaskRepo ('panorama/src/'+$uiTaskRel)
    $uiTaskDest=Join-Path $uiTaskContent $uiTaskRel
    $uiTaskCompiled=Join-Path $uiTaskRuntime ($uiTaskRel -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c')
    $uiTaskRecord=[pscustomobject]@{relative=$uiTaskRel;source=$uiTaskSource;content=$uiTaskDest;artifact=$uiTaskCompiled;sourceHash=(Get-FileHash -LiteralPath $uiTaskSource).Hash;contentExisted=(Test-Path -LiteralPath $uiTaskDest);runtimeExisted=(Test-Path -LiteralPath $uiTaskCompiled);sourceBackup=(Join-Path $uiTaskBackup ('source/'+$uiTaskRel));contentBackup=(Join-Path $uiTaskBackup ('content/'+$uiTaskRel));runtimeBackup=(Join-Path $uiTaskBackup ('runtime/'+$uiTaskRel));compiledHash=$null}
    foreach($uiTaskPath in @($uiTaskRecord.sourceBackup,$uiTaskRecord.contentBackup,$uiTaskRecord.runtimeBackup)) {New-Item -ItemType Directory -Path (Split-Path -Parent $uiTaskPath) -Force|Out-Null}
    Copy-Item -LiteralPath $uiTaskSource -Destination $uiTaskRecord.sourceBackup
    if($uiTaskRecord.contentExisted){Copy-Item -LiteralPath $uiTaskDest -Destination $uiTaskRecord.contentBackup}
    if($uiTaskRecord.runtimeExisted){Copy-Item -LiteralPath $uiTaskCompiled -Destination $uiTaskRecord.runtimeBackup}
    $uiTaskRecords+=$uiTaskRecord
}
try {
    foreach($uiTaskRecord in $uiTaskRecords){
        New-Item -ItemType Directory -Path (Split-Path -Parent $uiTaskRecord.content) -Force|Out-Null
        Copy-Item -LiteralPath $uiTaskRecord.source -Destination $uiTaskRecord.content -Force
    }
    # Compile scripts and styles first, then layouts with the confirmed graph.
    foreach($uiTaskRecord in ($uiTaskRecords|Sort-Object @{Expression={if($_.relative.StartsWith('layout/')){1}else{0}}})){
        $uiTaskStart=Get-Date
        $uiTaskLog=@(& $uiTaskCompiler -i $uiTaskRecord.content -game (Join-Path $uiTaskEngine 'game/dota') -fshallow -nop4 2>&1)
        $uiTaskExit=$LASTEXITCODE
        $uiTaskLog|Set-Content -LiteralPath (Join-Path $uiTaskBackup (($uiTaskRecord.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($uiTaskExit -ne 0 -or -not ($uiTaskLog -match '0 failed')){throw "Native compile failed: $($uiTaskRecord.relative)"}
        $uiTaskArtifact=Get-Item -LiteralPath $uiTaskRecord.artifact
        if($uiTaskArtifact.Length -le 0 -or $uiTaskArtifact.LastWriteTime -lt $uiTaskStart){throw "Stale or empty artifact: $($uiTaskRecord.relative)"}
        if((Get-FileHash -LiteralPath $uiTaskRecord.source).Hash -ne $uiTaskRecord.sourceHash){throw "Source changed during compile: $($uiTaskRecord.relative)"}
        $uiTaskRecord.compiledHash=(Get-FileHash -LiteralPath $uiTaskRecord.artifact).Hash
        Write-Output ('PURPLE_COMPILE_PASS '+$uiTaskRecord.relative)
    }
    $uiTaskRecords|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $uiTaskBackup 'manifest.json') -Encoding UTF8
    @{at=(Get-Date -Format o);backup=$uiTaskBackup;records=$uiTaskRecords;scope='Only explicitly selected task files; no broad Content synchronization'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $uiTaskRepo 'design_refs/purple_ui_10h/work/compile.json') -Encoding UTF8
} catch {
    foreach($uiTaskRecord in $uiTaskRecords){
        if($uiTaskRecord.contentExisted){Copy-Item -LiteralPath $uiTaskRecord.contentBackup -Destination $uiTaskRecord.content -Force}
        elseif(Test-Path -LiteralPath $uiTaskRecord.content){Remove-Item -LiteralPath $uiTaskRecord.content}
        if($uiTaskRecord.runtimeExisted){Copy-Item -LiteralPath $uiTaskRecord.runtimeBackup -Destination $uiTaskRecord.artifact -Force}
        elseif(Test-Path -LiteralPath $uiTaskRecord.artifact){Remove-Item -LiteralPath $uiTaskRecord.artifact}
    }
    throw
}
