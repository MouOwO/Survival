param(
 [Parameter(Mandatory=$true)][int]$GameProcessId,
 [Parameter(Mandatory=$true)][ValidateRange(1,5)][int]$Round,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9_]{1,35}$')][string]$Tag
)
# Capture the same first-open archive at three times, without closing it.
$ErrorActionPreference='Stop'
$qaProcess=Get-CimInstance Win32_Process -Filter "ProcessId=$GameProcessId"
if($qaProcess.Name -ne 'dota2.exe' -or $qaProcess.CommandLine -notmatch '\s-tools\s' -or $qaProcess.CommandLine -notmatch '\s-addon\s+survival(?:\s|$)' -or $qaProcess.CommandLine -notmatch 'survival_offline_logic_test 1'){throw 'owned_offline_tools_required'}
$qaOut=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../output/ui_qa_20261025/native_review'))
$qaReport=Join-Path $qaOut ('archive_timeline_'+$Tag+'.json')
if(Test-Path -LiteralPath $qaReport){throw 'timeline_report_exists'}
foreach($ms in @(500,2000,10000)){if(Test-Path -LiteralPath (Join-Path $qaOut ('r'+$Round+'_'+$Tag+'_'+$ms+'ms.png'))){throw 'timeline_image_exists'}}
& "$PSScriptRoot/../focus_live_perf_window.ps1" -GameProcessId $GameProcessId -SkipCursorCenter | Out-Null
$qaWindowScript=Join-Path $PSScriptRoot '../menus_v10/window.ps1'
# Warm the existing read-only window validation/PInvoke, never the archive.
$qaWarm=& $qaWindowScript -ProcessId $GameProcessId -CaptureDelayMs 0 | ConvertFrom-Json
$qaOpened=& $qaWindowScript -ProcessId $GameProcessId -ClickX 156 -ClickY 44 -CaptureDelayMs 0 | ConvertFrom-Json
if(-not $qaOpened.ClickSent){throw 'archive_physical_click_missing'}
$qaClock=[Diagnostics.Stopwatch]::StartNew()
$qaSamples=@()
foreach($qaTargetMs in @(500,2000,10000)){
 $qaRemaining=$qaTargetMs-$qaClock.ElapsedMilliseconds
 if($qaRemaining -gt 0){Start-Sleep -Milliseconds $qaRemaining}
 $qaBefore=$qaClock.ElapsedMilliseconds
 $qaName='ui_qa_archive_timeline_r'+$Round+'_'+$Tag+'_'+$qaTargetMs+'ms.png'
 $qaMeta=& $qaWindowScript -ProcessId $GameProcessId -Screenshot $qaName -CaptureDelayMs 0 | ConvertFrom-Json
 $qaAfter=$qaClock.ElapsedMilliseconds
 $qaDest=Join-Path $qaOut ('r'+$Round+'_'+$Tag+'_'+$qaTargetMs+'ms.png')
 Copy-Item -LiteralPath $qaMeta.Screenshot -Destination $qaDest
 $qaDigest=[Security.Cryptography.SHA256]::Create();$qaStream=[IO.File]::OpenRead($qaDest)
 try{$qaHash=[BitConverter]::ToString($qaDigest.ComputeHash($qaStream)).Replace('-','').ToLowerInvariant()}finally{$qaStream.Dispose();$qaDigest.Dispose()}
 $qaSamples+=@{target_after_click_ms=$qaTargetMs;capture_call_before_ms=$qaBefore;capture_call_after_ms=$qaAfter;screenshot=$qaDest;sha256=$qaHash;window=$qaMeta;visual_review='pending_actual_image_inspection'}
}
$qaRecord=[ordered]@{schema=1;round=$Round;tag=$Tag;at=[DateTime]::UtcNow.ToString('o');scope='native_offline_first_archive_open_continuous_500_2000_10000ms';closed_between_samples=$false;physical_click=$qaOpened;samples=$qaSamples}
$qaRecord|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $qaReport -Encoding UTF8
$qaRecord|ConvertTo-Json -Depth 6
