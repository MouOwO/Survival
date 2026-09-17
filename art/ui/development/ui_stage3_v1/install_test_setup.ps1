$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$target=[IO.Path]::GetFullPath((Join-Path $repo '../survival_ui_handoff_v1/scripts/vscripts/addon_game_mode.lua'))
if($target -notlike '*\survival_ui_handoff_v1\scripts\vscripts\addon_game_mode.lua'){throw 'Not isolated addon'}
$backup=Join-Path $PSScriptRoot 'before/test_addon_game_mode.lua'
if(-not(Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $target -Destination $backup}
$code=[IO.File]::ReadAllText($backup)
if($code -notmatch 'UI_STAGE3_TEST_COMMAND'){
 $hook="`n-- UI_STAGE3_TEST_COMMAND: isolated Tools inspection, never a production rule.`nif IsInToolsMode() then`n Convars:RegisterCommand('ui_stage3_setup', function() require('ui_stage3_setup')() end, 'Pause isolated UI test deadlines', 0)`nend`n"
 $code=[regex]::Replace($code,'return M\s*$',$hook+"`nreturn M`n")
 [IO.File]::WriteAllText($target,$code,[Text.UTF8Encoding]::new($false))
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test_setup.lua') -Destination (Join-Path (Split-Path -Parent $target) 'ui_stage3_setup.lua') -Force
