param([switch]$Generate,[string]$SourceMap)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$out = Join-Path $repo 'output/map_build_c6'
$contentMap = Join-Path $engine 'content/dota_addons/survival/maps/survival_c6.vmap'
$bin = Join-Path $engine 'game/bin/win64'
$vpk = Join-Path $repo 'maps/survival_c6.vpk'
New-Item -ItemType Directory -Force -Path $out | Out-Null
if ($Generate -and $SourceMap) { throw 'Choose -Generate or -SourceMap, not both.' }
if (Test-Path -LiteralPath $vpk) {
    try { $probe = [IO.File]::Open($vpk, 'Open', 'ReadWrite', 'None'); $probe.Dispose() }
    catch { throw 'survival_c6.vpk is in use. Close the Workshop test instance before compiling.' }
}
if ($Generate) {
    & node --max-old-space-size=4096 (Join-Path $PSScriptRoot 'build.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'C6 source generation failed' }
}
$inputMap = if ($SourceMap) { (Resolve-Path -LiteralPath $SourceMap).Path } elseif ($Generate) { Join-Path $out 'survival_c6.vmap' } else { $contentMap }
& (Join-Path $bin 'dmxconvert.exe') -i $inputMap -o (Join-Path $out 'survival_c6_binary.vmap') -oe binary
if ($LASTEXITCODE -ne 0) { throw 'C6 DMX conversion failed' }
Copy-Item -LiteralPath (Join-Path $out 'survival_c6_binary.vmap') -Destination $contentMap
$compileStarted = Get-Date
& (Join-Path $bin 'resourcecompiler.exe') -i $contentMap -game (Join-Path $engine 'game/dota') -fshallow -nop4 *> (Join-Path $out 'compile.log')
if ($LASTEXITCODE -ne 0) { throw 'C6 compile failed; see output/map_build_c6/compile.log' }
$log = Get-Content -LiteralPath (Join-Path $out 'compile.log') -Raw
if ($log -match '(?im)^Write .+\.vpk Failed!') { throw 'Resource compilation completed, but VPK write failed. Close the test game and rebuild.' }
if (-not (Test-Path -LiteralPath $vpk)) { throw 'Compiler produced no map VPK.' }
$packed = Get-Item -LiteralPath $vpk
if ($packed.Length -eq 0 -or $packed.LastWriteTime -lt $compileStarted) { throw 'Map VPK was not updated by this compile.' }
Get-Content (Join-Path $out 'compile.log') -Tail 6
