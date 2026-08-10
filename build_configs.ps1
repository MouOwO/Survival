param(
    [switch]$CheckOnly,
    [string]$PythonPath
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$AddonRoot = $PSScriptRoot
$Builder = Join-Path $AddonRoot 'tools\build_configs.py'
$Generated = Join-Path $AddonRoot 'scripts\vscripts\config\generated'

function Resolve-PythonExecutable {
    $candidates = @()
    if ($PythonPath) { $candidates += $PythonPath }
    if ($env:QCLAW_PYTHON_BINARY) { $candidates += $env:QCLAW_PYTHON_BINARY }

    # Prefer the Python 3 installation registered on this workstation. Keep
    # this as a candidate rather than a hard requirement so -PythonPath and
    # QCLAW_PYTHON_BINARY can still override it on other machines.
    $candidates += 'C:\Users\a\.workbuddy\binaries\python\versions\3.14.3\python.exe'

    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonCommand -and $pythonCommand.Source -notlike '*\Microsoft\WindowsApps\*') {
        $candidates += $pythonCommand.Source
    }

    foreach ($root in @('D:\QClaw', (Join-Path $env:LOCALAPPDATA 'QClaw'))) {
        if (Test-Path $root) {
            $candidates += Get-ChildItem $root -Recurse -File -Filter python.exe -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like '*\resources\python\python.exe' } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -ExpandProperty FullName
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not $candidate -or -not (Test-Path $candidate -PathType Leaf)) { continue }
        & $candidate -c "import sys; sys.exit(0 if sys.version_info.major == 3 else 1)" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return [PSCustomObject]@{
                Command = (Resolve-Path $candidate).Path
                PrefixArgs = @()
                Display = (Resolve-Path $candidate).Path
            }
        }
    }

    # The Python Launcher bypasses the non-functional Microsoft Store alias
    # and selects the registered Python 3 runtime.
    $pythonLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pythonLauncher) {
        & $pythonLauncher.Source -3 -c "import sys; sys.exit(0 if sys.version_info.major == 3 else 1)" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return [PSCustomObject]@{
                Command = $pythonLauncher.Source
                PrefixArgs = @('-3')
                Display = "$($pythonLauncher.Source) -3"
            }
        }
    }

    throw "Python 3 executable not found. Pass it explicitly with -PythonPath 'D:\VisionScore\python310_embed\python.exe'. The Microsoft Store WindowsApps alias is not a real Python runtime."
}

$Python = Resolve-PythonExecutable
$PythonCommand = $Python.Command
$PythonPrefixArgs = @($Python.PrefixArgs)
Write-Host "PYTHON: $($Python.Display)"

Push-Location $AddonRoot
try {
    if (-not $CheckOnly) {
        & $PythonCommand @PythonPrefixArgs $Builder
        if ($LASTEXITCODE -ne 0) { throw "CSV to Lua failed: $LASTEXITCODE" }
    }

    & $PythonCommand @PythonPrefixArgs -c "from pathlib import Path; import sys; r=Path(r'$Generated'); fs=list(r.glob('*.lua')); bad=[str(p) for p in fs if chr(0xfffd) in p.read_text(encoding='utf-8-sig')]; print(f'CONFIG_VERIFY files={len(fs)} bad_utf8={len(bad)}'); sys.exit(1 if len(fs)<47 or bad else 0)"
    if ($LASTEXITCODE -ne 0) { throw 'Generated Lua verification failed.' }

    Write-Host 'CONFIG_BUILD_PASS' -ForegroundColor Green
    Write-Host "Output: $Generated"
    Write-Host 'Close the current test session and Run the map again. Required Lua modules are cached inside a running VM.' -ForegroundColor Yellow
}
finally { Pop-Location }
