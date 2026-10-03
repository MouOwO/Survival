$ErrorActionPreference = 'Stop'
$meteorRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$meteorEngine = (Resolve-Path (Join-Path $meteorRepo '../../..')).Path
$meteorContent = Join-Path $meteorEngine 'content/dota_addons/survival'
$meteorLogs = Join-Path $meteorRepo 'output/phoenix_meteor/compile'
New-Item -ItemType Directory -Force -Path $meteorLogs | Out-Null
foreach ($name in @('meteor_phoenix_fall', 'meteor_impact')) {
    $relative = 'particles/survival/skills/' + $name + '.vpcf'
    $destination = Join-Path $meteorContent $relative
    $backup = Join-Path $meteorLogs ('before/' + $name + '.vpcf')
    if ((Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $backup)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $meteorRepo ('art/effects/skill_visuals/source/' + $relative)) -Destination $destination -Force
    $log = @(& (Join-Path $meteorEngine 'game/bin/win64/resourcecompiler.exe') -i $destination -game (Join-Path $meteorEngine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $meteorLogs ($name + '.log'))
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Phoenix meteor compile failed: $name" }
}
