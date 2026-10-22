param(
    [switch]$AttachOnly,
    [ValidateRange(10,600)][int]$WaitSeconds = 300,
    [ValidateRange(1,4)][int]$ExpectedPlayers = 1,
    [ValidateRange(10,1800)][int]$JoinWaitSeconds = 600
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'backend_python.ps1')
$python = Resolve-SurvivalBackendPython -RepoRoot $repo
$tunnel = Join-Path $PSScriptRoot 'aliyun_test_connection.py'
$auth = Join-Path $PSScriptRoot 'aliyun_game_test_auth.py'

function Invoke-Check([string]$Script, [string]$Action) {
    # These helpers emit fixed status codes; credentials never enter arguments.
    $outputLines = @(& $python -B $Script $Action)
    $exitCode = $LASTEXITCODE
    try { $result = ($outputLines -join "`n") | ConvertFrom-Json }
    catch { throw 'The test connection helper did not return a status.' }
    if ($exitCode -ne 0 -and $result.ok) { throw 'The test connection helper failed.' }
    return $result
}

function Get-HammerBackendStatus {
    $lines = @(& (Join-Path $PSScriptRoot 'setup_hammer_backend.ps1') -Action Status -AsJson)
    $status = ($lines -join "`n") | ConvertFrom-Json
    if ($status.ok -ne $true -or $status.task_installed -isnot [bool] -or
        $status.task_enabled -isnot [bool] -or $status.helper_running -isnot [bool] -or
        $status.task_state -notin @('Unknown','Disabled','Queued','Ready','Running','not_installed')) {
        throw 'hammer_backend_status_invalid'
    }
    return $status
}

function Restore-HammerBackend($Previous) {
    if ($Previous.task_installed -and $Previous.task_enabled) {
        $global:LASTEXITCODE = 0
        & (Join-Path $PSScriptRoot 'setup_hammer_backend.ps1') -Action Start | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'hammer_backend_resume_failed' }
    } else {
        # Restore a previously live standalone helper without installing or
        # enabling a task. Only remove this addon's validated graceful marker.
        $runner = Join-Path $PSScriptRoot 'run_hammer_backend.ps1'
        $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        if (-not (Test-Path -LiteralPath $runner -PathType Leaf) -or
            -not (Test-Path -LiteralPath $powershell -PathType Leaf)) { throw 'hammer_backend_runner_missing' }
        $stopFile = [IO.Path]::GetFullPath((Join-Path $repo 'output/hammer_backend/bridge.stop'))
        $rootPrefix = [IO.Path]::GetFullPath($repo).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $stopFile.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'hammer_backend_stop_path_invalid'
        }
        $cursor = $stopFile
        while ($cursor) {
            if (Test-Path -LiteralPath $cursor) {
                $item = Get-Item -LiteralPath $cursor -Force
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw 'hammer_backend_stop_path_invalid'
                }
            }
            $cursor = [IO.Path]::GetDirectoryName($cursor)
        }
        if (Test-Path -LiteralPath $stopFile) {
            $marker = Get-Item -LiteralPath $stopFile -Force
            if ($marker.PSIsContainer -or $marker.Length -gt 16 -or
                (Get-Content -LiteralPath $stopFile -Raw).Trim() -ne 'stop') {
                throw 'hammer_backend_stop_marker_invalid'
            }
            Remove-Item -LiteralPath $stopFile -Force
        }
        Start-Process -FilePath $powershell -WorkingDirectory $repo -WindowStyle Hidden -ArgumentList @(
            '-NoLogo','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass',
            '-File', ('"' + $runner + '"')
        ) | Out-Null
    }
    # Starting a task or process only confirms the request. Both paths must
    # publish a fresh live helper heartbeat before restoration is confirmed.
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $restored = Get-HammerBackendStatus
        if ($restored.helper_running) { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $restored.helper_running) { throw 'hammer_backend_resume_unconfirmed' }
    Write-Host 'HAMMER_BACKEND_RESUMED: the previous automatic helper was restored.'
}

$resumeHammer = $null
$launchFailed = $false
Push-Location $repo
try {
    if ($ExpectedPlayers -gt 1) {
        # Use the normal stop path: validate task ownership, prevent task restart,
        # and let any in-flight credential file be cleaned up before continuing.
        # The stop marker also pauses a standalone bridge. Never kill the game.
        try {
            $global:LASTEXITCODE = 0
            & (Join-Path $PSScriptRoot 'setup_hammer_backend.ps1') -Action Stop | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'bridge_stop_failed' }
        } catch {
            throw 'HAMMER_BACKEND_PAUSE_FAILED: automatic authentication could not be paused. Run tools/setup_hammer_backend.ps1 -Action Stop and resolve its error before retrying LAN. This launcher has not connected or started a game.'
        }
        Write-Host 'HAMMER_BACKEND_PAUSED_FOR_LAN: the current game and SSH tunnel were preserved.'
        Write-Host 'After LAN testing, resume an installed Hammer helper with: tools/setup_hammer_backend.ps1 -Action Start'
    }
    $connected = Invoke-Check $tunnel 'connect'
    if (-not $connected.ok) {
        $connectionError = [string]$connected.error
        if ([string]::IsNullOrWhiteSpace($connectionError)) { $connectionError = [string]$connected.status }
        if ([string]::IsNullOrWhiteSpace($connectionError)) { $connectionError = 'ssh_tunnel_or_backend_unavailable' }
        $hint = switch ($connectionError) {
            'backend_unavailable' {
                ' The SSH connection reached the server, but the game backend is unavailable. Check the backend service on ECS and retry; any existing tunnel and game were preserved.'
            }
            'ssh_connection_timeout' {
                ' ECS SSH port 22 did not respond. Check the instance status, security-group allowlist and network/VPN route, then retry.'
            }
            'ssh_connection_refused' {
                ' ECS SSH port 22 refused the connection. Check that the instance is running and its SSH service is listening.'
            }
            'ssh_network_unreachable' {
                ' No network route to ECS SSH port 22 is available. Check the local network and VPN routing.'
            }
            'ssh_connection_reset' {
                ' The ECS SSH connection was reset before the tunnel was ready. Check network/VPN routing and the server SSH service.'
            }
            'ssh_connection_closed' {
                ' The ECS SSH connection was closed before the tunnel was ready. Check network/VPN routing and the server SSH service.'
            }
            default { '' }
        }
        throw ('SSH connection: ' + $connectionError + $hint)
    }
    Write-Host 'ECS tunnel ready: 127.0.0.1:8765'
    if ($ExpectedPlayers -eq 1) {
        try { $hammer = Get-HammerBackendStatus }
        catch { throw 'HAMMER_BACKEND_STATUS_FAILED: the local automatic helper could not be identified. Run tools/setup_hammer_backend.ps1 -Action Status before retrying; the current game was preserved.' }
        if ($hammer.helper_running -or ($hammer.task_installed -and $hammer.task_enabled -and
            $hammer.task_state -in @('Running','Queued'))) {
            # Remember the owned helper's prior state before Stop, which can
            # disable a task or write STOP even if draining later fails.
            $resumeHammer = $hammer
            try {
                $global:LASTEXITCODE = 0
                & (Join-Path $PSScriptRoot 'setup_hammer_backend.ps1') -Action Stop | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'bridge_stop_failed' }
            } catch {
                throw 'HAMMER_BACKEND_PAUSE_FAILED: the automatic helper could not release the developer console. No game was started or credentials applied by this launcher. Resolve tools/setup_hammer_backend.ps1 -Action Stop before retrying.'
            }
            Write-Host 'HAMMER_BACKEND_PAUSED_FOR_AUTH: the automatic helper released the developer console for this launcher.'
        }
    }
    $games = @(Get-Process -Name dota2 -ErrorAction SilentlyContinue)
    $startedGame = $games.Count -eq 0
    if ($startedGame) {
        if ($AttachOnly) { throw 'Open the survival Workshop Tools game first.' }
        $engineGame = (Resolve-Path (Join-Path $repo '../..')).Path
        $executable = Join-Path $engineGame 'bin/win64/dota2.exe'
        if (-not (Test-Path -LiteralPath $executable)) { throw 'Dota 2 executable was not found.' }
        if (-not (Test-Path -LiteralPath (Join-Path $repo 'maps/template_map.vpk'))) {
            throw 'Compile template_map before launching the test game.'
        }
        # This is the interactive gameplay launcher, so the game window is visible.
        Start-Process -FilePath $executable -WorkingDirectory (Join-Path $engineGame 'dota') -WindowStyle Normal -ArgumentList @(
            '-tools', '-noassetbrowser', '-addon', 'survival', '-dev', '-condebug', '-novid',
            '+sv_cheats', '1', '+host_timescale', '1', '+r_drawpanorama', '1',
            '+dota_launch_custom_game', 'survival', 'template_map'
        )
    } else {
        Write-Host 'Attaching to the current game; its map and match will be preserved.'
        Write-Host 'If this is the ordinary Dota main menu, exit Dota and run launch_aliyun_test_game.cmd again to start the survival Tools game.'
    }
    Write-Host 'Waiting for the normal survival/template_map Tools server...'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $ready = $false
    $lastWaitError = ''
    $nextWaitUpdate = 0
    $emptyToolsChecked = $false
    do {
        $probe = Invoke-Check $auth 'probe'
        if ($probe.ok) { $ready = $true; break }
        if ($probe.error -notin @('tools_console_unavailable', 'tools_server_confirmation_missing')) {
            throw ('Game connection: ' + $probe.error)
        }
        if (@(Get-Process -Name dota2 -ErrorAction SilentlyContinue).Count -eq 0) {
            throw 'GAME_CLIENT_EXITED: Dota closed before the test map was ready. Keep Steam running, then retry launch_aliyun_test_game.cmd. The ECS tunnel is already connected.'
        }
        if (-not $startedGame -and -not $AttachOnly -and -not $emptyToolsChecked) {
            $emptyTools = Invoke-Check $auth 'start-empty'
            if ($emptyTools.ok) {
                $emptyToolsChecked = $true
                Write-Host 'EMPTY_TOOLS_CHECKED: an idle Tools world was asked to open template_map; any active map was preserved.'
            } elseif ($emptyTools.error -notin @('tools_console_unavailable', 'tools_server_confirmation_missing')) {
                throw ('Game preparation: ' + $emptyTools.error)
            }
        }
        if ($probe.error -ne $lastWaitError -or $timer.Elapsed.TotalSeconds -ge $nextWaitUpdate) {
            $stage = if ($probe.error -eq 'tools_console_unavailable') {
                'Waiting for the Workshop Tools console. Check the Dota window; if VConsole is connected, disconnect it while this launcher runs.'
            } else {
                'The test map has not confirmed readiness. Check whether Dota is still loading, in its main menu, or its developer console is busy.'
            }
            Write-Host ('GAME_WAITING: {0}s/{1}s. {2}' -f [int]$timer.Elapsed.TotalSeconds, $WaitSeconds, $stage)
            $lastWaitError = $probe.error
            $nextWaitUpdate = $timer.Elapsed.TotalSeconds + 15
        }
        Start-Sleep -Seconds 2
    } while ($timer.Elapsed.TotalSeconds -lt $WaitSeconds)
    if (-not $ready) {
        $hint = if ($startedGame) {
            'The launcher started Dota, but loading or the developer console did not become ready. Check the visible game window and disconnect VConsole if it owns the console connection. If the map is still loading, rerun this launcher to keep waiting without restarting it.'
        } else {
            'Dota was already running, so this launcher preserved its current map. If it is in the ordinary main menu or another map, exit Dota yourself, then double-click launch_aliyun_test_game.cmd to start the correct test game.'
        }
        throw ('GAME_MAP_WAIT_TIMEOUT: survival/template_map was not confirmed within {0} seconds (last status: {1}). {2} The ECS tunnel is connected; no game was closed or map replaced.' -f $WaitSeconds, $lastWaitError, $hint)
    }
    if ($ExpectedPlayers -gt 1) {
        Write-Host ('LAN_WAITING_PLAYERS: expected ' + $ExpectedPlayers + '. Clients join this host; do not launch separate maps. Authentication waits until everyone joins.')
        $joinTimer = [Diagnostics.Stopwatch]::StartNew()
        $arrived = $false
        $lastCount = -1
        do {
            $roster = Invoke-Check (Join-Path $PSScriptRoot 'aliyun_lan_probe.py') 'probe'
            if (-not $roster.ok) {
                if ($roster.error -eq 'lan_session_already_authenticated_restart_without_bridge') {
                    $reason = switch ($roster.reason) {
                        'credential_already_present' { 'credential_already_present: this game already has a backend credential configured.' }
                        'admission_already_released' { 'admission_already_released: this game has already passed its loading/admission gate.' }
                        default { 'This game was already configured or released before the LAN wait.' }
                    }
                    throw ('LAN roster: ' + $roster.error + '. ' + $reason + ' Fully exit the current Dota 2 game, then run launch_aliyun_lan_host.cmd again. Do not run the single-player launcher or restart the Hammer helper while waiting for players. The current map, profiles and credentials have not been reset.')
                }
                throw ('LAN roster: ' + $roster.error)
            }
            if ($roster.players -ne $lastCount) {
                $lastCount = $roster.players
                Write-Host ('LAN_PLAYERS: ' + $lastCount + '/' + $ExpectedPlayers)
            }
            if ($roster.status -eq 'waiting_players' -and $roster.players -ge $ExpectedPlayers) {
                $arrived = $true
                break
            }
            Start-Sleep -Seconds 2
        } while ($joinTimer.Elapsed.TotalSeconds -lt $JoinWaitSeconds)
        if (-not $arrived) { throw 'LAN join timed out. No credentials were applied by this launcher; the current map was preserved.' }
    }
    $applied = Invoke-Check $auth 'inject'
    if (-not $applied.ok) { throw ('Game authentication: ' + $applied.error) }
    Write-Host 'GAME_AUTH_READY: backend credential applied; existing profiles preserved.'
    Write-Host 'In the party waiting room, the host must click Start loading after everyone joins.'
    Write-Host 'No password is required. The SSH tunnel remains active after this window closes.'
} catch {
    $launchFailed = $true
    throw
} finally {
    try {
        if ($resumeHammer) {
            try { Restore-HammerBackend $resumeHammer }
            catch {
                $resumeHint = if ($resumeHammer.task_installed -and $resumeHammer.task_enabled) {
                    'Run tools/setup_hammer_backend.ps1 -Action Start to restore it.'
                } else {
                    'Check this addon''s output/hammer_backend/bridge.stop first; do not clear an invalid marker blindly. Then run tools/run_hammer_backend.ps1 to restore the standalone helper; its scheduled task remains disabled or uninstalled.'
                }
                $message = 'HAMMER_BACKEND_RESUME_FAILED: the previous automatic helper could not be restored. The game, profiles and SSH tunnel were preserved. ' + $resumeHint
                Write-Host $message
                # A restore error must not replace the original launch/auth error.
                if (-not $launchFailed) { throw $message }
            }
        }
    } finally {
        Pop-Location
    }
}
