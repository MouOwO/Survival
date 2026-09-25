param(
    [switch]$AttachOnly,
    [ValidateRange(10,600)][int]$WaitSeconds = 180,
    [ValidateRange(1,4)][int]$ExpectedPlayers = 1,
    [ValidateRange(10,1800)][int]$JoinWaitSeconds = 600
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$python = Join-Path $repo 'output/ecs_backend_work/.venv/Scripts/python.exe'
$tunnel = Join-Path $PSScriptRoot 'aliyun_test_connection.py'
$auth = Join-Path $PSScriptRoot 'aliyun_game_test_auth.py'
if (-not (Test-Path -LiteralPath $python)) { throw 'The local deployment Python environment is missing.' }

function Invoke-Check([string]$Script, [string]$Action) {
    # These helpers emit fixed status codes; credentials never enter arguments.
    $outputLines = @(& $python -B $Script $Action)
    $exitCode = $LASTEXITCODE
    try { $result = ($outputLines -join "`n") | ConvertFrom-Json }
    catch { throw 'The test connection helper did not return a status.' }
    if ($exitCode -ne 0 -and $result.ok) { throw 'The test connection helper failed.' }
    return $result
}

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
    if (-not $connected.ok) { throw ('SSH connection: ' + $connected.error) }
    Write-Host 'ECS tunnel ready: 127.0.0.1:8765'
    $games = @(Get-Process -Name dota2 -ErrorAction SilentlyContinue)
    if ($games.Count -eq 0) {
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
            '+host_timescale', '1', '+r_drawpanorama', '1',
            '+dota_launch_custom_game', 'survival', 'template_map'
        )
    } else {
        Write-Host 'Attaching to the current game; its map and match will be preserved.'
    }
    Write-Host 'Waiting for the normal survival/template_map Tools server...'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $ready = $false
    do {
        $probe = Invoke-Check $auth 'probe'
        if ($probe.ok) { $ready = $true; break }
        if ($probe.error -notin @('tools_console_unavailable', 'tools_server_confirmation_missing')) {
            throw ('Game connection: ' + $probe.error)
        }
        Start-Sleep -Seconds 2
    } while ($timer.Elapsed.TotalSeconds -lt $WaitSeconds)
    if (-not $ready) {
        throw 'Normal template_map is not ready. Open Workshop Tools survival, then run: host_timescale 1; r_drawpanorama 1; dota_launch_custom_game survival template_map'
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
} finally {
    Pop-Location
}
