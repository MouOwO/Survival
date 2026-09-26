# Shared by the interactive launcher and the hidden Hammer helper.
function Invoke-SurvivalPythonCommand {
    param([string]$Executable, [string[]]$Arguments)
    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo.FileName = $Executable
        $process.StartInfo.Arguments = $Arguments -join ' '
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.EnvironmentVariables['PYTHON_MANAGER_AUTOMATIC_INSTALL'] = 'false'
        foreach ($name in @('PYLAUNCHER_ALLOW_INSTALL','PYLAUNCHER_ALWAYS_INSTALL','PYLAUNCHER_DRYRUN')) {
            $process.StartInfo.EnvironmentVariables.Remove($name)
        }
        if (-not $process.Start()) { return }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) { $process.Kill(); return }
        if ($process.ExitCode -eq 0) { return $stdout.GetAwaiter().GetResult().Trim() }
    } catch {
        # A copied/broken venv is only one candidate. Never print subprocess errors.
    } finally {
        $process.Dispose()
    }
}

function Invoke-SurvivalPythonProbe {
    param([string]$Executable, [string[]]$PrefixArguments = @())
    if (-not $Executable -or -not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return }
    if ($Executable -match '[\\/]Microsoft[\\/]WindowsApps[\\/]python[^\\/]*\.exe$') { return }
    $probeCode = 'import sys,json,ctypes,http.client,socket,subprocess,msvcrt; assert sys.platform == ''win32'' and sys.version_info >= (3,10); print(json.dumps(sys.executable))'
    $probeArguments = @($PrefixArguments) + @('-I', '-B', '-c', ('"' + $probeCode + '"'))
    try {
        $output = Invoke-SurvivalPythonCommand -Executable $Executable -Arguments $probeArguments
        if (-not $output) { return }
        $resolved = $output | ConvertFrom-Json
        if ($resolved -is [string] -and (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $resolved).Path
        }
    } catch {}
}

function Get-SurvivalPythonCandidates {
    param([string]$RepoRoot)
    [PSCustomObject]@{ Executable = (Join-Path $RepoRoot 'output/ecs_backend_work/.venv/Scripts/python.exe'); PrefixArguments = @() }
    foreach ($name in @('py.exe', 'python.exe', 'python3.exe')) {
        foreach ($command in @(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue)) {
            if ($name -eq 'py.exe') {
                # List existing runtimes only. "py -3" can install one implicitly.
                $listing = Invoke-SurvivalPythonCommand -Executable $command.Source -Arguments @('-0p')
                foreach ($line in @($listing -split '\r?\n')) {
                    if ($line -match '\s((?:[A-Za-z]:[\\/]|\\\\)[^\r\n]+\.exe)\s*$') {
                        [PSCustomObject]@{ Executable = $Matches[1]; PrefixArguments = @() }
                    }
                }
            } else {
                [PSCustomObject]@{ Executable = $command.Source; PrefixArguments = @() }
            }
        }
    }
    # Also find a normal Python installation when it was not added to PATH.
    foreach ($registryRoot in @('HKCU:\Software\Python\PythonCore', 'HKLM:\Software\Python\PythonCore', 'HKLM:\Software\WOW6432Node\Python\PythonCore')) {
        foreach ($versionKey in @(Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue | Sort-Object PSChildName -Descending)) {
            $installKey = Get-Item -LiteralPath (Join-Path $versionKey.PSPath 'InstallPath') -ErrorAction SilentlyContinue
            if (-not $installKey) { continue }
            $executable = $installKey.GetValue('ExecutablePath')
            if (-not $executable -and $installKey.GetValue('')) {
                $executable = Join-Path $installKey.GetValue('') 'python.exe'
            }
            if ($executable) { [PSCustomObject]@{ Executable = $executable; PrefixArguments = @() } }
        }
    }
}

function Resolve-SurvivalBackendPython {
    param([Parameter(Mandatory = $true)][string]$RepoRoot, [string]$PythonPath = $env:SURVIVAL_PYTHON)
    if ($PythonPath) {
        $resolved = Invoke-SurvivalPythonProbe -Executable $PythonPath
        if ($resolved) { return $resolved }
        throw 'SURVIVAL_PYTHON must point to a working Windows Python 3.10+ python.exe with ctypes. See docs/STARTUP_LOADING.md.'
    }
    foreach ($candidate in @(Get-SurvivalPythonCandidates -RepoRoot $RepoRoot)) {
        $resolved = Invoke-SurvivalPythonProbe -Executable $candidate.Executable -PrefixArguments $candidate.PrefixArguments
        if ($resolved) { return $resolved }
    }
    throw 'Python 3.10+ was not found. Install Python, reopen the launcher, or set SURVIVAL_PYTHON to its python.exe. The old deployment venv is optional. See docs/STARTUP_LOADING.md for the other test connection requirements.'
}
