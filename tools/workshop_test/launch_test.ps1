param([Parameter(Mandatory=$true)][ValidateSet('Offline','Online')][string]$Mode,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/backend_python.ps1')
try {
    $python=Resolve-SurvivalBackendPython -RepoRoot $repo
    $entryArguments=@('-B','-X','utf8',(Join-Path $PSScriptRoot 'test_entry.py'),$Mode.ToLowerInvariant())
    if($CheckOnly){$entryArguments+='--check'}
    if($Mode -eq 'Online' -and -not $CheckOnly){
        Write-Output 'Local signed online test: keep this window open until Dota exits and the original installation is restored. This is not a Workshop publication.'
    }
    Push-Location $repo
    try {
        & $python @entryArguments
        $code=$LASTEXITCODE
    } finally {Pop-Location}
    if($code -ne 0){
        Write-Output 'Test entry failed. Keep Steam running and exit the current Dota game before switching entries.'
        exit $code
    }
    if(-not $CheckOnly){
        if($Mode -eq 'Offline'){Write-Output 'Offline logic test: memory-only profile, no cloud login. Cheats and debug commands are enabled.'}
        else{Write-Output 'The signed online test has ended and the original installation has been restored. Workshop publication is still a separate step.'}
    }
} catch {
    Write-Output 'test_entry_preparation_failed'
    exit 1
}
