[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [string]$SourceRoot = 'panorama/src',
    [string]$Report = 'output/daily_native_icons_20261017/compile.json'
)
$ErrorActionPreference = 'Stop'
$dailyNativeRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$dailyNativeEngine = [IO.Path]::GetFullPath((Join-Path $dailyNativeRepo '../../..'))
$dailyNativeContent = Join-Path $dailyNativeEngine 'content/dota_addons/Survival/panorama'
$dailyNativeRuntime = Join-Path $dailyNativeRepo 'panorama'
$dailyNativeCompiler = Join-Path $dailyNativeEngine 'game/bin/win64/resourcecompiler.exe'
$dailyNativeSourceRoot = [IO.Path]::GetFullPath((Join-Path $dailyNativeRepo $SourceRoot))
$dailyNativeReport = [IO.Path]::GetFullPath((Join-Path $dailyNativeRepo $Report))
$dailyNativeBackup = Join-Path $dailyNativeRepo ('output/daily_native_icons_20261017/compile_' + (Get-Date -Format yyyyMMdd_HHmmss_fff) + '_' + [guid]::NewGuid().ToString('N').Substring(0,8))
$dailyNativeFiles = @(
    'scripts/custom_game/common/item_resources.js',
    'scripts/custom_game/archive_v10_icons.js',
    'styles/custom_game/daily_gw2.css'
)
$dailyNativeRecords = @()
$dailyNativeSuccess = $false
$dailyNativeFailure = $null
$dailyNativeRestoreErrors = @()

function Assert-DailyNativePath([string]$Path, [string]$Root) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the intended directory: $resolved"
    }
}

function Get-DailyNativeHash([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    return $null
}

function Assert-DailyNativeHash([string]$Path, $Expected, [string]$Stage) {
    if ((Get-DailyNativeHash $Path) -ne $Expected) {
        throw "File changed during ${Stage}: $Path; snapshots remain in $dailyNativeBackup"
    }
}

function Save-DailyNativeReport {
    $value = @{
        at = (Get-Date -Format o); success = $dailyNativeSuccess; failure = $dailyNativeFailure
        sourceRoot = $dailyNativeSourceRoot; backup = $dailyNativeBackup
        restoreErrors = @($dailyNativeRestoreErrors); records = @($dailyNativeRecords)
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dailyNativeReport) | Out-Null
    $value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $dailyNativeReport -Encoding utf8
    $value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dailyNativeBackup 'report.json') -Encoding utf8
}

Assert-DailyNativePath $dailyNativeSourceRoot $dailyNativeRepo
Assert-DailyNativePath $dailyNativeReport $dailyNativeRepo
if (-not (Test-Path -LiteralPath $dailyNativeCompiler -PathType Leaf)) { throw 'Dota2 resource compiler is missing.' }
foreach ($relative in $dailyNativeFiles) {
    $source = Join-Path $dailyNativeSourceRoot $relative
    $content = Join-Path $dailyNativeContent $relative
    $runtimeRelative = $relative -replace '\.js$', '.vjs_c' -replace '\.css$', '.vcss_c'
    $artifact = Join-Path $dailyNativeRuntime $runtimeRelative
    Assert-DailyNativePath $source $dailyNativeSourceRoot
    Assert-DailyNativePath $content $dailyNativeContent
    Assert-DailyNativePath $artifact $dailyNativeRuntime
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $relative" }
    $dailyNativeRecords += [pscustomobject]@{
        relative = $relative; runtimeRelative = $runtimeRelative
        source = $source; content = $content; artifact = $artifact
        sourceHash = Get-DailyNativeHash $source
        contentBeforeHash = Get-DailyNativeHash $content; runtimeBeforeHash = Get-DailyNativeHash $artifact
        sourceBackup = Join-Path $dailyNativeBackup ('source/' + $relative)
        contentBackup = Join-Path $dailyNativeBackup ('content/' + $relative)
        runtimeBackup = Join-Path $dailyNativeBackup ('runtime/' + $runtimeRelative)
        compiledBackup = Join-Path $dailyNativeBackup ('compiled/' + $runtimeRelative)
        compilerLog = Join-Path $dailyNativeBackup (([IO.Path]::GetFileName($source)) + '.log')
        contentWritten = $false; runtimeAttempted = $false
        contentOwnedHash = $null; runtimeOwnedHash = $null; compiledHash = $null
        contentRestored = $false; runtimeRestored = $false
    }
}
if ($CheckOnly) { Write-Output 'DAILY_NATIVE_ICONS_PANORAMA_CHECK_PASS 3 sources'; return }

try {
    foreach ($record in $dailyNativeRecords) {
        foreach ($target in @($record.sourceBackup, $record.contentBackup, $record.runtimeBackup, $record.compiledBackup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        }
        Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
        Assert-DailyNativeHash $record.sourceBackup $record.sourceHash 'source snapshot'
        Assert-DailyNativeHash $record.source $record.sourceHash 'source snapshot'
        if ($record.contentBeforeHash) { Copy-Item -LiteralPath $record.content -Destination $record.contentBackup }
        if ($record.runtimeBeforeHash) { Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup }
        Assert-DailyNativeHash $record.content $record.contentBeforeHash 'Content snapshot'
        Assert-DailyNativeHash $record.artifact $record.runtimeBeforeHash 'runtime snapshot'
        if ($record.contentBeforeHash) { Assert-DailyNativeHash $record.contentBackup $record.contentBeforeHash 'Content backup' }
        if ($record.runtimeBeforeHash) { Assert-DailyNativeHash $record.runtimeBackup $record.runtimeBeforeHash 'runtime backup' }
    }
    Save-DailyNativeReport
    foreach ($record in $dailyNativeRecords) {
        Assert-DailyNativeHash $record.source $record.sourceHash 'before compilation'
        Assert-DailyNativeHash $record.content $record.contentBeforeHash 'before Content write'
        Assert-DailyNativeHash $record.artifact $record.runtimeBeforeHash 'before compilation'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $record.content) | Out-Null
        Copy-Item -LiteralPath $record.sourceBackup -Destination $record.content -Force
        $record.contentWritten = $true; $record.contentOwnedHash = $record.sourceHash
        $started = (Get-Date).ToUniversalTime()
        $record.runtimeAttempted = $true
        $log = @(& $dailyNativeCompiler -i $record.content -game (Join-Path $dailyNativeEngine 'game/dota') -fshallow -nop4 2>&1)
        $compilerExit = $LASTEXITCODE
        $record.runtimeOwnedHash = Get-DailyNativeHash $record.artifact
        $log | Set-Content -LiteralPath $record.compilerLog -Encoding utf8
        Save-DailyNativeReport
        if ($compilerExit -ne 0 -or -not ($log -match 'OK: [1-9][0-9]* compiled, 0 failed,')) {
            throw "Compile failed: $($record.relative); see $($record.compilerLog)"
        }
        if (-not (Test-Path -LiteralPath $record.artifact -PathType Leaf)) { throw "Missing output: $($record.runtimeRelative)" }
        $built = Get-Item -LiteralPath $record.artifact
        if ($built.Length -le 0 -or $built.LastWriteTimeUtc -lt $started) { throw "Empty or stale output: $($record.runtimeRelative)" }
        Assert-DailyNativeHash $record.source $record.sourceHash 'after compilation'
        Assert-DailyNativeHash $record.content $record.sourceHash 'after compilation'
        $record.compiledHash = $record.runtimeOwnedHash
        Copy-Item -LiteralPath $record.artifact -Destination $record.compiledBackup
        Assert-DailyNativeHash $record.compiledBackup $record.compiledHash 'compiled snapshot'
        Write-Output ('DAILY_NATIVE_ICONS_PANORAMA_COMPILED ' + $record.relative)
    }
    foreach ($record in $dailyNativeRecords) {
        Assert-DailyNativeHash $record.source $record.sourceHash 'final source verification'
        Assert-DailyNativeHash $record.content $record.sourceHash 'final Content verification'
        Assert-DailyNativeHash $record.artifact $record.compiledHash 'final runtime verification'
    }
    $dailyNativeSuccess = $true
} catch {
    $dailyNativeFailure = $_.Exception.Message
} finally {
    if (-not $dailyNativeSuccess) {
        foreach ($record in $dailyNativeRecords) {
            foreach ($kind in @('content', 'runtime')) {
                $attempted = if ($kind -eq 'content') { $record.contentWritten } else { $record.runtimeAttempted }
                if (-not $attempted) { continue }
                try {
                    $target = if ($kind -eq 'content') { $record.content } else { $record.artifact }
                    $root = if ($kind -eq 'content') { $dailyNativeContent } else { $dailyNativeRuntime }
                    Assert-DailyNativePath $target $root
                    $ownedHash = $record.($kind + 'OwnedHash')
                    Assert-DailyNativeHash $target $ownedHash "before $kind recovery"
                    $beforeHash = $record.($kind + 'BeforeHash')
                    if ($beforeHash) {
                        $saved = $record.($kind + 'Backup')
                        Assert-DailyNativeHash $saved $beforeHash "$kind backup verification"
                        Copy-Item -LiteralPath $saved -Destination $target -Force
                    } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
                        Remove-Item -LiteralPath $target -Force
                    }
                    Assert-DailyNativeHash $target $beforeHash "after $kind recovery"
                    $record.($kind + 'Restored') = $true
                } catch { $dailyNativeRestoreErrors += $_.Exception.Message }
            }
        }
    }
    New-Item -ItemType Directory -Force -Path $dailyNativeBackup | Out-Null
    Save-DailyNativeReport
}
if ($dailyNativeRestoreErrors.Count) { throw ($dailyNativeRestoreErrors -join [Environment]::NewLine) }
if ($dailyNativeFailure) { throw $dailyNativeFailure }
Write-Output ('DAILY_NATIVE_ICONS_PANORAMA_PASS report=' + $dailyNativeReport)
