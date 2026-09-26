param(
    [string]$ServerAddress,
    [ValidateRange(1,65535)][int]$Port = 27015,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ServerAddress)) {
    $ServerAddress = Read-Host 'Host LAN IPv4 (example: 192.168.1.170)'
}
# Only canonical IPv4 literals: never accept console commands or switches.
if ($ServerAddress -notmatch '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') {
    throw 'INVALID_HOST_IPV4'
}
$ip = $null
if (-not [Net.IPAddress]::TryParse($ServerAddress, [ref]$ip) -or
    $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
    $ip.ToString() -cne $ServerAddress -or
    $ip.GetAddressBytes()[0] -eq 0 -or $ip.GetAddressBytes()[0] -ge 224 -or
    [Net.IPAddress]::IsLoopback($ip)) {
    throw 'INVALID_HOST_IPV4'
}
$engineGame = (Resolve-Path (Join-Path $repo '../..')).Path
$executable = Join-Path $engineGame 'bin/win64/dota2.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'DOTA_EXECUTABLE_MISSING' }
if (-not (Test-Path -LiteralPath (Join-Path $repo 'maps/template_map.vpk') -PathType Leaf)) {
    throw 'COMPILED_MAP_MISSING'
}
$target = '{0}:{1}' -f $ip.ToString(), $Port
# Keep Tools/addon mode identical to the existing test client, but never create
# a local map before joining. This isolates local-to-remote map teardown.
$launchArgs = @('-tools', '-noassetbrowser', '-addon', 'survival', '-dev',
    '-condebug', '-novid', '+connect', $target)
if ($DryRun) {
    [pscustomobject]@{mode='cold_client_join'; target=$target; arguments=$launchArgs} | ConvertTo-Json
    return
}
if (@(Get-Process -Name dota2 -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'DOTA_ALREADY_RUNNING: Save any Hammer work, then fully exit Dota/Tools on this joining PC before retrying. Nothing was closed by this script.'
}
Write-Host ('JOIN_STARTING: ' + $target)
Write-Host 'No local match, SSH tunnel or backend authentication is created on this joining PC.'
Start-Process -FilePath $executable -WorkingDirectory (Join-Path $engineGame 'dota') -WindowStyle Normal -ArgumentList $launchArgs
Write-Host 'CLIENT_LAUNCHED: connection and successful map loading still require in-game verification.'
