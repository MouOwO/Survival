$ErrorActionPreference='Stop'
$uiRepo=(Get-Location).Path
$uiEngine=[IO.Path]::GetFullPath((Join-Path $uiRepo '../../..'))
$uiBackup=Join-Path $uiRepo 'output/ui_20h/queue_before_capture'
New-Item -ItemType Directory -Path $uiBackup -Force|Out-Null
$uiFiles=@('scripts/custom_game/production_progress.js','styles/custom_game/production_progress.css')
$uiProbe=(Get-Content output/ui_20h/native_probe/command.json -Raw|ConvertFrom-Json).command
foreach($uiRel in $uiFiles){
    $uiSrc=Join-Path $uiEngine ('content/dota_addons/Survival/panorama/'+$uiRel)
    $uiRuntime=Join-Path $uiRepo ('panorama/'+$uiRel.Replace('.js','.vjs_c').Replace('.css','.vcss_c'))
    $uiName=Split-Path $uiRel -Leaf
    Copy-Item -LiteralPath $uiSrc -Destination (Join-Path $uiBackup $uiName) -Force
    Copy-Item -LiteralPath $uiRuntime -Destination (Join-Path $uiBackup ($uiName+'.compiled')) -Force
}
try{
    foreach($uiRel in $uiFiles){
        $uiDest=Join-Path $uiEngine ('content/dota_addons/Survival/panorama/'+$uiRel)
        Copy-Item -LiteralPath (Join-Path $uiRepo ('design_refs/ui_20h/work/checkpoints/baseline/panorama/src/'+$uiRel)) -Destination $uiDest -Force
        & (Join-Path $uiEngine 'game/bin/win64/resourcecompiler.exe') -i $uiDest -fshallow -nop4 *> (Join-Path $uiBackup ((Split-Path $uiRel -Leaf)+'.log'))
        if($LASTEXITCODE -ne 0){throw 'Baseline compile failed'}
    }
    node tools/map_c6/console.cjs "$uiProbe select 621" 800 > output/ui_20h/before_select.log
    node tools/map_c6/console.cjs --file output/ui_20h/resume.json --timeout-ms 3000 > output/ui_20h/before_sync.log
    node tools/map_c6/console.cjs "$uiProbe layout A" 800 > output/ui_20h/before_inspect.log
    node tools/map_c6/console.cjs screenshot 900 | Select-String 'Screenshot written'
}finally{
    foreach($uiRel in $uiFiles){
        $uiSrc=Join-Path $uiEngine ('content/dota_addons/Survival/panorama/'+$uiRel)
        $uiRuntime=Join-Path $uiRepo ('panorama/'+$uiRel.Replace('.js','.vjs_c').Replace('.css','.vcss_c'))
        $uiName=Split-Path $uiRel -Leaf
        Copy-Item -LiteralPath (Join-Path $uiBackup $uiName) -Destination $uiSrc -Force
        Copy-Item -LiteralPath (Join-Path $uiBackup ($uiName+'.compiled')) -Destination $uiRuntime -Force
    }
}
node tools/map_c6/console.cjs "$uiProbe select 621" 800 > output/ui_20h/after_select.log
node tools/map_c6/console.cjs --file output/ui_20h/resume.json --timeout-ms 3000 > output/ui_20h/after_sync.log
node tools/map_c6/console.cjs "$uiProbe layout A" 800 > output/ui_20h/after_inspect.log
node tools/map_c6/console.cjs screenshot 900 | Select-String 'Screenshot written'
Write-Output 'UI20H_BASELINE_RESTORED'
