param(
 [Parameter(Mandatory=$true)][int]$GameProcessId,
 [Parameter(Mandatory=$true)][string]$CreatedUtc,
 [ValidateSet('Backslash','Enter','Escape')][string]$Key='Backslash'
)
$ErrorActionPreference='Stop'
$base=Join-Path $PSScriptRoot 'arcade_portrait_perf_20261031/input_arcade.ps1'
if((Get-FileHash -LiteralPath $base).Hash.ToLowerInvariant() -ne '59709044702b5de6ff740ee563efccfb9afca465b225fd73b399ad5d8b17d0e1'){throw 'native_input_reference_changed'}
$code=[IO.File]::ReadAllText($base)
$native=[regex]::Match($code,"(?s)Add-Type @'\r?\n(.*?)\r?\n'@")
if(-not $native.Success){throw 'native_input_type_anchor_missing'}
if(-not ('ArcadeInput' -as [type])){Add-Type -TypeDefinition $native.Groups[1].Value}
if(-not ('LotteryNativeScanV1' -as [type])){Add-Type @'
using System;using System.Runtime.InteropServices;
public static class LotteryNativeScanV1 {
 [StructLayout(LayoutKind.Sequential)] public struct K{public ushort V,S;public uint F,T;public UIntPtr E;}
 [StructLayout(LayoutKind.Explicit,Size=32)] public struct U{[FieldOffset(0)] public K key;}
 [StructLayout(LayoutKind.Sequential)] public struct I{public uint type;public U data;}
 [DllImport("user32.dll",SetLastError=true)]static extern uint SendInput(uint n,I[] a,int size);
 public static void Key(ushort scan,bool up){var i=new I{type=1,data=new U{key=new K{S=scan,F=up?10u:8u}}};if(SendInput(1,new I[]{i},Marshal.SizeOf(typeof(I)))!=1)throw new Exception("native_scan_input_failed");}
}
'@}
function Identity {
 $p=Get-CimInstance Win32_Process -Filter "ProcessId=$GameProcessId"
 if(-not $p -or $p.Name -ne 'dota2.exe' -or $p.CommandLine -match '(?:^|\s)-(tools|addon)(?:\s|$)' -or [Math]::Abs(($p.CreationDate.ToUniversalTime()-[DateTimeOffset]::Parse($CreatedUtc).UtcDateTime).TotalMilliseconds) -gt 1){throw 'ordinary_client_identity_changed'}
}
Identity
$window=[ArcadeInput]::FindMain([uint32]$GameProcessId)
[ArcadeInput]::EnsureForeground($window,[uint32]$GameProcessId)
$scan=@{Backslash=0x2B;Enter=0x1C;Escape=0x01}[$Key]
[LotteryNativeScanV1]::Key([ushort]$scan,$false)
try{Start-Sleep -Milliseconds 80}finally{[LotteryNativeScanV1]::Key([ushort]$scan,$true)}
Identity
[ordered]@{pid=$GameProcessId;key=$Key;scan_code=$scan;events_inserted=2;script_injection=$false;account_operations=0;automatic_retry=$false}|ConvertTo-Json -Compress
