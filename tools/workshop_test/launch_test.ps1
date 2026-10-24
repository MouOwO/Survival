param([Parameter(Mandatory=$true)][ValidateSet('Offline','Online')][string]$Mode,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/backend_python.ps1')
try {
    $python=Resolve-SurvivalBackendPython -RepoRoot $repo
    $entryArguments=@('-B','-X','utf8',(Join-Path $PSScriptRoot 'test_entry.py'),$Mode.ToLowerInvariant())
    if($CheckOnly){$entryArguments+='--check'}
    Push-Location $repo
    try {
        $reply=& $python @entryArguments
        $code=$LASTEXITCODE
    } finally {Pop-Location}
    $reply | Write-Output
    if($code -ne 0){
        Write-Output 'Test entry failed. Keep Steam running and exit the current Dota game before switching entries.'
        exit $code
    }
    if(-not $CheckOnly){
        if($Mode -eq 'Offline'){Write-Output 'Offline logic test: memory-only test profile, no cloud login. In-game debug commands remain available.'}
        else{Write-Output 'Online login test: confirm this match on the web page. Keep this PC and its Steam connection online.'}
    }
} catch {
    Write-Output 'test_entry_preparation_failed'
    exit 1
}
