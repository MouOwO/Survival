param(
    [Parameter(Mandatory=$true)][string]$PatchedMap,
    [Parameter(Mandatory=$true)][string]$BaselineText,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$sourceMap = Join-Path $engine 'content/dota_addons/survival/maps/template_map.vmap'
$vpk = Join-Path $repo 'maps/template_map.vpk'
$bin = Join-Path $engine 'game/bin/win64'
$patched = (Resolve-Path -LiteralPath $PatchedMap).Path
$baseline = (Resolve-Path -LiteralPath $BaselineText).Path
$out = [IO.Path]::GetFullPath((Join-Path $repo $OutputDirectory))
if (-not $out.StartsWith(($repo + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must stay in the project.' }
New-Item -ItemType Directory -Force -Path $out | Out-Null
$backup = Join-Path $out ('install_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $backup | Out-Null
try { $handle = [IO.File]::Open($vpk, 'Open', 'ReadWrite', 'None'); $handle.Dispose() }
catch { throw 'Map package is in use; disconnect its Tools test session before compiling.' }
$originalHash = (Get-FileHash -LiteralPath $sourceMap -Algorithm SHA256).Hash
Copy-Item -LiteralPath $sourceMap -Destination (Join-Path $backup 'template_map.before.vmap')
Copy-Item -LiteralPath $vpk -Destination (Join-Path $backup 'template_map.before.vpk')
& (Join-Path $bin 'dmxconvert.exe') -i $sourceMap -o (Join-Path $backup 'current_text.vmap') -oe keyvalues2
if ($LASTEXITCODE -ne 0) { throw 'Current Hammer snapshot conversion failed.' }
& node (Join-Path $PSScriptRoot 'same-snapshot.cjs') (Join-Path $backup 'current_text.vmap') $baseline
if ($LASTEXITCODE -ne 0) {
    throw 'Hammer changed since the baseline was captured. Rebase the patch onto the latest saved map.'
}
& (Join-Path $bin 'dmxconvert.exe') -i $patched -o (Join-Path $backup 'template_map.patched.vmap') -oe binary
if ($LASTEXITCODE -ne 0) { throw 'Patched DMX conversion failed.' }
if ((Get-FileHash -LiteralPath $sourceMap).Hash -ne $originalHash) { throw 'Hammer source changed during preparation.' }
Copy-Item -LiteralPath (Join-Path $backup 'template_map.patched.vmap') -Destination $sourceMap
$installedHash = (Get-FileHash -LiteralPath $sourceMap).Hash
$started = Get-Date
$argsForCompiler = @('-i', ('"{0}"' -f $sourceMap), '-game', ('"{0}"' -f (Join-Path $engine 'game/dota')), '-fshallow', '-nop4')
$compiler = Start-Process -FilePath (Join-Path $bin 'resourcecompiler.exe') -ArgumentList $argsForCompiler -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $backup 'compile.log') -RedirectStandardError (Join-Path $backup 'compile.stderr.log')
if ($compiler.ExitCode -ne 0) { throw ('Map compilation failed; see ' + $backup) }
$packed = Get-Item -LiteralPath $vpk
if ($packed.Length -eq 0 -or $packed.LastWriteTime -lt $started) { throw 'Compiled map package was not updated.' }
if ((Get-FileHash -LiteralPath $sourceMap).Hash -ne $installedHash) { throw 'Hammer source changed during compilation; rebuild its latest version.' }
& node (Join-Path $repo 'tools/map_c6/verify-map-package.cjs') --source $sourceMap --vpk $vpk --report (Join-Path $backup 'package_verification.json')
if ($LASTEXITCODE -ne 0) { throw 'Compiled package verification failed.' }
$report = @{source=$sourceMap;source_before_sha256=$originalHash;source_after_sha256=$installedHash;package_sha256=(Get-FileHash -LiteralPath $vpk).Hash;backup=$backup;compiled=$true}
[IO.File]::WriteAllText((Join-Path $out 'installed.json'), ($report | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
Get-Content -LiteralPath (Join-Path $backup 'compile.log') -Tail 8
