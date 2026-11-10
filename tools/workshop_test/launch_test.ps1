param([Parameter(Mandatory=$true)][ValidateSet('Offline','Online')][string]$Mode,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/backend_python.ps1')
try {
    if($Mode -eq 'Online'){$python=Resolve-SurvivalReleasePython -RepoRoot $repo}
    else{$python=Resolve-SurvivalBackendPython -RepoRoot $repo}
    if($Mode -eq 'Online'){
        $publishedText=& $python -B -X utf8 (Join-Path $PSScriptRoot 'published_route.py')
        $publishedCode=$LASTEXITCODE
        if($publishedCode -eq 0){
            $published=$publishedText|ConvertFrom-Json
            if($published.ok -eq $true -and $published.mode -eq 'published_workshop'){
                if(-not $CheckOnly){Write-Output ('Published Workshop '+$published.release_sequence+' / manifest '+$published.steam_manifest)}
                & (Join-Path $PSScriptRoot 'launch_published.ps1') -CheckOnly:$CheckOnly
                exit $LASTEXITCODE
            }
        }
    }
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
    # Only explain these fixed dependency failures. Never echo arbitrary
    # subprocess/configuration exceptions (which may contain private values).
    $failureMessage=[string]$_.Exception.Message
    if($Mode -eq 'Online' -and $failureMessage.StartsWith('SURVIVAL_RELEASE_PYTHON must point',[StringComparison]::Ordinal)){
        Write-Output 'SURVIVAL_RELEASE_PYTHON must point to a working Windows Python 3.10+ python.exe with cryptography. No dependencies are installed automatically.'
    } elseif($Mode -eq 'Online' -and $failureMessage.StartsWith('Signed Online entry needs',[StringComparison]::Ordinal)){
        Write-Output 'Signed Online entry needs Windows Python 3.10+ with cryptography. Set SURVIVAL_RELEASE_PYTHON to an existing release environment. No dependencies are installed automatically.'
    }
    Write-Output 'test_entry_preparation_failed'
    exit 1
}
