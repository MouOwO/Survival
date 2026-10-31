param(
 [Parameter(Mandatory=$true)][int]$GameProcessId,
 [Parameter(Mandatory=$true)][string]$CreatedUtc,
 [ValidateSet('Click','Key','Text','Focus')][string]$Action,
 [int]$X=-1,[int]$Y=-1,
 [ValidateSet('F9','Escape','Backslash','Enter','CtrlA')][string]$Key,
 [ValidateLength(0,256)][string]$Text,
 [ValidateSet('Unicode','AsciiKeys')][string]$TextMode='Unicode'
)
# One explicit action. Only -Action Focus may activate a window, once.
# O(W) window admission per action; O(1) focus checks per input character.
$ErrorActionPreference='Stop'
if(-not ('ArcadeInput' -as [type])){
Add-Type @'
using System;using System.Runtime.InteropServices;using System.Text;
public static class ArcadeInput {
 [StructLayout(LayoutKind.Sequential)] public struct P{public int X,Y;}
 [StructLayout(LayoutKind.Sequential)] public struct R{public int L,T,Rt,B;}
 [StructLayout(LayoutKind.Sequential)] public struct K{public ushort V,S;public uint F,T;public UIntPtr E;}
 [StructLayout(LayoutKind.Sequential)] public struct M{public int X,Y;public uint D,F,T;public UIntPtr E;}
 [StructLayout(LayoutKind.Explicit)] public struct U{[FieldOffset(0)]public K Key;[FieldOffset(0)]public M Mouse;}
 [StructLayout(LayoutKind.Sequential)] public struct I{public uint T;public U V;}
 public delegate bool EnumProc(IntPtr h,IntPtr d);
 public static uint EventsInserted;
 [DllImport("user32.dll",SetLastError=true)]public static extern uint SendInput(uint n,I[] a,int z);
 [DllImport("user32.dll",SetLastError=true)]public static extern bool EnumWindows(EnumProc p,IntPtr d);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern int GetWindowText(IntPtr h,StringBuilder t,int n);
 [DllImport("user32.dll")]public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll",SetLastError=true)]public static extern bool ClientToScreen(IntPtr h,ref P p);
 [DllImport("user32.dll",SetLastError=true)]public static extern bool GetClientRect(IntPtr h,out R r);
 [DllImport("user32.dll",SetLastError=true)]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern IntPtr WindowFromPoint(P p);
 [DllImport("user32.dll")]public static extern IntPtr GetAncestor(IntPtr h,uint f);
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")]public static extern IntPtr GetKeyboardLayout(uint thread);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern short VkKeyScanEx(char c,IntPtr layout);
 [DllImport("user32.dll")]public static extern short GetAsyncKeyState(int key);
 [DllImport("user32.dll",SetLastError=true)]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
 public static string Title(IntPtr h){var t=new StringBuilder(512);GetWindowText(h,t,t.Capacity);return t.ToString();}
 public static bool MainMatches(IntPtr h,uint pid){
  uint owner;R r;GetWindowThreadProcessId(h,out owner);
  return owner==pid&&IsWindow(h)&&IsWindowVisible(h)&&!IsIconic(h)&&Title(h)=="Dota 2"
   &&GetClientRect(h,out r)&&r.Rt-r.L>=640&&r.B-r.T>=360;
 }
 public static IntPtr FindMain(uint pid){
  IntPtr found=IntPtr.Zero;int count=0;
  EnumProc callback=(h,d)=>{if(MainMatches(h,pid)){found=h;count++;}return true;};
  if(!EnumWindows(callback,IntPtr.Zero))throw new Exception("window_enumeration_failed");
  if(count!=1)throw new Exception("unique_main_window_required");return found;
 }
 public static void RequireUniqueFocusTitle(IntPtr expected){
  bool other=false;EnumProc callback=(h,d)=>{if(h!=expected&&Title(h)=="Dota 2")other=true;return true;};
  if(!EnumWindows(callback,IntPtr.Zero))throw new Exception("window_enumeration_failed");
  if(other)throw new Exception("focus_title_ambiguous");
 }
 public static void EnsureForeground(IntPtr expected,uint pid){
  IntPtr foreground=GetForegroundWindow();uint owner;GetWindowThreadProcessId(foreground,out owner);
  if(foreground!=expected||owner!=pid)throw new Exception("input_focus_changed");
 }
 private static uint Insert(I[] values){uint n=SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(I)));EventsInserted+=n;return n;}
 public static void KeyEvent(ushort key,bool up){var a=new I{T=1,V=new U{Key=new K{V=key,F=up?2u:0u}}};if(Insert(new I[]{a})!=1)throw new Exception("input_failed");}
 public static void MouseEvent(bool up){var a=new I{T=0,V=new U{Mouse=new M{F=up?4u:2u}}};if(Insert(new I[]{a})!=1)throw new Exception("input_failed");}
 public static void Write(string text,IntPtr expected,uint pid){
  foreach(char c in text){
   EnsureForeground(expected,pid);
   var down=new I{T=1,V=new U{Key=new K{S=c,F=4}}};var up=new I{T=1,V=new U{Key=new K{S=c,F=6}}};
   uint sent=Insert(new I[]{down,up});
   if(sent!=2){if(sent==1)Insert(new I[]{up});throw new Exception("input_failed");}
  }
 }
 public static void WriteAscii(string text,IntPtr expected,uint pid){
  EnsureForeground(expected,pid);
  uint owner;uint thread=GetWindowThreadProcessId(expected,out owner);
  if(owner!=pid||thread==0)throw new Exception("input_focus_changed");
  IntPtr layout=GetKeyboardLayout(thread);
  if(layout==IntPtr.Zero)throw new Exception("ascii_keyboard_layout_unavailable");
  // Validate the whole allowlisted string before sending any key. No clipboard.
  ushort[] mapping=new ushort[text.Length];
  for(int i=0;i<text.Length;i++){
   if(text[i]<32||text[i]>126)throw new Exception("ascii_text_required");
   short result=VkKeyScanEx(text[i],layout);int key=result&255;int modifiers=(result>>8)&255;
   if(result==-1||key==0||key==0xE7||(modifiers&~7)!=0)throw new Exception("ascii_character_unmappable");
   mapping[i]=(ushort)result;
  }
  foreach(ushort item in mapping){
   EnsureForeground(expected,pid);
   if(GetKeyboardLayout(thread)!=layout)throw new Exception("ascii_keyboard_layout_changed");
   if((GetAsyncKeyState(0x10)&0x8000)!=0||(GetAsyncKeyState(0x11)&0x8000)!=0||(GetAsyncKeyState(0x12)&0x8000)!=0)
    throw new Exception("ascii_modifiers_already_down");
   ushort key=(ushort)(item&255);int modifiers=item>>8;
   bool control=false,alt=false,shift=false,down=false;
   try{
    if((modifiers&2)!=0){EnsureForeground(expected,pid);KeyEvent(0x11,false);control=true;}
    if((modifiers&4)!=0){EnsureForeground(expected,pid);KeyEvent(0x12,false);alt=true;}
    if((modifiers&1)!=0){EnsureForeground(expected,pid);KeyEvent(0x10,false);shift=true;}
    EnsureForeground(expected,pid);
    KeyEvent(key,false);down=true;
   }finally{
    // A focus change must not leave this invocation's keys held down.
    try{if(down)KeyEvent(key,true);}
    finally{try{if(shift)KeyEvent(0x10,true);}
     finally{try{if(alt)KeyEvent(0x12,true);}finally{if(control)KeyEvent(0x11,true);}}}
   }
  }
 }
}
'@
}
function Assert-InputProcess {
 $inputDetails=Get-CimInstance Win32_Process -Filter "ProcessId=$GameProcessId"
 if(-not $inputDetails -or $inputDetails.Name -ne 'dota2.exe' -or $inputDetails.CommandLine -match '(?:^|\s)-(tools|addon)(?:\s|$)' -or $null -eq $inputDetails.CreationDate -or [Math]::Abs(($inputDetails.CreationDate.ToUniversalTime()-[DateTimeOffset]::Parse($CreatedUtc).UtcDateTime).TotalMilliseconds) -gt 1){throw 'ordinary_process_identity_changed'}
}
Assert-InputProcess
$inputDpi=[ArcadeInput]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
if($inputDpi -eq [IntPtr]::Zero){throw 'physical_dpi_context_unavailable'}
try{
 $inputWindow=[ArcadeInput]::FindMain([uint32]$GameProcessId)
 $inputBefore=[ArcadeInput]::GetForegroundWindow()
 if($Action -ne 'Focus'){[ArcadeInput]::EnsureForeground($inputWindow,[uint32]$GameProcessId)}
 $inputBounds=[ArcadeInput+R]::new();if(-not [ArcadeInput]::GetClientRect($inputWindow,[ref]$inputBounds)){throw 'client_bounds_unavailable'}
 $inputInsertedBefore=[ArcadeInput]::EventsInserted
 $inputStopped=$false;$inputFocusAccepted=$false
 try{
 if($Action -eq 'Click'){
  if($X -lt 0 -or $Y -lt 0 -or $X -ge $inputBounds.Rt -or $Y -ge $inputBounds.B){throw 'point_outside_client'}
  $inputPoint=[ArcadeInput+P]::new();$inputPoint.X=$X;$inputPoint.Y=$Y
  if(-not [ArcadeInput]::ClientToScreen($inputWindow,[ref]$inputPoint) -or [ArcadeInput]::GetAncestor([ArcadeInput]::WindowFromPoint($inputPoint),2) -ne $inputWindow){throw 'point_occluded'}
  if(-not [ArcadeInput]::SetCursorPos($inputPoint.X,$inputPoint.Y)){throw 'cursor_position_failed'}
  [ArcadeInput]::EnsureForeground($inputWindow,[uint32]$GameProcessId)
  [ArcadeInput]::MouseEvent($false);try{Start-Sleep -Milliseconds 80}finally{[ArcadeInput]::MouseEvent($true)}
 }elseif($Action -eq 'Key'){
  $inputCode=@{F9=0x78;Escape=0x1B;Backslash=0xDC;Enter=0x0D;CtrlA=0x41}[$Key]
  if(-not $inputCode){throw 'key_required'}
  [ArcadeInput]::EnsureForeground($inputWindow,[uint32]$GameProcessId)
  if($Key -eq 'CtrlA'){[ArcadeInput]::KeyEvent(0x11,$false)}
  try{[ArcadeInput]::EnsureForeground($inputWindow,[uint32]$GameProcessId);[ArcadeInput]::KeyEvent($inputCode,$false);try{Start-Sleep -Milliseconds 80}finally{[ArcadeInput]::KeyEvent($inputCode,$true)}}finally{if($Key -eq 'CtrlA'){[ArcadeInput]::KeyEvent(0x11,$true)}}
 }elseif($Action -eq 'Text'){
  # UI search or explicitly bounded native read/log commands; never arbitrary scripts or server mutations.
  if($Text -notmatch '^(console|控制台|con_enable|sv_cheats|fps_max|fps_max_ui|r_vsync|mat_vsync|cl_showfps|dota_camera_get_lookatpos|help dota_camera_set_lookatpos|dota_camera_set_lookatpos -5716 6592 110|(?:help )?dota_dump_scene_panel_state|hideconsole|condump|con_logfile(?: output/arcade_portrait_perf_20261031/[a-z0-9_]+\.log)?|echo ARCADE_[A-Z0-9_]+)$'){throw 'text_not_allowlisted'}
  if($TextMode -eq 'AsciiKeys'){[ArcadeInput]::WriteAscii($Text,$inputWindow,[uint32]$GameProcessId)}
  else{[ArcadeInput]::Write($Text,$inputWindow,[uint32]$GameProcessId)}
 }elseif($Action -eq 'Focus'){
  # Title activation is explicit, single-attempt, and refused when ambiguous.
  [ArcadeInput]::RequireUniqueFocusTitle($inputWindow)
  $inputShell=New-Object -ComObject WScript.Shell
  try{$inputFocusAccepted=[bool]$inputShell.AppActivate('Dota 2')}
  finally{if([Runtime.InteropServices.Marshal]::IsComObject($inputShell)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($inputShell)}}
 }else{throw 'action_required'}
 }catch{
  if($_.Exception.InnerException -and $_.Exception.InnerException.Message -eq 'input_focus_changed'){$inputStopped=$true}else{throw}
 }
 # Allow one native UI transition to settle before the next explicit action.
 Start-Sleep -Milliseconds 250
 $inputAfter=[ArcadeInput]::GetForegroundWindow();[uint32]$inputAfterOwner=0
 [void][ArcadeInput]::GetWindowThreadProcessId($inputAfter,[ref]$inputAfterOwner)
 $inputChanged=$inputAfter -ne $inputWindow -or $inputAfterOwner -ne $GameProcessId
 $inputMainValid=[ArcadeInput]::MainMatches($inputWindow,[uint32]$GameProcessId)
 $inputProcessValid=$true;try{Assert-InputProcess}catch{$inputProcessValid=$false}
 $inputStatus=if($Action -eq 'Focus'){if($inputFocusAccepted -and -not $inputChanged -and $inputMainValid -and $inputProcessValid){'FOCUS_ESTABLISHED'}else{'FOCUS_NOT_ESTABLISHED'}}elseif($inputStopped){'ACTION_STOPPED_FOCUS_CHANGED'}elseif($inputChanged){'ACTION_COMPLETED_FOCUS_CHANGED'}elseif(-not $inputMainValid -or -not $inputProcessValid){'ACTION_COMPLETED_IDENTITY_CHANGED'}else{'ACTION_COMPLETED'}
 [ordered]@{pid=$GameProcessId;action=$Action;key=$Key;text_mode=$TextMode;x=$X;y=$Y;status=$inputStatus;main_hwnd=$inputWindow.ToInt64();foreground_before=$inputBefore.ToInt64();foreground_after=$inputAfter.ToInt64();foreground_after_pid=$inputAfterOwner;focus_changed=$inputChanged;stopped_on_focus_change=$inputStopped;main_window_valid=$inputMainValid;process_identity_valid=$inputProcessValid;events_inserted=([ArcadeInput]::EventsInserted-$inputInsertedBefore);focus_attempts=$(if($Action -eq 'Focus'){1}else{0});automatic_retry=$false;account_operations=0;script_injection=$false}|ConvertTo-Json -Compress
}finally{[void][ArcadeInput]::SetThreadDpiAwarenessContext($inputDpi)}
