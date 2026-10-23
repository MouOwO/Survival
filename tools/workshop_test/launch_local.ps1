param([ValidateRange(1,4)][int]$ExpectedPlayers = 1)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/backend_python.ps1')
$python = Resolve-SurvivalBackendPython -RepoRoot $repo
Push-Location $repo
try {
    & $python -B -X utf8 (Join-Path $PSScriptRoot 'local_host.py') run --expected-players $ExpectedPlayers
    exit $LASTEXITCODE
} finally { Pop-Location }
