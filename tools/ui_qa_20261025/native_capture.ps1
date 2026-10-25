param(
 [Parameter(Mandatory=$true)][int]$GameProcessId,
 [Parameter(Mandatory=$true)][ValidateRange(1,5)][int]$Round,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9_]{1,60}$')][string]$Name,
 [int]$ClickX=-1,[int]$ClickY=-1,[int]$PointerX=-1,[int]$PointerY=-1,
 [switch]$Escape,[ValidateRange(0,5000)][int]$Delay=350
)
$ErrorActionPreference='Stop'
$nativeProcess=Get-CimInstance Win32_Process -Filter "ProcessId=$GameProcessId"
if($nativeProcess.Name -ne 'dota2.exe' -or $nativeProcess.CommandLine -notmatch '\s-tools\s' -or $nativeProcess.CommandLine -notmatch '\s-addon\s+survival(?:\s|$)'){throw 'owned_survival_tools_required'}
& "$PSScriptRoot/../focus_live_perf_window.ps1" -GameProcessId $GameProcessId -SkipCursorCenter | Out-Null
if($Escape){
 Add-Type -AssemblyName System.Windows.Forms
 [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
 Start-Sleep -Milliseconds 250
}
$nativeFilename='ui_qa_native_review_r'+$Round+'_'+$Name+'.png'
$raw=& "$PSScriptRoot/../menus_v10/window.ps1" -ProcessId $GameProcessId -Screenshot $nativeFilename -ClickX $ClickX -ClickY $ClickY -PointerX $PointerX -PointerY $PointerY -CaptureDelayMs $Delay
$nativeMeta=$raw|ConvertFrom-Json
$nativeOut=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output/ui_qa_20261025/native_review'))
[void][IO.Directory]::CreateDirectory($nativeOut)
$target=Join-Path $nativeOut ('r'+$Round+'_'+$Name+'.png')
if(Test-Path -LiteralPath $target){throw 'review_screenshot_exists_use_new_name'}
Copy-Item -LiteralPath $nativeMeta.Screenshot -Destination $target
$record=[ordered]@{round=$Round;name=$Name;at=[DateTime]::UtcNow.ToString('o');escape_sent=[bool]$Escape;actual_window=$nativeMeta;screenshot=$target;visual_review='pending_human_image_inspection'}
$record|ConvertTo-Json -Depth 5|Set-Content -LiteralPath ($target+'.json') -Encoding UTF8
$record|ConvertTo-Json -Depth 5
