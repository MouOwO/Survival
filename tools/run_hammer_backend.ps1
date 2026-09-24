$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$python = Join-Path $repo 'output/ecs_backend_work/.venv/Scripts/python.exe'
$bridge = Join-Path $PSScriptRoot 'hammer_backend_bridge.py'
# Blender's bundled Python can create a venv pythonw.exe launcher without a
# base pythonw.exe. Use the tested console interpreter in a hidden child.
$process = Start-Process -FilePath $python -ArgumentList @('-B', ('"' + $bridge + '"'), 'run') `
    -WorkingDirectory $repo -WindowStyle Hidden -PassThru -Wait
exit $process.ExitCode
