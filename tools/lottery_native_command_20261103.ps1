param(
 [Parameter(Mandatory=$true)][int]$GameProcessId,
 [Parameter(Mandatory=$true)][string]$CreatedUtc,
 [Parameter(Mandatory=$true)][string]$Command
)
# Keyboard input to the existing native console only. No game script evaluation,
# resource writes, draw/purchase/redeem commands or user-selected tool paths.
$ErrorActionPreference='Stop'
$allowed='^(?:clear|hideconsole|echo ARCADE_[A-Z0-9_]+|lottery_film_(?:map|cultivation|dragon_knight|summer)_[0-9]{10,16}|archive_view_action_[0-9]{10,16} (?:audit|open|close))$'
if($Command -cnotmatch $allowed){throw 'native_diagnostic_command_not_allowlisted'}
$tool=Join-Path $PSScriptRoot 'arcade_portrait_perf_20261031/input_arcade.ps1'
if((Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToLowerInvariant() -ne '59709044702b5de6ff740ee563efccfb9afca465b225fd73b399ad5d8b17d0e1'){throw 'frozen_native_input_helper_changed'}
$source=[IO.File]::ReadAllText($tool)
$needle="){throw 'text_not_allowlisted'}"
if(([regex]::Matches($source,[regex]::Escape($needle))).Count -ne 1){throw 'input_allowlist_anchor_changed'}
$replacement=" -and `$Text -cnotmatch '$allowed'){throw 'text_not_allowlisted'}"
$safeSource=$source.Replace($needle,$replacement)
$runner=[ScriptBlock]::Create($safeSource)
& $runner -GameProcessId $GameProcessId -CreatedUtc $CreatedUtc -Action Text -Text $Command -TextMode AsciiKeys
& $tool -GameProcessId $GameProcessId -CreatedUtc $CreatedUtc -Action Key -Key Enter
