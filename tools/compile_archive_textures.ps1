param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine = [IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content = Join-Path $engine 'content/dota_addons/survival/panorama/images/custom_game'
$masters = Join-Path $repo 'art/ui/sources/custom_game'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$work = Join-Path $repo 'output/archive_texture_fix'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$inputs = @()
foreach ($group in @('archive_gpu_regular', 'archive_gpu_small')) {
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $masters $group) -Filter '*.vtex' -File)
    if (-not $sources.Count) { throw "No texture recipes found: $group" }
    foreach ($source in $sources) {
        $inputFile = Join-Path (Join-Path $content $group) $source.Name
        if (-not (Test-Path -LiteralPath $inputFile) -or
            (Get-FileHash -LiteralPath $source.FullName).Hash -ne (Get-FileHash -LiteralPath $inputFile).Hash) {
            throw "Content recipe differs from artist source: $group/$($source.Name). Sync content images before compiling."
        }
        $inputs += $inputFile
    }
}
$fileList = Join-Path $work 'inputs.txt'
[IO.File]::WriteAllLines($fileList, $inputs, [Text.UTF8Encoding]::new($false))
$compilerArgs = @('-filelist', $fileList, '-game', (Join-Path $engine 'game/dota'), '-nop4')
if (-not $CheckOnly) {
    $buildLog = Join-Path $work 'compile.log'
    & $compiler @compilerArgs *> $buildLog
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $buildLog -Pattern 'OK: \d+ compiled, 0 failed,' -Quiet)) {
        throw "Texture compilation failed. See $buildLog"
    }
}
# Check-only can return success even when it skips an OUTDATED resource.
# Count the explicit valid-dependency marker, not the process exit code alone.
$checkLog = Join-Path $work 'check.log'
& $compiler @compilerArgs -dependency_check_only *> $checkLog
$valid = @(Select-String -LiteralPath $checkLog -Pattern '^All inputs have identical CRCs, skipping').Count
if ($LASTEXITCODE -ne 0 -or $valid -ne $inputs.Count) {
    throw "Only $valid/$($inputs.Count) textures are up to date. See $checkLog"
}
Write-Output "ARCHIVE_TEXTURES_READY: $valid textures passed compiler dependency checks."
