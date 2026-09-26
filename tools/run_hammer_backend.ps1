$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'backend_python.ps1')
$python = Resolve-SurvivalBackendPython -RepoRoot $repo
$bridge = Join-Path $PSScriptRoot 'hammer_backend_bridge.py'
# Blender's bundled Python can create a venv pythonw.exe launcher without a
# base pythonw.exe. Use the tested console interpreter in a hidden child.
$process = Start-Process -FilePath $python -ArgumentList @('-B', ('"' + $bridge + '"'), 'run') `
    -WorkingDirectory $repo -WindowStyle Hidden -PassThru -Wait
exit $process.ExitCode
