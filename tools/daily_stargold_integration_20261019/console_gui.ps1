[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$GameProcessId,
 [Parameter(Mandatory=$true)][ValidateSet('Toggle','Command','Screenshot')][string]$Action,
 [string]$Command,
 [switch]$ConsoleVerifiedOpen,
 [string]$Screenshot,
 [ValidateRange(100,3000)][int]$CaptureDelayMs=600
)
# This helper has no socket, clipboard, order, grant or match-state operation.
# The caller must visually verify Toggle's screenshot before Command is allowed.
$ErrorActionPreference='Stop'
$dailyConsoleRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if($Action -eq 'Command'){
 if(-not $ConsoleVerifiedOpen){throw 'First use Toggle with Screenshot, visually confirm the console is open, then pass -ConsoleVerifiedOpen.'}
 if($Command -cnotmatch '^survival_window_review_[0-9]{10,16} (benefit|inspect|nav|close)$'){
  throw 'Only the explicit read-only window-review commands are allowed.'
 }
}elseif($Command){throw 'Command text is only accepted with -Action Command.'}
if($Action -eq 'Toggle' -and -not $Screenshot){throw 'Toggle requires a screenshot for visual console verification.'}
if($Screenshot -and ($Screenshot -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*\.png$')){throw 'Screenshot must be a safe PNG basename, without a directory.'}
if($Action -eq 'Screenshot' -and -not $Screenshot){throw 'Screenshot action requires a PNG basename.'}
function Assert-DailyConsoleProcess {
 $details=Get-CimInstance Win32_Process -Filter "ProcessId=$GameProcessId" -ErrorAction Stop
 if($null -eq $details -or $details.Name -ine 'dota2.exe' -or
  $details.CommandLine -notmatch '(?:^|\s)-tools(?:\s|$)' -or
  $details.CommandLine -notmatch '(?:^|\s)-addon\s+"?survival"?(?:\s|$)'){
  throw 'Target is not the explicitly launched survival Tools Dota client.'
 }
 return $details.CreationDate.ToUniversalTime().ToString('o')
}
$dailyConsoleCreated=Assert-DailyConsoleProcess
$dailyConsoleCurrent=& (Join-Path $dailyConsoleRepo 'tools/menus_v10/window.ps1') -ProcessId $GameProcessId | ConvertFrom-Json
$dailyConsoleWindow=[IntPtr]::new([long]$dailyConsoleCurrent.WindowHandle)
if(-not ('DailyStargoldConsoleInputV1' -as [type])){
 Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DailyStargoldConsoleInputV1 {
 [StructLayout(LayoutKind.Sequential)] public struct MouseInput {public int X,Y;public uint Data,Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Sequential)] public struct KeyboardInput {public ushort VirtualKey,Scan;public uint Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Explicit)] public struct InputUnion {[FieldOffset(0)] public MouseInput Mouse;[FieldOffset(0)] public KeyboardInput Keyboard;}
 [StructLayout(LayoutKind.Sequential)] public struct Input {public uint Type;public InputUnion Value;}
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window,out uint owner);
 [DllImport("user32.dll")] public static extern uint SendInput(uint count,Input[] inputs,int size);
 public static void Verify(IntPtr window,uint pid) {
  uint owner;GetWindowThreadProcessId(window,out owner);
  if(owner!=pid||GetForegroundWindow()!=window)throw new InvalidOperationException("Dota focus changed: expected="+window.ToInt64()+" current="+GetForegroundWindow().ToInt64()+" expectedPid="+pid+" windowOwner="+owner);
 }
 private static void SendKey(IntPtr window,uint pid,ushort key,ushort scan,uint flags) {
  Verify(window,pid);
  var input=new Input {Type=1,Value=new InputUnion {Keyboard=new KeyboardInput {VirtualKey=key,Scan=scan,Flags=flags}}};
  if(SendInput(1,new Input[]{input},Marshal.SizeOf(typeof(Input)))!=1)throw new InvalidOperationException("Keyboard delivery failed.");
 }
 private static void Release(ushort key,ushort scan,uint flags) {
  var input=new Input {Type=1,Value=new InputUnion {Keyboard=new KeyboardInput {VirtualKey=key,Scan=scan,Flags=flags|2}}};
  if(SendInput(1,new Input[]{input},Marshal.SizeOf(typeof(Input)))!=1)throw new InvalidOperationException("Keyboard release failed.");
 }
 public static void VirtualKey(IntPtr window,uint pid,ushort key) {
  if(key!=0xDC&&key!=0x0D)throw new ArgumentOutOfRangeException("key");
  SendKey(window,pid,key,0,0);
  try {System.Threading.Thread.Sleep(65);}finally{Release(key,0,0);}
  Verify(window,pid);
 }
 public static void TypeAscii(IntPtr window,uint pid,string text) {
  if(String.IsNullOrEmpty(text)||text.Length>128)throw new ArgumentException("Invalid command length.");
  foreach(char c in text) {
   if(c<32||c>126)throw new ArgumentException("Only printable ASCII is accepted.");
   SendKey(window,pid,0,(ushort)c,4);
   try {System.Threading.Thread.Sleep(9);}finally{Release(0,(ushort)c,4);}
  }
  Verify(window,pid);
 }
}
'@
}
if((Assert-DailyConsoleProcess) -ne $dailyConsoleCreated){throw 'Dota process identity changed before input.'}
if($Action -ne 'Screenshot'){
 # Compile/CIM initialization precedes the final focus; no helper process can
 # take foreground between the verification and the first key event.
 $dailyConsoleFocus=& (Join-Path $dailyConsoleRepo 'tools/focus_live_perf_window.ps1') -GameProcessId $GameProcessId -SkipCursorCenter | ConvertFrom-Json
 $dailyConsoleWindow=[IntPtr]::new([long]$dailyConsoleFocus.window)
}
[DailyStargoldConsoleInputV1]::Verify($dailyConsoleWindow,[uint32]$GameProcessId)
$dailyConsoleInputSent=$false
if($Action -eq 'Toggle'){
 # Installed user_keys_dev_default.vcfg and user_keys_default.vcfg both bind backslash to toggleconsole.
 [DailyStargoldConsoleInputV1]::VirtualKey($dailyConsoleWindow,[uint32]$GameProcessId,0xDC)
 $dailyConsoleInputSent=$true
}elseif($Action -eq 'Command'){
 # Do not toggle here: the visually verified console must already be open.
 [DailyStargoldConsoleInputV1]::TypeAscii($dailyConsoleWindow,[uint32]$GameProcessId,$Command)
 Start-Sleep -Milliseconds 120
 [DailyStargoldConsoleInputV1]::VirtualKey($dailyConsoleWindow,[uint32]$GameProcessId,0x0D)
 $dailyConsoleInputSent=$true
}
if($Screenshot){
 $dailyConsoleCapture=& (Join-Path $dailyConsoleRepo 'tools/menus_v10/window.ps1') -ProcessId $GameProcessId -Screenshot $Screenshot -CaptureDelayMs $CaptureDelayMs | ConvertFrom-Json
}else{$dailyConsoleCapture=$null}
if((Assert-DailyConsoleProcess) -ne $dailyConsoleCreated){throw 'Dota process identity changed during operation.'}
[DailyStargoldConsoleInputV1]::Verify($dailyConsoleWindow,[uint32]$GameProcessId)
[pscustomobject]@{
 action=$Action;pid=$GameProcessId;window=$dailyConsoleWindow.ToInt64();native=$true
 inputSent=$dailyConsoleInputSent;command=$Command;callerVisuallyVerifiedConsole=[bool]$ConsoleVerifiedOpen
 consoleOpenAutomaticallyVerified=$false;clipboardUsed=$false;socketUsed=$false
 capture=$dailyConsoleCapture
}|ConvertTo-Json -Depth 6
