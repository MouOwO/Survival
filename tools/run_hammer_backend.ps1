$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'backend_python.ps1')
$python = Resolve-SurvivalBackendPython -RepoRoot $repo
$bridge = Join-Path $PSScriptRoot 'hammer_backend_bridge.py'
# Reconcile saved auto-connect settings before the login helper polls Dota.
# With MCP, share its relay; without MCP, keep 29000 available to this helper.
& (Join-Path $PSScriptRoot 'repair_hammer_console.ps1') -Action Repair
# Blender's bundled Python can create a venv pythonw.exe launcher without a
# base pythonw.exe. Use the tested console interpreter in a hidden child.
$process = Start-Process -FilePath $python -ArgumentList @('-B', ('"' + $bridge + '"'), 'run') `
    -WorkingDirectory $repo -WindowStyle Hidden -PassThru -Wait
exit $process.ExitCode
