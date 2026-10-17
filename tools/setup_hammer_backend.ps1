param(
    [ValidateSet('Install','Start','Status','Stop','Uninstall')][string]$Action = 'Install',
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'
if ($AsJson -and $Action -ne 'Status') { throw 'AsJson is supported only for Status.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'backend_python.ps1')
$python = Resolve-SurvivalBackendPython -RepoRoot $repo
$bridge = Join-Path $PSScriptRoot 'hammer_backend_bridge.py'
$runner = Join-Path $PSScriptRoot 'run_hammer_backend.ps1'
$consoleRepair = Join-Path $PSScriptRoot 'repair_hammer_console.ps1'
$powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$taskName = 'Goufayu-Hammer-Test-Backend'
$arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $runner + '"'
$stopFile = Join-Path $repo 'output/hammer_backend/bridge.stop'
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name

foreach ($path in @($python, $powershell, $bridge, $runner, $consoleRepair)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Local backend Python or bridge is missing.' }
}
function Repair-ConsoleConnection {
    if (-not (Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'Node.js is required by the console helper. Install Node.js and rerun Setup.'
    }
    & $consoleRepair -Action Repair
}
function Show-BridgeStatus {
    $statusFile = Join-Path $repo 'output/hammer_backend/bridge_status.json'
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (Test-Path -LiteralPath $statusFile) {
        try { $state = Get-Content -LiteralPath $statusFile -Raw | ConvertFrom-Json }
        catch { break }
        if ($state.status -ne 'stopped' -or [DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds 250
    }
    & $python -B $bridge status
    Write-Output 'connected means a live game connection; waiting_for_party means the host has not started loading.'
    Write-Output 'A start request alone does not confirm game authentication. Use -Action Status to inspect it.'
}
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    $actions = @($existing.Actions)
    if ($actions.Count -ne 1 -or $actions[0].Execute -ne $powershell -or $actions[0].Arguments -ne $arguments) {
        throw 'A different task already uses this name; it has not been changed.'
    }
}
function Stop-BridgeGracefully {
    $stopLines = @(& $python -B $bridge stop)
    $stopExitCode = $LASTEXITCODE
    try { $stopResult = ($stopLines -join "`n") | ConvertFrom-Json }
    catch { throw 'The helper did not confirm a graceful stop; no process was terminated.' }
    if ($stopExitCode -ne 0 -or $stopResult.ok -isnot [bool] -or $stopResult.ok -ne $true -or
        $stopResult.status -ne 'stopped' -or $stopResult.stop_confirmed -isnot [bool] -or
        $stopResult.stop_confirmed -ne $true) {
        throw 'The helper did not confirm a graceful stop; no process was terminated.'
    }
    # Python confirms the instance lock only after injection cleanup and the
    # Node console socket have closed. A legacy -Wait task wrapper may still
    # wait for its preserved SSH descendant; task Running is not helper liveness.
    [pscustomobject]@{ok=$true;status='stopped';stop_confirmed=$true} | ConvertTo-Json -Compress
}
function Start-BridgeTaskOrLegacyRunner {
    $currentTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $currentActions = @($currentTask.Actions)
    if ($currentActions.Count -ne 1 -or $currentActions[0].Execute -ne $powershell -or
        $currentActions[0].Arguments -ne $arguments) {
        throw 'The helper task changed during setup; no helper was started.'
    }
    if ($currentTask.State -eq 'Running') {
        # IgnoreNew would discard a scheduler start while an old wrapper waits
        # for SSH. Start the same verified, fixed local action without stopping
        # that wrapper or its descendants. The bridge instance lock stays unique.
        Start-Process -FilePath $powershell -ArgumentList $arguments -WorkingDirectory $repo -WindowStyle Hidden | Out-Null
    } else {
        Start-ScheduledTask -TaskName $taskName
    }
}
function Show-BridgeStatusJson {
    # Use the bridge's credential-free status action, which checks its heartbeat.
    # Do not expose arbitrary fields from a saved status file or inspect a game.
    $statusLines = @(& $python -B $bridge status)
    $statusExitCode = $LASTEXITCODE
    $helperStatus = 'status_unavailable'
    $helperRunning = $false
    $statusOk = $false
    try {
        $helperState = ($statusLines -join "`n") | ConvertFrom-Json
        $allowed = @('not_started', 'stopped', 'heartbeat_expired', 'waiting_for_party',
            'waiting_for_map', 'waiting_for_workshop', 'authentication_required',
            'authentication_applied', 'configured', 'connected', 'retrying', 'already_running')
        if ($helperState.status -in $allowed -and $helperState.ok -is [bool]) {
            $helperStatus = [string]$helperState.status
            $statusOk = $statusExitCode -eq 0 -or -not $helperState.ok
            if ($helperStatus -notin @('not_started', 'stopped', 'heartbeat_expired')) {
                $updated = $helperState.updated_at
                if ($updated -is [int] -or $updated -is [long] -or $updated -is [double] -or $updated -is [decimal]) {
                    $unixNow = ([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalSeconds
                    $age = $unixNow - [double]$updated
                    $helperRunning = $age -ge -5 -and $age -le 90
                    if (-not $helperRunning) { $helperStatus = 'heartbeat_expired' }
                }
            }
        }
    } catch { }
    $taskState = if ($existing) { [string]$existing.State } else { 'not_installed' }
    if ($taskState -notin @('Unknown', 'Disabled', 'Queued', 'Ready', 'Running', 'not_installed')) {
        $taskState = 'Unknown'
    }
    $taskEnabled = $false
    if ($existing) {
        $taskEnabled = $taskState -ne 'Disabled'
        if ($existing.Settings -and $existing.Settings.Enabled -is [bool]) {
            $taskEnabled = $existing.Settings.Enabled
        }
    }
    [pscustomobject]@{ok=$statusOk; task_installed=($null -ne $existing);
        task_state=$taskState; task_enabled=$taskEnabled;
        helper_running=$helperRunning; helper_status=$helperStatus} | ConvertTo-Json -Compress
}
switch ($Action) {
    'Install' {
        Repair-ConsoleConnection
        # A manual resident helper can own the instance lock even when the
        # scheduled task is Ready or missing. Drain it before removing STOP.
        Stop-BridgeGracefully
        Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
        $launch = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $repo
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $taskName -Action $launch -Trigger $trigger `
            -Principal $principal -Settings $settings -Description 'Connect this user''s survival Hammer tests to the existing ECS test backend; no game launch or stored credentials.' -Force | Out-Null
        Start-BridgeTaskOrLegacyRunner
        Write-Output 'HAMMER_BACKEND_INSTALLED: hidden current-user helper starts at Windows sign-in.'
        Write-Output 'Hammer Run Map remains the entry point. The helper connects only survival/template_map Tools sessions.'
        Show-BridgeStatus
    }
    'Start' {
        if (-not $existing) { throw 'Run Install first.' }
        Repair-ConsoleConnection
        Stop-BridgeGracefully
        Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
        Enable-ScheduledTask -TaskName $taskName | Out-Null
        Start-BridgeTaskOrLegacyRunner
        Write-Output 'HAMMER_BACKEND_START_REQUESTED'
        Show-BridgeStatus
    }
    'Status' {
        if ($AsJson) { Show-BridgeStatusJson; break }
        if ($existing) { Write-Output ('Scheduled task: ' + $existing.State) }
        else { Write-Output 'Scheduled task: not installed' }
        & $consoleRepair -Action Check
        & $python -B $bridge status
    }
    'Stop' {
        if ($existing) { Disable-ScheduledTask -TaskName $taskName | Out-Null }
        Stop-BridgeGracefully
        Write-Output 'HAMMER_BACKEND_STOPPED: existing SSH tunnel and current game were preserved.'
    }
    'Uninstall' {
        Stop-BridgeGracefully
        if ($existing) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
        Write-Output 'HAMMER_BACKEND_UNINSTALLED: current game, SSH tunnel and database were preserved.'
    }
}
