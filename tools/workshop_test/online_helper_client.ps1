param(
    [ValidateSet('inspect','start')][string]$Mode = 'inspect',
    [string]$SteamExe
)
$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$taskGameRoot = Split-Path -Parent (Split-Path -Parent $taskProject)
$taskExpectedExe = Join-Path $taskGameRoot 'bin/win64/dota2.exe'
function Read-Client([int]$ProcessId) {
    $taskDetail = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $ProcessId)
    if (-not $taskDetail) { return $null }
    $taskProcess = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $taskProcess) { return $null }
    [ordered]@{
        pid = $ProcessId
        filetime = $taskProcess.StartTime.ToFileTimeUtc().ToString()
        exe = $taskDetail.ExecutablePath
        expected_exe = ($taskDetail.ExecutablePath -ieq $taskExpectedExe)
        ordinary = ($taskDetail.CommandLine -notmatch '(?i)(?:^|\s)-(?:tools|dev|addon)(?:\s|$)')
        consolelog = [bool]($taskDetail.CommandLine -match '(?i)(?:^|\s)-consolelog(?:\s|$)')
    }
}
function Read-Clients {
    $taskFound = @(Get-CimInstance Win32_Process -Filter "Name='dota2.exe'")
    if ($taskFound.Count -gt 4) { throw 'too_many_clients' }
    @($taskFound | ForEach-Object { Read-Client $_.ProcessId })
}
$taskExisting = @(Read-Clients)
if ($Mode -eq 'inspect') {
    ConvertTo-Json -InputObject $taskExisting -Compress
    exit 0
}
if ($taskExisting.Count) { throw 'existing_client_requires_normal_exit' }
if (-not (Test-Path -LiteralPath $SteamExe -PathType Leaf)) { throw 'steam_not_found' }
# Subscribe before launching. One reconciliation inventory handles a queued event;
# waiting uses the process-start trace, not repeated whole-process enumeration.
$taskEventId = 'SurvivalOnlineClient_' + [Guid]::NewGuid().ToString('N')
$taskStarted = [DateTime]::UtcNow
$taskClient = $null
try {
    Register-CimIndicationEvent -Namespace root/cimv2 -Query (
        "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName = 'dota2.exe'") -SourceIdentifier $taskEventId | Out-Null
    Start-Process -FilePath $SteamExe -ArgumentList @('-applaunch','570','-novid',
        '-console','-consolelog','+sv_cheats','0','+net_showmsg','0') -WindowStyle Hidden
    $taskNew = @(Read-Clients)
    if ($taskNew.Count -eq 1) { $taskClient = $taskNew[0] }
    while (-not $taskClient -and ([DateTime]::UtcNow - $taskStarted).TotalSeconds -lt 180) {
        $taskEvent = Wait-Event -SourceIdentifier $taskEventId -Timeout 1
        if ($taskEvent) {
            $taskCandidate = Read-Client ([int]$taskEvent.SourceEventArgs.NewEvent.ProcessID)
            Remove-Event -EventIdentifier $taskEvent.EventIdentifier
            if ($taskCandidate -and $taskCandidate.expected_exe -and
                [DateTime]::FromFileTimeUtc([long]$taskCandidate.filetime) -ge $taskStarted.AddSeconds(-1)) {
                $taskClient = $taskCandidate
            }
        }
    }
} finally {
    Unregister-Event -SourceIdentifier $taskEventId -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier $taskEventId -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
}
if (-not $taskClient) { throw 'client_start_timeout_preserve_client' }
if (-not $taskClient.expected_exe -or -not $taskClient.ordinary -or -not $taskClient.consolelog) {
    throw 'client_start_settings_invalid'
}
ConvertTo-Json -InputObject $taskClient -Compress
