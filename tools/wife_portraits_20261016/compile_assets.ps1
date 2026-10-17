param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$wifePython='C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe'
$wifeArguments=@((Join-Path $PSScriptRoot 'compile_assets.py'))
if(-not $CheckOnly){$wifeArguments+='--apply'}
& $wifePython @wifeArguments
if($LASTEXITCODE -ne 0){throw 'Scoped wife portrait compile failed; review the scoped backup/failure report.'}
