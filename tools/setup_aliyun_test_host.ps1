param(
    [ValidateSet('Setup','Check','OnlineCheck','Credential')][string]$Action = 'Setup',
    [string]$PythonExe,
    [string]$KeyFile,
    [string]$EnvironmentFile
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$work = Join-Path $repo 'output/ecs_backend_work'
$venv = Join-Path $work '.venv'
$python = Join-Path $venv 'Scripts/python.exe'
$helper = Join-Path $PSScriptRoot 'aliyun_test_host.py'

function Test-LocalPython([string]$Executable, [string[]]$PrefixArgs = @()) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return $false }
    # Python's copied venv launcher can exist while its old base executable is missing.
    try {
        & $Executable @PrefixArgs -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 2)' 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Assert-RegularAncestors([string]$Path) {
    $candidate = [IO.Path]::GetFullPath($Path)
    while ($candidate) {
        if (Test-Path -LiteralPath $candidate) {
            if ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Redirected setup paths are not supported. Use a regular NTFS addon directory.'
            }
        }
        $candidate = [IO.Path]::GetDirectoryName($candidate)
    }
}

Push-Location -LiteralPath $repo
try {
    Assert-RegularAncestors $python
    if ($Action -eq 'Setup') {
        if (-not (Test-LocalPython $python)) {
            $baseExecutable = $null
            $baseArgs = @()
            if ($PythonExe) {
                $candidate = (Resolve-Path -LiteralPath $PythonExe).Path
                if (-not (Test-LocalPython $candidate)) { throw 'Specified Python cannot run Python 3.10 or newer.' }
                $baseExecutable = $candidate
            } else {
                $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
                if ($launcher) {
                    foreach ($version in @('-3.13','-3.12','-3')) {
                        if (Test-LocalPython $launcher.Source @($version)) {
                            $baseExecutable = $launcher.Source
                            $baseArgs = @($version)
                            break
                        }
                    }
                }
                if (-not $baseExecutable) { throw 'Install Python 3.13 with the Python launcher, or pass -PythonExe with its full path. No files were changed.' }
            }
            # Moving a copied venv preserves it. Do not rename while the local bridge uses it.
            $task = Get-ScheduledTask -TaskName 'Goufayu-Hammer-Test-Backend' -ErrorAction SilentlyContinue
            if ($task -and $task.State -eq 'Running') {
                throw 'Stop the Hammer backend helper before rebuilding Python. Existing environment was preserved.'
            }
            New-Item -ItemType Directory -Path $work -Force | Out-Null
            if (Test-Path -LiteralPath $venv) {
                $resolvedVenv = (Resolve-Path -LiteralPath $venv).Path
                if ($resolvedVenv -ne [IO.Path]::GetFullPath($venv) -or (Get-Item -LiteralPath $venv).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw 'Refusing to move a redirected Python environment.'
                }
                Rename-Item -LiteralPath $resolvedVenv -NewName ('.venv.old.' + [Guid]::NewGuid().ToString('N'))
            }
            # All helpers use the standard library; pip and a network download are unnecessary.
            & $baseExecutable @baseArgs -m venv --without-pip $venv
            if ($LASTEXITCODE -ne 0 -or -not (Test-LocalPython $python)) { throw 'Creating the local Python environment failed; old environment was kept.' }
            Write-Output 'LOCAL_PYTHON_CREATED'
        } else { Write-Output 'LOCAL_PYTHON_READY' }
        $configureArgs = @('-B', $helper, 'configure')
        if ($KeyFile) { $configureArgs += @('--key', $KeyFile) }
        if ($EnvironmentFile) { $configureArgs += @('--environment', $EnvironmentFile) }
        & $python @configureArgs
        if ($LASTEXITCODE -ne 0) { throw 'Local configuration failed. See the fixed error code above.' }
    } elseif (-not (Test-LocalPython $python)) {
        throw 'The local Python environment is missing or copied from another PC. Run Setup first.'
    }
    $operation = switch ($Action) {
        'OnlineCheck' { 'online-check' }
        'Credential' { 'credential' }
        default { 'check' }
    }
    & $python -B $helper $operation
    if ($LASTEXITCODE -ne 0) {
        Write-Output 'SETUP_NEEDS_ATTENTION: see docs/NEW_PC_LAN_TEST_GUIDE.md for the reported checks.'
        exit 1
    }
    Write-Output 'SETUP_CHECK_OK: this is not a substitute for GAME_AUTH_READY or a multiplayer test.'
} finally {
    Pop-Location
}
