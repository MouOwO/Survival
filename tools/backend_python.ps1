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
    param([string]$Executable, [string[]]$PrefixArguments = @(), [switch]$RequireReleaseCrypto)
    if (-not $Executable -or -not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return }
    if ($Executable -match '[\\/]Microsoft[\\/]WindowsApps[\\/]python[^\\/]*\.exe$') { return }
    $probeCode = 'import sys,json,ctypes,http.client,socket,subprocess,msvcrt; assert sys.platform == ''win32'' and sys.version_info >= (3,10); '
    if ($RequireReleaseCrypto) {
        # Public RFC 8032 empty-message vector only: no key/config files, writes,
        # network, installation or subprocess dependencies are used by this probe.
        $probeCode += 'from cryptography.hazmat.primitives import serialization; from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey,Ed25519PublicKey; from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes; '
        $probeCode += 'Ed25519PublicKey.from_public_bytes(bytes.fromhex(''d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'')).verify(bytes.fromhex(''e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b''),b''''); '
    }
    $probeCode += 'print(json.dumps(sys.executable))'
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

# Signed Online entry needs cryptography; Offline/backend-only callers retain
# their existing standard-library-only resolution and explicit override policy.
function Resolve-SurvivalReleasePython {
    param([Parameter(Mandatory = $true)][string]$RepoRoot, [string]$PythonPath = $env:SURVIVAL_RELEASE_PYTHON)
    if ($PythonPath) {
        $resolved = Invoke-SurvivalPythonProbe -Executable $PythonPath -RequireReleaseCrypto
        if ($resolved) { return $resolved }
        throw 'SURVIVAL_RELEASE_PYTHON must point to a working Windows Python 3.10+ python.exe with cryptography. No dependencies are installed automatically.'
    }
    $managedPython = ('D:/Survival_' + [char]0x5B89 + [char]0x5168 + [char]0x5DE5 + [char]0x5177 + '/venv/Scripts/python.exe')
    $resolved = Invoke-SurvivalPythonProbe -Executable $managedPython -RequireReleaseCrypto
    if ($resolved) { return $resolved }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    [void]$seen.Add($managedPython.Replace('/', '\'))
    foreach ($candidate in @(Get-SurvivalPythonCandidates -RepoRoot $RepoRoot)) {
        if (-not $candidate.Executable -or -not $seen.Add($candidate.Executable.Replace('/', '\'))) { continue }
        $resolved = Invoke-SurvivalPythonProbe -Executable $candidate.Executable -PrefixArguments $candidate.PrefixArguments -RequireReleaseCrypto
        if ($resolved) { return $resolved }
    }
    throw 'Signed Online entry needs Windows Python 3.10+ with cryptography. Set SURVIVAL_RELEASE_PYTHON to an existing release environment. No dependencies are installed automatically.'
}
