$ErrorActionPreference='Stop'
$uiProbe=(Get-Content -LiteralPath 'output/ui_20h/native_probe/command.json' -Raw|ConvertFrom-Json).command
$uiRepo=(Get-Location).Path
$uiDota=[IO.Path]::GetFullPath((Join-Path $uiRepo '../../../game/dota'))
$uiOut=Join-Path $uiRepo 'design_refs/ui_20h/work/native'
New-Item -ItemType Directory -Path $uiOut -Force|Out-Null
$script:uiSerial=0;$script:uiRecords=@()
function Send-UICommand([string]$Command){
    $script:uiSerial++
    & node tools/map_c6/console.cjs $Command 900 *> (Join-Path $uiRepo ('output/ui_20h/matrix_'+$script:uiSerial+'.log'))
    if($LASTEXITCODE -ne 0){throw "Native console action failed: $Command"}
}
function Sync-UI { & node tools/map_c6/console.cjs --file output/ui_20h/resume.json --timeout-ms 3000 *> (Join-Path $uiRepo 'output/ui_20h/matrix_sync.log');if($LASTEXITCODE -ne 0){throw 'Native synchronization failed'} }
function Save-UIShot([string]$Name,[int]$Width,[int]$Height){
    $uiLines=& node tools/map_c6/console.cjs screenshot 900
    $uiMatch=[regex]::Match(($uiLines -join "`n"),'screenshots[\\/]shot_\d+\.tga')
    if(-not $uiMatch.Success){throw 'Screenshot command did not produce a file'}
    $uiSource=Join-Path $uiDota $uiMatch.Value
    $uiBytes=[IO.File]::ReadAllBytes($uiSource)
    $uiActual=@([BitConverter]::ToUInt16($uiBytes,12),[BitConverter]::ToUInt16($uiBytes,14))
    $uiFile=Join-Path $uiOut ($Name+'.png')
    & node tools/shop_ui_12h/tga.cjs $uiSource $uiFile
    if($LASTEXITCODE -ne 0){throw 'Screenshot conversion failed'}
    $script:uiRecords+=@{file=('work/native/'+$Name+'.png');requested=@($Width,$Height);actual=$uiActual;resolution_verified=($uiActual[0] -eq $Width -and $uiActual[1] -eq $Height);scope='Native running Tools game; server-backed state; no payments';at=(Get-Date -Format o)}
    $script:uiRecords|ConvertTo-Json -Depth 6 -AsArray|Set-Content -LiteralPath (Join-Path $uiOut 'captures.json') -Encoding UTF8
    if($uiActual[0] -ne $Width -or $uiActual[1] -ne $Height){throw "Requested resolution did not apply; captured $($uiActual -join 'x'). Remaining sizes require preview or a new game launch."}
}
Send-UICommand "$uiProbe archive"
try{
    foreach($uiSize in @(@(1280,720),@(1920,1080),@(2560,1440),@(2560,1080))){
        $uiWidth=$uiSize[0];$uiHeight=$uiSize[1];$uiPrefix=$uiWidth.ToString()+'x'+$uiHeight.ToString()
        Send-UICommand "mat_setvideomode $uiWidth $uiHeight 1"
        Send-UICommand "$uiProbe select 621";Sync-UI
        Send-UICommand "$uiProbe layout A"
        Save-UIShot ($uiPrefix+'_city') $uiWidth $uiHeight
        Send-UICommand "$uiProbe archive"
        Save-UIShot ($uiPrefix+'_archive') $uiWidth $uiHeight
        Send-UICommand "$uiProbe archive"
        Send-UICommand "$uiProbe select 579";Sync-UI
        Save-UIShot ($uiPrefix+'_hero') $uiWidth $uiHeight
    }
}finally{
    Send-UICommand 'mat_setvideomode 1280 720 1'
    Send-UICommand "$uiProbe select 579";Sync-UI
}
Write-Output "UI20H_NATIVE_MATRIX_CAPTURED $($script:uiRecords.Count)"
