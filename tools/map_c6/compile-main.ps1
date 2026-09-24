param([string]$SourceMap)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$out = Join-Path $repo 'output/map_main_merge_20260919'
$contentMap = Join-Path $engine 'content/dota_addons/survival/maps/template_map.vmap'
$bin = Join-Path $engine 'game/bin/win64'
$vpk = Join-Path $repo 'maps/template_map.vpk'
$node = (Get-Command node.exe -ErrorAction Stop).Source
New-Item -ItemType Directory -Force -Path $out | Out-Null
if (Test-Path -LiteralPath $vpk) {
    try { $probe = [IO.File]::Open($vpk, 'Open', 'ReadWrite', 'None'); $probe.Dispose() }
    catch { throw 'template_map.vpk is in use. Disconnect its test session before compiling.' }
}
# A normal rebuild compiles the current Hammer source. Importing a snapshot is
# explicit, so later manual edits cannot be silently replaced by the generator.
if ($SourceMap) {
    $inputMap = (Resolve-Path -LiteralPath $SourceMap).Path
    $backup = Join-Path $out ('before_compile_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $backup | Out-Null
    Copy-Item -LiteralPath $contentMap -Destination $backup
    Copy-Item -LiteralPath $vpk -Destination $backup
    & (Join-Path $bin 'dmxconvert.exe') -i $inputMap -o (Join-Path $out 'template_merged_binary.vmap') -oe binary
    if ($LASTEXITCODE -ne 0) { throw 'Main map DMX conversion failed.' }
    Copy-Item -LiteralPath (Join-Path $out 'template_merged_binary.vmap') -Destination $contentMap
}
$sourceHash = (Get-FileHash -LiteralPath $contentMap -Algorithm SHA256).Hash
$compileStarted = Get-Date
$compilerArgs = @('-i', ('"{0}"' -f $contentMap), '-game', ('"{0}"' -f (Join-Path $engine 'game/dota')), '-fshallow', '-nop4')
$process = Start-Process -FilePath (Join-Path $bin 'resourcecompiler.exe') -ArgumentList $compilerArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $out 'compile.log') -RedirectStandardError (Join-Path $out 'compile.stderr.log')
if ($process.ExitCode -ne 0) { throw 'Main map compilation failed; see output/map_main_merge_20260919/compile.log.' }
$log = Get-Content -LiteralPath (Join-Path $out 'compile.log') -Raw
if ($log -match '(?im)^Write .+\.vpk Failed!') { throw 'Main map VPK write failed.' }
$packed = Get-Item -LiteralPath $vpk
if ($packed.Length -eq 0 -or $packed.LastWriteTime -lt $compileStarted) { throw 'Main map VPK was not updated.' }
if ((Get-FileHash -LiteralPath $contentMap -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Hammer source changed during compilation. Save the map and rebuild again.'
}
& $node (Join-Path $PSScriptRoot 'verify-map-package.cjs') --source $contentMap --vpk $vpk --report (Join-Path $out 'package_verification.json')
if ($LASTEXITCODE -ne 0) { throw 'Compiled map does not match its source or contains a corrupt resource; see package_verification.json.' }
Get-Content -LiteralPath (Join-Path $out 'compile.log') -Tail 8
