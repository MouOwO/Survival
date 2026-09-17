param([string]$Name='walkthrough')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
$folder=Join-Path $PSScriptRoot ('evidence/'+$Name+'_frames')
if(Test-Path -LiteralPath $folder){throw 'Keep existing recording'}
New-Item -ItemType Directory -Force $folder | Out-Null
$steps=@(
 @(0.5,350,38,1,'entry'),@(2.5,590,210,1,'items'),@(4.5,780,210,1,'technology'),@(6.5,980,210,1,'challenge'),@(8.5,1170,210,1,'rebirth'),@(10.5,1360,210,1,'bundles'),@(12.5,390,210,1,'catalog'),@(14.5,430,450,0,'hover'),@(16.5,430,530,1,'order'),@(18.5,982,498,1,'quantity'),@(20.5,980,575,1,'method'),@(22.5,1060,687,1,'qr'),@(24.5,490,775,1,'loading'),@(26.5,640,775,1,'waiting'),@(28.5,800,775,1,'qr_failed'),@(30.5,957,775,1,'expired'),@(32.5,1110,775,1,'success'),@(34.5,1267,775,1,'failed'),@(36.5,640,775,1,'waiting_again'),@(38.5,880,700,1,'return'),@(40.5,725,450,0,'second_hover'),@(42.5,725,530,1,'second_order'),@(44.5,1340,149,1,'cancel'),@(46.5,1470,110,1,'closed'),@(48.5,350,38,1,'reopened'))
$bitmap=[Drawing.Bitmap]::new($window.Width,$window.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
$jpg=[Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object MimeType -eq 'image/jpeg'
$parameters=[Drawing.Imaging.EncoderParameters]::new(1);$parameters.Param[0]=[Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality,[long]85)
$watch=[Diagnostics.Stopwatch]::StartNew();$frames=@();$next=0;$captureAt=0;$captureLabel=$null;$fps=10
try{
 for($i=0;$i -lt 510;$i++){
  if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed; recording stopped'}
  if($next -lt $steps.Count -and $watch.Elapsed.TotalSeconds -ge $steps[$next][0]){
   $s=$steps[$next];[void][HandoffWindow]::SetCursorPos($origin.X+[int]($s[1]*$window.Width/1768),$origin.Y+[int]($s[2]*$window.Height/992));Start-Sleep -Milliseconds 160
   if($s[3]){[HandoffWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 70;[HandoffWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero)}
   $captureAt=$watch.Elapsed.TotalSeconds+.9;$captureLabel=$s[4];$next++
  }
  $at=$watch.Elapsed.TotalMilliseconds;$file=('{0:D5}.jpg' -f $i);$graphics.CopyFromScreen($origin.X,$origin.Y,0,0,$bitmap.Size);$bitmap.Save((Join-Path $folder $file),$jpg,$parameters);$frames+=@{file=$file;ms=$at}
  if($captureLabel -and $watch.Elapsed.TotalSeconds -ge $captureAt){$bitmap.Save((Join-Path (Split-Path $folder) ($Name+'_'+$captureLabel+'.png')),[Drawing.Imaging.ImageFormat]::Png);$captureLabel=$null}
  $wait=[Math]::Floor(($i+1)*1000/$fps-$watch.Elapsed.TotalMilliseconds);if($wait -gt 0){Start-Sleep -Milliseconds $wait}
 }
 @{width=$window.Width;height=$window.Height;fps=$fps;elapsedMs=$watch.Elapsed.TotalMilliseconds;frames=$frames;source='Actual Dota test-client capture of local-only commerce preview, physical mouse input'}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $folder 'capture.json') -Encoding utf8
}finally{$graphics.Dispose();$bitmap.Dispose();$parameters.Dispose()}
node (Join-Path $PSScriptRoot '../remaining_ui_handoff_v1/encode_avi.cjs') $folder
