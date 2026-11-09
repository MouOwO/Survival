param(
    [ValidateSet('gui','inspect','build','publish-test','resume')]
    [string]$Action = 'gui',
    [string]$Job,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'backend_python.ps1')
$taskPython = Resolve-SurvivalReleasePython -RepoRoot $taskRoot
if (-not $taskPython) { throw 'No working release Python environment found.' }
$taskCli = Join-Path $PSScriptRoot 'release_packager/cli.py'
if ($CheckOnly) {
    & $taskPython -B -X utf8 $taskCli inspect --project $taskRoot
    exit $LASTEXITCODE
}
if ($Action -eq 'gui') {
    $taskWindowPython = Join-Path (Split-Path -Parent $taskPython) 'pythonw.exe'
    if (Test-Path -LiteralPath $taskWindowPython -PathType Leaf) { $taskPython = $taskWindowPython }
}
$taskArguments = @('-B','-X','utf8',$taskCli,$Action,'--project',$taskRoot)
if ($Job) { $taskArguments += @('--job',$Job) }
Push-Location -LiteralPath $taskRoot
try {
    & $taskPython @taskArguments
    exit $LASTEXITCODE
} finally { Pop-Location }
