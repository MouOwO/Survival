$ErrorActionPreference = 'Stop'
$snowballRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$snowballEngine = (Resolve-Path (Join-Path $snowballRepo '../../..')).Path
$snowballResource = 'particles/survival/skills/tusk_snowball_fixed_size.vpcf'
$snowballSource = Join-Path $snowballRepo ('art/effects/tusk_snowball_fixed_size/source/' + $snowballResource)
$snowballDestination = Join-Path $snowballEngine ('content/dota_addons/survival/' + $snowballResource)
$snowballOutput = Join-Path $snowballRepo 'output/tusk_snowball_fixed_size'
New-Item -ItemType Directory -Force -Path $snowballOutput | Out-Null
& node (Join-Path $PSScriptRoot 'map_c6/build-tusk-snowball-fixed-size.cjs') --check
if ($LASTEXITCODE -ne 0) { throw 'Fixed-size snowball source verification failed' }
if (Test-Path -LiteralPath $snowballDestination) {
    $snowballBackup = Join-Path $snowballOutput ('content_backup/' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '/' + $snowballResource)
    New-Item -ItemType Directory -Force -Path (Split-Path $snowballBackup) | Out-Null
    Copy-Item -LiteralPath $snowballDestination -Destination $snowballBackup
}
New-Item -ItemType Directory -Force -Path (Split-Path $snowballDestination) | Out-Null
Copy-Item -LiteralPath $snowballSource -Destination $snowballDestination -Force
$snowballLog = @(& (Join-Path $snowballEngine 'game/bin/win64/resourcecompiler.exe') -i $snowballDestination -game (Join-Path $snowballEngine 'game/dota') -fshallow -nop4 2>&1)
$snowballExitCode = $LASTEXITCODE
$snowballLog | Set-Content -LiteralPath (Join-Path $snowballOutput 'compile.log')
$snowballLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
if ($snowballExitCode -ne 0 -or -not ($snowballLog -match '0 failed')) { throw 'Fixed-size snowball compile failed' }
if (-not (Test-Path -LiteralPath (Join-Path $snowballRepo ($snowballResource + '_c')))) { throw 'Compiled fixed-size snowball is missing' }
& node (Join-Path $PSScriptRoot 'map_c6/build-tusk-snowball-fixed-size.cjs') --check-compiled
if ($LASTEXITCODE -ne 0) { throw 'Compiled snowball differs from the fixed-size native variant' }
Write-Output 'TUSK_SNOWBALL_FIXED_SIZE_COMPILE_PASS'
