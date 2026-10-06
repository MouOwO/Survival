$ErrorActionPreference = 'Stop'
$blizzardRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$blizzardEngine = (Resolve-Path (Join-Path $blizzardRepo '../../..')).Path
foreach ($blizzardName in @('wyvern_blizzard_snow', 'blizzard_ground', 'blizzard_wind')) {
$blizzardRelative = 'particles/survival/skills/' + $blizzardName + '.vpcf'
$blizzardDestination = Join-Path $blizzardEngine ('content/dota_addons/survival/' + $blizzardRelative)
New-Item -ItemType Directory -Force -Path (Split-Path $blizzardDestination) | Out-Null
Copy-Item -LiteralPath (Join-Path $blizzardRepo ('art/effects/skill_visuals/source/' + $blizzardRelative)) -Destination $blizzardDestination -Force
$blizzardLog = @(& (Join-Path $blizzardEngine 'game/bin/win64/resourcecompiler.exe') -i $blizzardDestination -game (Join-Path $blizzardEngine 'game/dota') -f -nop4 2>&1)
$blizzardLog | Set-Content (Join-Path $blizzardRepo ('output/wyvern_blizzard/compile_' + $blizzardName + '.log'))
$blizzardLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
if ($LASTEXITCODE -ne 0 -or -not ($blizzardLog -match '0 failed')) { throw 'Blizzard snow compile failed' }

}
