param([ValidateRange(1,4)][int]$ExpectedPlayers = 1, [switch]$DirectJoin)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/backend_python.ps1')
$python = Resolve-SurvivalBackendPython -RepoRoot $repo
Push-Location $repo
try {
    $launchArgs = @('-B','-X','utf8',(Join-Path $PSScriptRoot 'local_host.py'),'run','--expected-players',"$ExpectedPlayers")
    if ($DirectJoin) { $launchArgs += '--direct-join' }
    & $python @launchArgs
    exit $LASTEXITCODE
} finally { Pop-Location }
