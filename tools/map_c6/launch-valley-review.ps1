$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$out = Join-Path $repo 'output/valley_decor_v2'
New-Item -ItemType Directory -Force $out | Out-Null
$client = Join-Path $PSScriptRoot 'console.cjs'
function Show-ReviewWindow {
    for ($focusAttempt = 0; $focusAttempt -lt 3; $focusAttempt++) {
        try { & (Join-Path $PSScriptRoot 'window.ps1') -Show -CenterPointer | Out-Null; return }
        catch { if ($focusAttempt -eq 2) { throw }; Start-Sleep -Milliseconds 500 }
    }
}
if (-not (Test-Path (Join-Path $repo 'maps/valley_decor_review.vpk'))) { throw 'Build the valley review map first.' }
$games = @(Get-CimInstance Win32_Process -Filter "name='dota2.exe'")
if ($games | Where-Object { $_.CommandLine -notmatch '-addon\s+survival(?:\s|$)' }) {
    throw 'Close the other Dota instance before opening this project preview.'
}
if ($games.Count -eq 0) {
    Start-Process (Join-Path $engine 'game/bin/win64/dota2.exe') -ArgumentList '-tools -noassetbrowser -addon survival -dev -condebug -novid -windowed -w 1600 -h 900 +dota_launch_custom_game survival valley_decor_review' -WorkingDirectory (Join-Path $engine 'game/dota') -WindowStyle Normal
} else {
    & node $client 'host_timescale 1; dota_launch_custom_game survival valley_decor_review' 1500 | Out-File (Join-Path $out 'launch.log')
    if ($LASTEXITCODE -ne 0) { throw 'Could not connect to Workshop console.' }
}
$ready = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    # A loading server may not answer yet; Windows PowerShell treats native
    # stderr as an ErrorRecord, so preserve the intended bounded retry.
    $ErrorActionPreference = 'Continue'
    & node $client 'script_reload_code tools/valley_review' --expect VALLEY_REVIEW_READY --timeout-ms 2500 *> (Join-Path $out 'runtime.log')
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { throw 'Review map did not finish loading; see output/valley_decor_v2/runtime.log.' }
Start-Sleep -Seconds 3
Show-ReviewWindow
$commands = "sv_cheats 1`nhost_timescale 1`nfog_enable 0`nfog_enableskybox 0`ndota_camera_distance 2400`ndota_camera_set_lookatpos 340 4920`nr_drawpanorama 0`nbind F6 `"dota_camera_distance 1600; dota_camera_set_lookatpos 476 5266`"`nbind F7 `"dota_camera_distance 2400; dota_camera_set_lookatpos 340 4920`"`nbind F8 `"dota_camera_distance 6800; dota_camera_set_lookatpos -1024 4096`"`nbind F9 `"dota_camera_distance 1250; dota_camera_set_lookatpos -1024 5190`"`nhideconsole"
$request = Join-Path $out 'review_camera.json'
[IO.File]::WriteAllText($request, (ConvertTo-Json -Depth 5 -InputObject @(@{name='console_send';arguments=@{commands=($commands + "`ndota_camera_get_lookatpos`necho VALLEY_CAMERA_READY")}})))
& node $client --file $request --delay-ms 150 --timeout-ms 3000 --expect VALLEY_CAMERA_READY *> (Join-Path $out 'review_camera.log')
if ($LASTEXITCODE -ne 0) { throw 'Camera setup failed.' }
Show-ReviewWindow
Write-Host 'Valley V2 ready. F6: ground details. F7: close view. F8: overview. F9: spawn arch. Main map unchanged.'
