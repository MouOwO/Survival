param([Parameter(Mandatory=$true)][ValidateSet('single','ten','ten_skip','rogue','boss')][string]$Mode,[string]$Name,[int]$Seconds=8,[int]$Fps=20,[ValidateSet(5,10,15)][int]$BossWave=5)
$ErrorActionPreference='Stop'
$captureMode=$Mode
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
$captureName=if($Name){$Name}else{$captureMode}
if($captureName -notmatch '^[a-z0-9_]+$'){throw 'Invalid evidence name'}
$folder=Join-Path $PSScriptRoot ('evidence/'+$captureName+'_frames')
if(Test-Path -LiteralPath $folder){throw 'Recording already exists; preserve earlier evidence'}
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$jpg=[Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object MimeType -eq 'image/jpeg'
$parameters=[Drawing.Imaging.EncoderParameters]::new(1)
$parameters.Param[0]=[Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality,[long]88)
$bitmap=[Drawing.Bitmap]::new($window.Width,$window.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
$watch=[Diagnostics.Stopwatch]::StartNew();$frames=@();$sent=$false;$second=$false
function Click-Test([int]$px,[int]$py){
 $px=[int][Math]::Round($px*$window.Width/1672);$py=[int][Math]::Round($py*$window.Height/941)
 if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed'}
 [void][HandoffWindow]::SetCursorPos($origin.X+$px,$origin.Y+$py)
 Start-Sleep -Milliseconds 150
 if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed after pointer move'}
 [HandoffWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 120
 [HandoffWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
}
try{
 for($i=0;$i -lt $Seconds*$Fps;$i++){
  if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed; recording stopped'}
  if(-not $sent -and $watch.Elapsed.TotalSeconds -ge .5){
   if($captureMode -in @('single','ten','ten_skip')){Click-Test $(if($captureMode -eq 'single'){1145}else{1450}) 884}
   else{
    $command=if($captureMode -eq 'boss'){'-monster '+$BossWave}else{'-rogue recruit_training tower_growth frozen_wall'}
    [HandoffWindow]::keybd_event(13,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 120
    [HandoffWindow]::keybd_event(13,0,2,[UIntPtr]::Zero);Start-Sleep -Milliseconds 250
    [Windows.Forms.SendKeys]::SendWait($command);Start-Sleep -Milliseconds 250
    [HandoffWindow]::keybd_event(13,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 120
    [HandoffWindow]::keybd_event(13,0,2,[UIntPtr]::Zero)
   };$sent=$true
  }
  if(-not $second -and $watch.Elapsed.TotalSeconds -ge $(if($captureMode -eq 'ten_skip'){2.3}else{3.4})){
   if($captureMode -eq 'ten_skip'){Click-Test 1570 122}
   elseif($captureMode -eq 'rogue'){[void][HandoffWindow]::SetCursorPos($origin.X+[int](830*$window.Width/1672),$origin.Y+[int](500*$window.Height/941))}
   $second=$true
  }
  $at=$watch.Elapsed.TotalMilliseconds;$file=('{0:D5}.jpg' -f $i)
  $graphics.CopyFromScreen($origin.X,$origin.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $folder $file),$jpg,$parameters)
  $frames+=@{file=$file;ms=$at}
  $wait=[Math]::Floor(($i+1)*1000/$Fps-$watch.Elapsed.TotalMilliseconds);if($wait -gt 0){Start-Sleep -Milliseconds $wait}
 }
 @{width=$window.Width;height=$window.Height;fps=$Fps;elapsedMs=$watch.Elapsed.TotalMilliseconds;frames=$frames;source='Actual isolated Dota client capture; existing server draw/debug_offer/debug_spawn_wave; no synthetic frames';mode=$captureMode}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $folder 'capture.json') -Encoding utf8
}finally{$graphics.Dispose();$bitmap.Dispose();$parameters.Dispose()}
node (Join-Path $PSScriptRoot '../remaining_ui_handoff_v1/encode_avi.cjs') $folder
