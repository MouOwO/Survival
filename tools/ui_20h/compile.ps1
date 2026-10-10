param([switch]$RebuildAll)
$ErrorActionPreference='Stop'
$uiRepo=(Get-Location).Path
$uiEngine=[IO.Path]::GetFullPath((Join-Path $uiRepo '../../..'))
$uiContent=Join-Path $uiEngine 'content/dota_addons/Survival/panorama'
$uiOut=Join-Path $uiRepo ('output/ui_20h/compile_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $uiOut -Force|Out-Null
& node tools/ui_20h/dependencies.cjs
$uiSources=Get-Content -LiteralPath 'design_refs/ui_20h/work/dependencies.json' -Raw|ConvertFrom-Json
$uiChanged=@()
foreach($uiRel in $uiSources){
    $uiDest=Join-Path $uiContent $uiRel
    $uiSource=Join-Path $uiRepo ('panorama/src/'+$uiRel)
    $uiRuntime=Join-Path $uiRepo ('panorama/'+$uiRel.Replace('.js','.vjs_c').Replace('.css','.vcss_c').Replace('.xml','.vxml_c'))
    if(-not $RebuildAll -and (Test-Path -LiteralPath $uiDest) -and (Test-Path -LiteralPath $uiRuntime) -and (Get-FileHash -LiteralPath $uiSource).Hash -eq (Get-FileHash -LiteralPath $uiDest).Hash){continue}
    if(Test-Path -LiteralPath $uiDest){$uiSaved=Join-Path $uiOut $uiRel;New-Item -ItemType Directory -Path (Split-Path $uiSaved -Parent) -Force|Out-Null;Copy-Item -LiteralPath $uiDest -Destination $uiSaved -Force}
    New-Item -ItemType Directory -Path (Split-Path $uiDest -Parent) -Force|Out-Null
    Copy-Item -LiteralPath $uiSource -Destination $uiDest -Force
    $uiChanged+=$uiRel
}
foreach($uiRel in $uiChanged){& (Join-Path $uiEngine 'game/bin/win64/resourcecompiler.exe') -i (Join-Path $uiContent $uiRel) -fshallow -nop4 *> (Join-Path $uiOut (($uiRel -replace '/','_')+'.log'));if($LASTEXITCODE -ne 0){throw "Compile failed $uiRel"}}
@{at=(Get-Date -Format o);backup=$uiOut;files=$uiSources;compiled=$uiChanged;scope='Native compile only; visual and interaction checks separate'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $uiRepo 'design_refs/ui_20h/work/compile.json') -Encoding UTF8
Write-Output "UI20H_NATIVE_COMPILED $($uiChanged.Count) changed sources ($($uiSources.Count) in reference graph)"
