$ErrorActionPreference = 'Stop'
$cleanupProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $cleanupProject 'tools/backend_python.ps1')
$cleanupPython = Resolve-SurvivalReleasePython -RepoRoot $cleanupProject
if (-not $cleanupPython) { throw 'No working project Python found.' }
Push-Location -LiteralPath $cleanupProject
try {
    & $cleanupPython -B -X utf8 (Join-Path $PSScriptRoot 'cli.py')
    exit $LASTEXITCODE
} finally { Pop-Location }
