# Parse the real helper and exercise only its extracted fixed-key branch using
# a fake native type. No CIM, live window, key input, focus or Dota process runs.
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'network50_dev_input.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'actual_input_helper_parser_failed'}
$actionParam=@($ast.ParamBlock.Parameters | Where-Object {$_.Name.VariablePath.UserPath -eq 'Action'})
$allowed=@($actionParam.Attributes | Where-Object {$_.TypeName.Name -eq 'ValidateSet'}).PositionalArguments.Value
if(($allowed -join ',') -ne 'Focus,Click,Screenshot,SelectBuilder,CancelTarget'){throw 'fixed_action_allowlist_changed'}
$names=@($ast.ParamBlock.Parameters | ForEach-Object {$_.Name.VariablePath.UserPath})
if(($names -join ',') -ne 'Action,Run,X,Y,Name'){throw 'arbitrary_key_text_or_command_parameter_added'}
$branch=$null
foreach($if in $ast.FindAll({param($node)$node -is [Management.Automation.Language.IfStatementAst]},$true)){
 foreach($clause in $if.Clauses){
  if($clause.Item1.Extent.Text -eq "`$Action -eq 'SelectBuilder' -or `$Action -eq 'CancelTarget'"){$branch=$clause.Item2}
 }
}
if(-not $branch){throw 'actual_fixed_key_branch_missing'}
$text=$branch.Extent.Text
$body=[scriptblock]::Create($text.Substring(1,$text.Length-2))
Add-Type @'
using System;
using System.Collections.Generic;
public static class ArcadeInput {
 public static List<string> Calls=new List<string>();
 public static bool FailForeground, FailDown;
 public static void EnsureForeground(IntPtr window,uint pid) {Calls.Add("foreground");if(FailForeground)throw new Exception("not_foreground");}
 public static void KeyEvent(ushort key,bool up) {Calls.Add(key+":"+(up?"up":"down"));if(!up&&FailDown)throw new Exception("down_failed");}
}
'@
$window=[IntPtr]::new(1);$gameProcess=42;$script:IdentityValid=$true
function Assert-DevProcess {
 [ArcadeInput]::Calls.Add('identity')
 if(-not $script:IdentityValid){throw 'owned_identity_changed'}
}
function Expect([string]$wanted){
 $actual=[ArcadeInput]::Calls -join ','
 if($actual -ne $wanted){throw ('actual_branch_call_order_mismatch:'+ $actual)}
 [ArcadeInput]::Calls.Clear()
}
$Action='SelectBuilder';& $body
Expect 'identity,foreground,113:down,113:up'
$Action='CancelTarget';& $body
Expect 'identity,foreground,27:down,27:up'
[ArcadeInput]::FailDown=$true
try{& $body;throw 'expected_down_failure'}catch{if($_.Exception.Message -eq 'expected_down_failure'){throw}}
Expect 'identity,foreground,27:down,27:up'
[ArcadeInput]::FailDown=$false;[ArcadeInput]::FailForeground=$true
try{& $body;throw 'expected_foreground_failure'}catch{if($_.Exception.Message -eq 'expected_foreground_failure'){throw}}
Expect 'identity,foreground'
[ArcadeInput]::FailForeground=$false;$script:IdentityValid=$false
try{& $body;throw 'expected_identity_failure'}catch{if($_.Exception.Message -eq 'expected_identity_failure'){throw}}
Expect 'identity'
Write-Output 'NETWORK50_DEV_INPUT_PASS actual PS Parser; only fixed F2/Escape; owner/foreground before input; finally release on failure; no native input/focus/process performed'
