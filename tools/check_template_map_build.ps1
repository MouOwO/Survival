$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $repo '..\..\..\content\dota_addons\survival\maps\template_map.vmap'
$compiled = Join-Path $repo 'maps\template_map.vpk'

$sourceFile = Get-Item -LiteralPath $source -ErrorAction SilentlyContinue
$compiledFile = Get-Item -LiteralPath $compiled -ErrorAction SilentlyContinue
$packageLocked = $false
if ($compiledFile) {
    try {
        $handle = [IO.File]::Open($compiledFile.FullName, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::None)
        $handle.Close()
    } catch [IO.IOException] {
        $packageLocked = $_.Exception.HResult -eq -2147024864 # 0x80070020: sharing violation
    }
}
$before = @(Get-Process -Name resourcecompiler -ErrorAction SilentlyContinue |
    Select-Object Id, CPU, PrivateMemorySize64, StartTime)
if ($before.Count -gt 0) { Start-Sleep -Seconds 3 }
$after = @(Get-Process -Name resourcecompiler -ErrorAction SilentlyContinue |
    Select-Object Id, CPU, PrivateMemorySize64, StartTime)

$running = foreach ($process in $after) {
    $previous = $before | Where-Object Id -eq $process.Id | Select-Object -First 1
    [pscustomobject]@{
        Pid = $process.Id
        ElapsedMinutes = [math]::Round(((Get-Date) - $process.StartTime).TotalMinutes, 1)
        CpuSecondsIn3s = if ($previous) { [math]::Round($process.CPU - $previous.CPU, 2) } else { $null }
        PrivateMemoryGiB = [math]::Round($process.PrivateMemorySize64 / 1GB, 2)
    }
}

$state = if ($running) { 'BUILD_RUNNING' }
elseif (-not $compiledFile) { 'NO_COMPILED_MAP' }
elseif (-not $sourceFile) { 'NO_SOURCE_MAP' }
elseif ($compiledFile.LastWriteTime -lt $sourceFile.LastWriteTime -and $packageLocked) { 'BUILD_FAILED_PACKAGE_LOCKED' }
elseif ($compiledFile.LastWriteTime -lt $sourceFile.LastWriteTime) { 'BUILD_MISSING_OR_FAILED' }
else { 'COMPILED_MAP_UPDATED' }

[pscustomobject]@{
    State = $state
    SourceSavedAt = if ($sourceFile) { $sourceFile.LastWriteTime } else { $null }
    PackageUpdatedAt = if ($compiledFile) { $compiledFile.LastWriteTime } else { $null }
    PackageMiB = if ($compiledFile) { [math]::Round($compiledFile.Length / 1MB, 1) } else { $null }
    PackageLocked = $packageLocked
    Compiler = @($running)
} | ConvertTo-Json -Depth 4
