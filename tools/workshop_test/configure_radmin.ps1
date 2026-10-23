param([string[]]$PeerAddress = @('26.0.0.0/8'), [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$game = Split-Path (Split-Path $repo)
$exe = Join-Path $game 'bin/win64/dota2.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'dota_executable_missing' }
$ips = @(Get-NetIPAddress -InterfaceAlias 'Radmin VPN' -AddressFamily IPv4 -ErrorAction Stop | Where-Object {$_.IPAddress -match '^26\.'})
if ($ips.Count -ne 1) { throw 'radmin_address_not_ready' }
foreach ($peer in $PeerAddress) {
    $parsed = [Net.IPAddress]::None
    if ($peer -ne '26.0.0.0/8' -and (-not [Net.IPAddress]::TryParse($peer,[ref]$parsed) -or $parsed.ToString() -ne $peer -or $peer -notmatch '^26\.')) { throw 'radmin_peer_address_invalid' }
}
$group = 'Survival WS4 controlled test network'
$rules = @(
    @{Name='Survival-WS4-Radmin-Game';Action='Allow';Protocol='UDP';LocalPort=@('27015');RemoteAddress=$PeerAddress},
    @{Name='Survival-WS4-Radmin-Tools-Blocked';Action='Block';Protocol='TCP';LocalPort=@('24981','29000','29003');RemoteAddress=@('26.0.0.0/8')}
)
foreach ($spec in $rules) {
    $existing = Get-NetFirewallRule -Name $spec.Name -ErrorAction SilentlyContinue
    if ($existing -and $existing.Group -ne $group) { throw 'unowned_firewall_rule_name' }
    if (-not $CheckOnly) {
        if ($existing) {
            $existing | Set-NetFirewallRule -Enabled True -Action $spec.Action -Profile Any -InterfaceAlias 'Radmin VPN' -Program $exe -Protocol $spec.Protocol -LocalPort $spec.LocalPort -LocalAddress $ips[0].IPAddress -RemoteAddress $spec.RemoteAddress | Out-Null
        } else {
            New-NetFirewallRule -Name $spec.Name -DisplayName $spec.Name -Group $group -Direction Inbound -Enabled True -Action $spec.Action -Profile Any -InterfaceAlias 'Radmin VPN' -Program $exe -Protocol $spec.Protocol -LocalPort $spec.LocalPort -LocalAddress $ips[0].IPAddress -RemoteAddress $spec.RemoteAddress | Out-Null
        }
    }
}
@{ok=$true;host_address=$ips[0].IPAddress;game_udp_port=27015;allowed_peers=$PeerAddress;check_only=[bool]$CheckOnly;remote_tools_ports_blocked=@(24981,29000,29003)} | ConvertTo-Json -Compress
