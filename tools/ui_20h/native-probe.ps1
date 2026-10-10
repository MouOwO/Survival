param([ValidateSet('install','restore')][string]$Action='install')
$ErrorActionPreference='Stop'
$uiRepo=(Get-Location).Path
$uiEngine=[IO.Path]::GetFullPath((Join-Path $uiRepo '../../..'))
$uiContent=Join-Path $uiEngine 'content/dota_addons/Survival/panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.js'
$uiRuntime=Join-Path $uiRepo 'panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.vjs_c'
$uiBackup=Join-Path $uiRepo 'output/ui_20h/native_probe'
if($Action -eq 'restore') {Copy-Item -LiteralPath (Join-Path $uiBackup 'source.js') -Destination $uiContent -Force; Copy-Item -LiteralPath (Join-Path $uiBackup 'runtime.vjs_c') -Destination $uiRuntime -Force; Write-Output 'UI20_PROBE_RESTORED'; return}
New-Item -ItemType Directory -Path $uiBackup -Force|Out-Null
Copy-Item -LiteralPath $uiContent -Destination (Join-Path $uiBackup 'source.js') -Force
Copy-Item -LiteralPath $uiRuntime -Destination (Join-Path $uiBackup 'runtime.vjs_c') -Force
$uiCommand='ui20_probe_'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$uiCode=[IO.File]::ReadAllText((Join-Path $uiRepo 'tools/ui_20h/native-probe.js')).Replace('COMMAND',$uiCommand)
[IO.File]::WriteAllText($uiContent,([IO.File]::ReadAllText($uiContent)+"`r`n"+$uiCode),[Text.UTF8Encoding]::new($false))
& (Join-Path $uiEngine 'game/bin/win64/resourcecompiler.exe') -i $uiContent -fshallow -nop4 *> (Join-Path $uiBackup 'compile.log')
if($LASTEXITCODE -ne 0){throw 'Native probe compile failed'}
@{command=$uiCommand}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $uiBackup 'command.json') -Encoding UTF8
Write-Output $uiCommand
