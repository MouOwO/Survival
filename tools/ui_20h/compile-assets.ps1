$ErrorActionPreference='Stop'
$uiRepo=(Get-Location).Path
$uiEngine=[IO.Path]::GetFullPath((Join-Path $uiRepo '../../..'))
$uiContent=Join-Path $uiEngine 'content/dota_addons/Survival/panorama/images/custom_game/reward_art_v5'
$uiSource=Join-Path $uiRepo 'art/ui/sources/custom_game/reward_art_v5'
$uiBackup=Join-Path $uiRepo ('output/ui_20h/assets_compile_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $uiBackup -Force|Out-Null
$uiRecords=(Get-Content -LiteralPath 'design_refs/ui_20h/Delivery/recovered_sources.json' -Raw|ConvertFrom-Json).records
$uiDefinitions=@()
foreach($uiRecord in $uiRecords){
    $uiFile=Split-Path $uiRecord.source -Leaf
    $uiMaster=Join-Path $uiSource $uiFile
    $uiDest=Join-Path $uiContent $uiFile
    if((Test-Path -LiteralPath $uiDest) -and (Get-FileHash -LiteralPath $uiMaster).Hash -eq (Get-FileHash -LiteralPath $uiDest).Hash){continue}
    if(Test-Path -LiteralPath $uiDest){Copy-Item -LiteralPath $uiDest -Destination (Join-Path $uiBackup $uiFile) -Force}
    New-Item -ItemType Directory -Path $uiContent -Force|Out-Null
    Copy-Item -LiteralPath $uiMaster -Destination $uiDest -Force
    if($uiFile.EndsWith('.vtex')){$uiDefinitions+=$uiDest}
}
foreach($uiDefinition in $uiDefinitions){
    & (Join-Path $uiEngine 'game/bin/win64/resourcecompiler.exe') -i $uiDefinition -fshallow -nop4 *> (Join-Path $uiBackup ((Split-Path $uiDefinition -Leaf)+'.log'))
    if($LASTEXITCODE -ne 0){throw "Texture compile failed $uiDefinition"}
}
@{at=(Get-Date -Format o);definitions=$uiDefinitions.Count;inputs=$uiRecords.Count;backup=$uiBackup;scope='Existing PNG artwork unchanged; repository LF texture definitions synchronized'}|ConvertTo-Json|Set-Content -LiteralPath 'design_refs/ui_20h/Delivery/assets_compile.json' -Encoding UTF8
Write-Output "UI20H_TEXTURES_COMPILED $($uiDefinitions.Count) definitions"
