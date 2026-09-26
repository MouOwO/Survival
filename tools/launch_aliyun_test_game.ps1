param(
    [switch]$AttachOnly,
    [ValidateRange(10,600)][int]$WaitSeconds = 180
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

Push-Location $repo
try {
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
    $applied = Invoke-Check $auth 'inject'
    if (-not $applied.ok) { throw ('Game authentication: ' + $applied.error) }
    Write-Host 'GAME_AUTH_READY: missing profiles requested; loaded profiles preserved.'
    Write-Host 'No password is required. The SSH tunnel remains active after this window closes.'
} finally {
    Pop-Location
}
