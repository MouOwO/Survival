param([switch]$Incremental)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine = (Resolve-Path (Join-Path $repo '..\..\..')).Path
$source = Join-Path $engine 'content\dota_addons\survival\maps\template_map.vmap'
$package = Join-Path $repo 'maps\template_map.vpk'
$compiler = Join-Path $engine 'game\bin\win64\resourcecompiler.exe'
$game = Join-Path $engine 'game\dota'
$logDirectory = Join-Path $repo 'output\map_builds'

foreach ($item in @($source, $compiler)) {
    if (-not (Test-Path -LiteralPath $item -PathType Leaf)) { throw "BUILD_INPUT_MISSING: $item" }
}
if (Get-Process -Name resourcecompiler -ErrorAction SilentlyContinue) {
    throw 'BUILD_ALREADY_RUNNING: wait for the current resourcecompiler process to finish.'
}
if (Test-Path -LiteralPath $package -PathType Leaf) {
    try {
        $handle = [IO.File]::Open($package, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::None)
        $handle.Close()
    } catch [IO.IOException] {
        if ($_.Exception.HResult -eq -2147024864) {
            throw 'MAP_PACKAGE_IN_USE: disconnect from the current Dota match before building; then retry.'
        }
        throw
    }
}

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$log = Join-Path $logDirectory ('template_map_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$started = Get-Date
$arguments = @('-i', $source, '-game', $game, '-nop4')
if (-not $Incremental) { $arguments += '-f' }
& $compiler @arguments *> $log
$exitCode = $LASTEXITCODE
$packageFile = Get-Item -LiteralPath $package -ErrorAction SilentlyContinue
$sourceFile = Get-Item -LiteralPath $source
$logText = Get-Content -LiteralPath $log -Raw
$packageWritten = ($packageFile -and $packageFile.LastWriteTime -ge $started -and
    $packageFile.LastWriteTime -ge $sourceFile.LastWriteTime)
$failed = ($exitCode -ne 0 -or -not $packageWritten -or
    $logText.Contains('Write ' + $package + ' Failed!') -or
    -not $logText.Contains('--> Map build finished.'))
$result = [pscustomobject]@{
    Status = if ($failed) { 'BUILD_FAILED' } else { 'BUILD_OK' }
    CompilerExitCode = $exitCode
    PackageWritten = [bool]$packageWritten
    PackageUpdatedAt = if ($packageFile) { $packageFile.LastWriteTime } else { $null }
    SourceSavedAt = $sourceFile.LastWriteTime
    GrassErrors = ([regex]::Matches($logText, 'grass_exclusion_radius')).Count
    SuppressedEntities = ([regex]::Matches($logText, 'Suppressing entity')).Count
    Log = $log
}
$result | ConvertTo-Json -Depth 3
if ($failed) { exit 1 }
