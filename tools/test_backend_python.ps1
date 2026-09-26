$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'backend_python.ps1')
$checks = 0
function Assert-Result($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
foreach ($name in @('backend_python.ps1','launch_aliyun_test_game.ps1','setup_hammer_backend.ps1','run_hammer_backend.ps1')) {
    $parseTokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$parseTokens, [ref]$parseErrors)
    Assert-Result ($parseErrors.Count -eq 0) ("PowerShell parse failed: " + $name)
}

# Exercise the real subprocess boundary without requiring Python or a network.
$fixture = Join-Path $repo ('output/backend_python_test_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$interpreter = Join-Path $fixture ('Python ' + [char]0x6D4B + [char]0x8BD5 + '.exe')
[System.IO.File]::WriteAllBytes($interpreter, [byte[]]@())
$reportedPath = ($interpreter | ConvertTo-Json -Compress).Replace([string][char]0x6D4B, '\u6d4b').Replace([string][char]0x8BD5, '\u8bd5')
$good = Join-Path $fixture 'good probe.ps1'
$bad = Join-Path $fixture 'bad probe.ps1'
$slow = Join-Path $fixture 'slow probe.ps1'
[System.IO.File]::WriteAllText($good, ("Write-Output '" + $reportedPath.Replace("'", "''") + "'"), $utf8)
[System.IO.File]::WriteAllText($bad, '[Console]::Error.WriteLine("fixture-error-do-not-expose"); exit 1', $utf8)
[System.IO.File]::WriteAllText($slow, 'Start-Sleep -Seconds 15', $utf8)
function Probe-Arguments([string]$Path) { @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"' + $Path + '"')) }
Assert-Result ((Invoke-SurvivalPythonProbe -Executable $shell -PrefixArguments (Probe-Arguments $good)) -eq $interpreter) 'Probe did not decode an absolute path with spaces and Unicode.'
Assert-Result ($null -eq (Invoke-SurvivalPythonProbe -Executable $shell -PrefixArguments (Probe-Arguments $bad))) 'Failed subprocess must not return or print stderr.'
$timer = [Diagnostics.Stopwatch]::StartNew()
Assert-Result ($null -eq (Invoke-SurvivalPythonProbe -Executable $shell -PrefixArguments (Probe-Arguments $slow))) 'Hung interpreter must be rejected.'
Assert-Result ($timer.Elapsed.TotalSeconds -lt 12) 'Probe timeout did not stop its child.'
Assert-Result ($null -eq (Invoke-SurvivalPythonProbe -Executable (Join-Path $fixture 'missing.exe'))) 'Missing interpreter must be rejected.'
$aliasPath = Join-Path $fixture 'Microsoft/WindowsApps/python.exe'
New-Item -ItemType Directory -Path (Split-Path -Parent $aliasPath) -Force | Out-Null
Copy-Item -LiteralPath $shell -Destination $aliasPath
Assert-Result ($null -eq (Invoke-SurvivalPythonProbe -Executable $aliasPath -PrefixArguments (Probe-Arguments $good))) 'WindowsApps Python alias must not run.'

# Discovery must enumerate PATH matches and list py runtimes without running py -3.
& {
    function Get-Command {
        param($Name, [switch]$All, $CommandType, $ErrorAction)
        Assert-Result $All 'Discovery must enumerate all PATH matches.'
        if ($Name -eq 'py.exe') { [PSCustomObject]@{Source='fake-launcher.exe'} }
        if ($Name -eq 'python.exe') {
            [PSCustomObject]@{Source='C:\Microsoft\WindowsApps\python.exe'}
            [PSCustomObject]@{Source='C:\Real Python\python.exe'}
        }
    }
    function Get-ChildItem { param($LiteralPath, $ErrorAction) }
    function Invoke-SurvivalPythonCommand {
        param($Executable, $Arguments)
        Assert-Result ($Arguments.Count -eq 1 -and $Arguments[0] -eq '-0p') 'Launcher discovery must not install a runtime.'
        ' -V:3.13 * C:\Python 313\python.exe'
        ' -3.11-64  C:\Python 311\python.exe'
    }
    $discovered = @(Get-SurvivalPythonCandidates -RepoRoot $repo)
    $paths = @($discovered | ForEach-Object { $_.Executable })
    Assert-Result ($paths -contains 'C:\Python 313\python.exe' -and $paths -contains 'C:\Python 311\python.exe') 'New and legacy launcher paths must both be discovered.'
    Assert-Result ($paths -contains 'C:\Real Python\python.exe') 'Real Python after WindowsApps must remain a candidate.'
}

# Simulate interpreter discovery: stale copied venv, launcher and explicit override.
function Get-SurvivalPythonCandidates { param([string]$RepoRoot) $script:candidates }
function Invoke-SurvivalPythonProbe {
    param([string]$Executable, [string[]]$PrefixArguments = @())
    $script:attempts += $Executable
    if ($Executable -eq 'launcher.exe') {
        Assert-Result ($PrefixArguments.Count -eq 1 -and $PrefixArguments[0] -eq '-3') 'py must select Python 3.'
    }
    if ($Executable -eq $script:accepted) { return $script:interpreter }
}
$candidates = @(
    [PSCustomObject]@{Executable='broken-venv.exe'; PrefixArguments=@()},
    [PSCustomObject]@{Executable='launcher.exe'; PrefixArguments=@('-3')},
    [PSCustomObject]@{Executable='unused.exe'; PrefixArguments=@()}
)
$accepted = 'launcher.exe'; $attempts = @()
Assert-Result ((Resolve-SurvivalBackendPython -RepoRoot $repo -PythonPath '') -eq $interpreter) 'Broken venv did not fall back to py.'
Assert-Result (($attempts -join ',') -eq 'broken-venv.exe,launcher.exe') 'Fallback order or early success is wrong.'
$accepted = 'explicit.exe'; $attempts = @()
Assert-Result ((Resolve-SurvivalBackendPython -RepoRoot $repo -PythonPath 'explicit.exe') -eq $interpreter) 'Explicit interpreter was not selected.'
Assert-Result (($attempts -join ',') -eq 'explicit.exe') 'Explicit interpreter must have priority.'
$attempts = @(); $errorText = ''
try { Resolve-SurvivalBackendPython -RepoRoot $repo -PythonPath 'invalid.exe' | Out-Null } catch { $errorText = $_.Exception.Message }
Assert-Result ($errorText -like 'SURVIVAL_PYTHON must point*' -and $attempts.Count -eq 1) 'Invalid explicit interpreter must fail clearly, without fallback.'
$accepted = ''; $attempts = @(); $errorText = ''
try { Resolve-SurvivalBackendPython -RepoRoot $repo -PythonPath '' | Out-Null } catch { $errorText = $_.Exception.Message }
Assert-Result ($errorText -like 'Python 3.10+ was not found.*' -and $attempts.Count -eq 3) 'Missing Python must produce an actionable error.'
Write-Output ("BACKEND_PYTHON_TEST_PASS checks=" + $checks)
