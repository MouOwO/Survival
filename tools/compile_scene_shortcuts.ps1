param([switch]$StylesOnly, [switch]$AppearanceOnly)
$ErrorActionPreference='Stop'
$sceneRepo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sceneEngine=(Resolve-Path (Join-Path $sceneRepo '../../..')).Path
$sceneContent=Join-Path $sceneEngine 'content/dota_addons/Survival/panorama'
$sceneCompiler=Join-Path $sceneEngine 'game/bin/win64/resourcecompiler.exe'
$sceneBackup=Join-Path $sceneRepo ('output/scene_shortcuts_20261010/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
$sceneFiles=@('scripts/custom_game/portrait_presentation.js','scripts/custom_game/minimap_shortcuts.js','styles/custom_game/minimap_shortcuts.css','layout/custom_game/survival_hud.xml')
if($StylesOnly){$sceneFiles=@('styles/custom_game/minimap_shortcuts.css')}
elseif($AppearanceOnly){$sceneFiles=@('scripts/custom_game/portrait_presentation.js','scripts/custom_game/minimap_shortcuts.js','styles/custom_game/minimap_shortcuts.css')}
$sceneRecords=@()
foreach($sceneRelative in $sceneFiles){
    $sceneSource=Join-Path $sceneRepo ('panorama/src/'+$sceneRelative)
    $sceneDest=Join-Path $sceneContent $sceneRelative
    $sceneArtifact=Join-Path $sceneRepo ('panorama/'+($sceneRelative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c'))
    $sceneRow=[pscustomobject]@{relative=$sceneRelative;source=$sceneSource;content=$sceneDest;artifact=$sceneArtifact;sourceHash=(Get-FileHash -LiteralPath $sceneSource).Hash;contentExisted=(Test-Path -LiteralPath $sceneDest);runtimeExisted=(Test-Path -LiteralPath $sceneArtifact);compiledHash=$null}
    foreach($sceneArea in @('source','content','runtime')){New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $sceneBackup ($sceneArea+'/'+$sceneRelative)))|Out-Null}
    Copy-Item -LiteralPath $sceneSource -Destination (Join-Path $sceneBackup ('source/'+$sceneRelative))
    if($sceneRow.contentExisted){Copy-Item -LiteralPath $sceneDest -Destination (Join-Path $sceneBackup ('content/'+$sceneRelative))}
    if($sceneRow.runtimeExisted){Copy-Item -LiteralPath $sceneArtifact -Destination (Join-Path $sceneBackup ('runtime/'+$sceneRelative))}
    $sceneRecords+=$sceneRow
}
try {
    foreach($sceneRow in $sceneRecords){Copy-Item -LiteralPath $sceneRow.source -Destination $sceneRow.content -Force}
    foreach($sceneRow in $sceneRecords){
        $sceneStart=(Get-Date).ToUniversalTime()
        $sceneLog=@(& $sceneCompiler -i $sceneRow.content -game (Join-Path $sceneEngine 'game/dota') -fshallow -nop4 2>&1)
        $sceneLog|Set-Content -LiteralPath (Join-Path $sceneBackup (($sceneRow.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($LASTEXITCODE -ne 0 -or -not ($sceneLog -match '0 failed')){throw ('Scene shortcut compilation failed: '+$sceneRow.relative)}
        $sceneResult=Get-Item -LiteralPath $sceneRow.artifact
        if($sceneResult.Length -le 0 -or $sceneResult.LastWriteTimeUtc -lt $sceneStart){throw ('Stale compiled artifact: '+$sceneRow.relative)}
        if((Get-FileHash -LiteralPath $sceneRow.source).Hash -ne $sceneRow.sourceHash){throw ('Source changed during compilation: '+$sceneRow.relative)}
        $sceneRow.compiledHash=(Get-FileHash -LiteralPath $sceneRow.artifact).Hash
        Write-Output ('SCENE_SHORTCUT_COMPILE_PASS '+$sceneRow.relative)
    }
    @{at=(Get-Date -Format o);backup=$sceneBackup;success=$true;records=$sceneRecords}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $sceneRepo 'output/scene_shortcuts_20261010/compile.json') -Encoding UTF8
} catch {
    foreach($sceneRow in $sceneRecords){
        if($sceneRow.contentExisted){Copy-Item -LiteralPath (Join-Path $sceneBackup ('content/'+$sceneRow.relative)) -Destination $sceneRow.content -Force}
        if($sceneRow.runtimeExisted){Copy-Item -LiteralPath (Join-Path $sceneBackup ('runtime/'+$sceneRow.relative)) -Destination $sceneRow.artifact -Force}
    }
    throw
}
