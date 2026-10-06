$ErrorActionPreference = 'Stop'
$audioRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$audioEngine = (Resolve-Path (Join-Path $audioRepo '../../..')).Path
$audioRelative = 'soundevents/survival_tower_feedback.vsndevts'
$audioDestination = Join-Path $audioEngine ('content/dota_addons/survival/' + $audioRelative)
$audioOutput = Join-Path $audioRepo 'output/machine_gun_feedback'
New-Item -ItemType Directory -Force -Path (Split-Path $audioDestination), $audioOutput | Out-Null
Copy-Item -LiteralPath (Join-Path $audioRepo ('art/audio/source/' + $audioRelative)) -Destination $audioDestination -Force
$audioLog = @(& (Join-Path $audioEngine 'game/bin/win64/resourcecompiler.exe') -i $audioDestination -game (Join-Path $audioEngine 'game/dota') -f -nop4 2>&1)
$audioCode = $LASTEXITCODE
$audioLog | Set-Content (Join-Path $audioOutput 'compile_sound.log')
$audioLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
if ($audioCode -ne 0 -or -not ($audioLog -match '0 failed')) { throw 'Tower audio compile failed' }
if (-not (Test-Path -LiteralPath (Join-Path $audioRepo ($audioRelative + '_c')))) { throw 'Compiled tower audio is missing' }
