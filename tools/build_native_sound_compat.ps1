$ErrorActionPreference = 'Stop'
$compatRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$compatEngine = (Resolve-Path (Join-Path $compatRepo '../../..')).Path
$compatRelative = 'soundevents/survival_native_compat.vsndevts'
$compatSource = Join-Path $compatRepo ('art/audio/source/' + $compatRelative)
$compatContent = Join-Path $compatEngine ('content/dota_addons/survival/' + $compatRelative)
$compatArtifact = Join-Path $compatRepo ($compatRelative + '_c')
$compatOut = Join-Path $compatRepo ('output/late_combat_20261008/sound_build_' + (Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Force -Path $compatOut, (Split-Path $compatContent) | Out-Null
$compatContentExisted = Test-Path -LiteralPath $compatContent
$compatArtifactExisted = Test-Path -LiteralPath $compatArtifact
if ($compatContentExisted) { Copy-Item -LiteralPath $compatContent -Destination (Join-Path $compatOut 'content.before.vsndevts') }
if ($compatArtifactExisted) { Copy-Item -LiteralPath $compatArtifact -Destination (Join-Path $compatOut 'game.before.vsndevts_c') }
try {
    Copy-Item -LiteralPath $compatSource -Destination $compatContent -Force
    $compatLog = @(& (Join-Path $compatEngine 'game/bin/win64/resourcecompiler.exe') -i $compatContent -game (Join-Path $compatEngine 'game/dota') -f -nop4 2>&1)
    $compatCode = $LASTEXITCODE
    $compatLog | Set-Content (Join-Path $compatOut 'compile.log')
    if ($compatCode -ne 0 -or -not ($compatLog -match '0 failed') -or -not (Test-Path -LiteralPath $compatArtifact)) { throw 'Native sound compatibility compilation failed' }
    $compatDump = @(& (Join-Path $compatEngine 'game/bin/win64/resourceinfo.exe') -i $compatArtifact -all 2>&1)
    $compatInfoCode = $LASTEXITCODE
    $compatDump | Set-Content (Join-Path $compatOut 'resource.dump.txt')
    if ($compatInfoCode -ne 0 -or -not ($compatDump -match 'Hero_Axe.Footsteps.Automaton') -or -not ($compatDump -match 'dota_null_start')) { throw 'Compiled compatibility event is missing' }
    if ((Get-FileHash -LiteralPath $compatSource).Hash -ne (Get-FileHash -LiteralPath $compatContent).Hash) { throw 'Content/source hash mismatch' }
    Write-Output "NATIVE_SOUND_COMPAT_PASS checkpoint=$compatOut"
} catch {
    if ($compatContentExisted) { Copy-Item -LiteralPath (Join-Path $compatOut 'content.before.vsndevts') -Destination $compatContent -Force }
    else { Remove-Item -LiteralPath $compatContent -ErrorAction SilentlyContinue }
    if ($compatArtifactExisted) { Copy-Item -LiteralPath (Join-Path $compatOut 'game.before.vsndevts_c') -Destination $compatArtifact -Force }
    else { Remove-Item -LiteralPath $compatArtifact -ErrorAction SilentlyContinue }
    throw
}
