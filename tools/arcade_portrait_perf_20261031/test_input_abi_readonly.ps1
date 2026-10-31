# Read the actual helper's C# declarations; never invoke a user32 entry point.
$ErrorActionPreference='Stop'
$abiSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'input_arcade.ps1') -Raw
$abiMatch=[regex]::Match($abiSource,"(?s)Add-Type @'\r?\n(.*?)\r?\n'@")
if(-not $abiMatch.Success){throw 'Native input declarations not found'}
if(-not ('ArcadeInput' -as [type])){Add-Type -TypeDefinition $abiMatch.Groups[1].Value}
$abiPointer=[IntPtr]::Size
$abiExpected=if($abiPointer -eq 8){@(40,8,24,16,32,24)}elseif($abiPointer -eq 4){@(28,4,16,12,24,20)}else{throw 'Unsupported pointer width'}
$abiActual=@(
 [Runtime.InteropServices.Marshal]::SizeOf([type][ArcadeInput+I]),
 [Runtime.InteropServices.Marshal]::OffsetOf([type][ArcadeInput+I],'V').ToInt32(),
 [Runtime.InteropServices.Marshal]::SizeOf([type][ArcadeInput+K]),
 [Runtime.InteropServices.Marshal]::OffsetOf([type][ArcadeInput+K],'E').ToInt32(),
 [Runtime.InteropServices.Marshal]::SizeOf([type][ArcadeInput+M]),
 [Runtime.InteropServices.Marshal]::OffsetOf([type][ArcadeInput+M],'E').ToInt32()
)
for($abiIndex=0;$abiIndex -lt $abiExpected.Count;$abiIndex++){
 if($abiActual[$abiIndex] -ne $abiExpected[$abiIndex]){throw ('Native INPUT ABI mismatch at field '+$abiIndex)}
}
[ordered]@{status='ACTUAL_INPUT_ABI_READONLY_PASS';pointer_bytes=$abiPointer;input_bytes=$abiActual[0];union_offset=$abiActual[1];key_bytes=$abiActual[2];key_extra_offset=$abiActual[3];mouse_bytes=$abiActual[4];mouse_extra_offset=$abiActual[5];sendinput_calls=0;ui_operations=0;source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'input_arcade.ps1') -Algorithm SHA256).Hash}|ConvertTo-Json -Compress
