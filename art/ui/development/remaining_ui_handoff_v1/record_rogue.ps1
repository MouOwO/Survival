param([string]$Name='rogue_motion',[int]$Seconds=8,[int]$Fps=25)
$ErrorActionPreference='Stop'
$captureName=$Name
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
if($captureName -notmatch '^[a-z0-9_]+$'){throw 'Invalid capture name'}
$folder=Join-Path $PSScriptRoot ('evidence/'+$captureName+'_frames')
New-Item -ItemType Directory -Force -Path $folder|Out-Null
$jpg=[Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object MimeType -eq 'image/jpeg'
$parameters=[Drawing.Imaging.EncoderParameters]::new(1)
$parameters.Param[0]=[Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality,[long]88)
$bitmap=[Drawing.Bitmap]::new($window.Width,$window.Height)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$watch=[Diagnostics.Stopwatch]::StartNew()
$frames=@();$sent=$false;$hovered=$false;$left=$false
try{
 for($i=0;$i -lt $Seconds*$Fps;$i++){
  if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed; recording stopped'}
  if(-not $sent -and $watch.Elapsed.TotalSeconds -ge .5){
   [Windows.Forms.SendKeys]::SendWait('{ENTER}')
   [Windows.Forms.SendKeys]::SendWait('-rogue recruit_training tower_growth frozen_wall{ENTER}')
   $sent=$true
  }
  if(-not $hovered -and $watch.Elapsed.TotalSeconds -ge 3.3){[void][HandoffWindow]::SetCursorPos($origin.X+830,$origin.Y+500);$hovered=$true}
  if(-not $left -and $watch.Elapsed.TotalSeconds -ge 5.3){[void][HandoffWindow]::SetCursorPos($origin.X+150,$origin.Y+500);$left=$true}
  $at=$watch.Elapsed.TotalMilliseconds
  $graphics.CopyFromScreen($origin.X,$origin.Y,0,0,$bitmap.Size)
  $file=('{0:D5}.jpg' -f $i)
  $bitmap.Save((Join-Path $folder $file),$jpg,$parameters)
  $frames+=@{file=$file;ms=$at}
  $wait=[Math]::Floor(($i+1)*1000/$Fps-$watch.Elapsed.TotalMilliseconds)
  if($wait -gt 0){Start-Sleep -Milliseconds $wait}
 }
 @{width=$window.Width;height=$window.Height;fps=$Fps;elapsedMs=$watch.Elapsed.TotalMilliseconds;frames=$frames;source='actual Dota 2 isolated test game; existing server debug_offer; no synthetic frames'}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $folder 'capture.json') -Encoding utf8
}finally{$graphics.Dispose();$bitmap.Dispose();$parameters.Dispose()}
node (Join-Path $PSScriptRoot 'encode_avi.cjs') $folder
