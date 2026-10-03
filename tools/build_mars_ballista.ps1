$ErrorActionPreference = 'Stop'
$ballistaRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ballistaEngine = (Resolve-Path (Join-Path $ballistaRepo '../../..')).Path
$ballistaRelative = 'particles/survival/towers/mars_crimson_ballista.vpcf'
$ballistaDestination = Join-Path $ballistaEngine ('content/dota_addons/survival/' + $ballistaRelative)
New-Item -ItemType Directory -Force -Path (Split-Path $ballistaDestination) | Out-Null
Copy-Item -LiteralPath (Join-Path $ballistaRepo ('art/effects/ballista/source/' + $ballistaRelative)) -Destination $ballistaDestination -Force
$ballistaLog = @(& (Join-Path $ballistaEngine 'game/bin/win64/resourcecompiler.exe') -i $ballistaDestination -game (Join-Path $ballistaEngine 'game/dota') -f -nop4 2>&1)
$ballistaLog | Set-Content (Join-Path $ballistaRepo 'output/mars_ballista/compile.log')
$ballistaLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
if ($LASTEXITCODE -ne 0 -or -not ($ballistaLog -match '0 failed')) { throw 'Mars ballista compile failed' }
