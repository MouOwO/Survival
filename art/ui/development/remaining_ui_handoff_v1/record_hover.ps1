$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
$folder=Join-Path $PSScriptRoot 'evidence/button_hover_frames'
New-Item -ItemType Directory -Force -Path $folder|Out-Null
$jpg=[Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object MimeType -eq 'image/jpeg'
$parameters=[Drawing.Imaging.EncoderParameters]::new(1)
$parameters.Param[0]=[Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality,[long]92)
$bitmap=[Drawing.Bitmap]::new($window.Width,150);$graphics=[Drawing.Graphics]::FromImage($bitmap)
$watch=[Diagnostics.Stopwatch]::StartNew();$frames=@();$phase=-1
try{
 for($i=0;$i -lt 150;$i++){
  if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed; capture stopped'}
  $next=[Math]::Floor($watch.Elapsed.TotalSeconds/.3)
  if($next -ne $phase){$phase=$next;$px=if($phase%2 -eq 1){if($phase -lt 10){1130}else{1450}}else{850};$py=if($phase%2 -eq 1){884}else{750};[void][HandoffWindow]::SetCursorPos($origin.X+$px,$origin.Y+$py)}
  $at=$watch.Elapsed.TotalMilliseconds;$file=('{0:D5}.jpg' -f $i)
  $graphics.CopyFromScreen($origin.X,$origin.Y+791,0,0,$bitmap.Size);$bitmap.Save((Join-Path $folder $file),$jpg,$parameters)
  $frames+=@{file=$file;ms=$at}
  $wait=[Math]::Floor(($i+1)*40-$watch.Elapsed.TotalMilliseconds);if($wait -gt 0){Start-Sleep -Milliseconds $wait}
 }
 @{width=$window.Width;height=150;fps=25;elapsedMs=$watch.Elapsed.TotalMilliseconds;frames=$frames;source='actual Dota 2 client bottom strip; rapid mouse enter/leave only; no draws'}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $folder 'capture.json') -Encoding utf8
}finally{$graphics.Dispose();$bitmap.Dispose();$parameters.Dispose()}
node (Join-Path $PSScriptRoot 'encode_avi.cjs') $folder
