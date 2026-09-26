param([ValidateSet('Install','Start','Status','Stop','Uninstall')][string]$Action = 'Install')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'backend_python.ps1')
$python = Resolve-SurvivalBackendPython -RepoRoot $repo
$bridge = Join-Path $PSScriptRoot 'hammer_backend_bridge.py'
$runner = Join-Path $PSScriptRoot 'run_hammer_backend.ps1'
$powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$taskName = 'Goufayu-Hammer-Test-Backend'
$arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $runner + '"'
$stopFile = Join-Path $repo 'output/hammer_backend/bridge.stop'
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name

foreach ($path in @($python, $powershell, $bridge, $runner)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Local backend Python or bridge is missing.' }
}
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    $actions = @($existing.Actions)
    if ($actions.Count -ne 1 -or $actions[0].Execute -ne $powershell -or $actions[0].Arguments -ne $arguments) {
        throw 'A different task already uses this name; it has not been changed.'
    }
}
function Stop-BridgeGracefully {
    & $python -B $bridge stop
    if ($LASTEXITCODE -ne 0) { throw 'Failed to request a graceful stop; task was preserved.' }
    # Let an in-flight injection execute its finally block and remove its
    # private temporary credential. Never terminate it halfway through.
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ($existing -and (Get-ScheduledTask -TaskName $taskName).State -eq 'Running') {
        if ([DateTime]::UtcNow -gt $deadline) {
            throw 'The current connection attempt is still finishing. Retry Stop shortly; the process was not terminated.'
        }
        Start-Sleep -Milliseconds 500
    }
}
switch ($Action) {
    'Install' {
        if ($existing -and $existing.State -eq 'Running') { Stop-BridgeGracefully }
        Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
        $launch = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $repo
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $taskName -Action $launch -Trigger $trigger `
            -Principal $principal -Settings $settings -Description 'Connect this user''s survival Hammer tests to the existing ECS test backend; no game launch or stored credentials.' -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Write-Output 'HAMMER_BACKEND_INSTALLED: hidden current-user helper starts at Windows sign-in.'
        Write-Output 'Hammer Run Map remains the entry point. The helper connects only survival/template_map Tools sessions.'
    }
    'Start' {
        if (-not $existing) { throw 'Run Install first.' }
        if ($existing.State -eq 'Running') { Stop-BridgeGracefully }
        Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
        Enable-ScheduledTask -TaskName $taskName | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Write-Output 'HAMMER_BACKEND_START_REQUESTED'
    }
    'Status' {
        if ($existing) { Write-Output ('Scheduled task: ' + $existing.State) }
        else { Write-Output 'Scheduled task: not installed' }
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
