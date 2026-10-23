param([string]$ContextPath = (Join-Path $PSScriptRoot 'join_network_context.json'))
$ErrorActionPreference = 'Stop'
$revision = 'WS4-NET-01'
$kind = 'WS4-NETWORK-DIAGNOSTIC'
$maximumContextBytes = 65536
$maximumLogBytes = 4 * 1024 * 1024
$reportDirectory = $null
$runId = $null
$server = $null

function Need($Value, [string]$Code) { if (-not $Value) { throw $Code } }
function Local-Path([string]$Path) {
    Need ($Path.Length -gt 0 -and $Path.Length -le 4096) 'network_path_invalid'
    $normal = $Path.Replace('/','\')
    Need ($normal -match '^[A-Za-z]:\\' -and $normal -notmatch '[\x00-\x1f]') 'network_path_invalid'
    $full = [IO.Path]::GetFullPath($normal)
    $comparison = $normal.TrimEnd('\')
    if ($comparison.Length -eq 2) { $comparison += '\' }
    Need ([string]::Equals($full.TrimEnd('\'),$comparison.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) 'network_path_invalid'
    return $full
}
function IO-Path([string]$Path) { return '\\?\' + $Path.Replace('/','\') }
function Plain-Path([string]$Path) {
    $io = IO-Path $Path
    $attributes = [IO.File]::GetAttributes($io)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $entry = New-Object IO.DirectoryInfo($io) }
    else { $entry = New-Object IO.FileInfo($io) }
    while ($entry) {
        Need (([IO.File]::GetAttributes($entry.FullName) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'network_linked_path'
        if ($entry -is [IO.FileInfo]) { $entry = $entry.Directory } else { $entry = $entry.Parent }
    }
    return $attributes
}
function Existing-Path([string]$Path) {
    try { [IO.File]::GetAttributes((IO-Path $Path)) | Out-Null; return $true }
    catch {
        $type = $_.Exception.GetBaseException().GetType().FullName
        if ($type -match '(File|Directory)NotFoundException$') { return $false }
        throw
    }
}
function UTC-Time($Value) {
    Need ($Value -is [string] -and $Value.Length -le 40 -and $Value -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|\+00:00)$') 'network_context_invalid'
    $date = [DateTimeOffset]::MinValue
    Need ([DateTimeOffset]::TryParse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)) 'network_context_invalid'
    Need ($date.Offset -eq [TimeSpan]::Zero) 'network_context_invalid'
    return $date.UtcDateTime
}
function Read-Context([string]$Path) {
    $attributes = Plain-Path $Path
    Need (($attributes -band [IO.FileAttributes]::Directory) -eq 0) 'network_context_invalid'
    $stream = [IO.File]::Open((IO-Path $Path),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        Need ($stream.Length -gt 0 -and $stream.Length -le $maximumContextBytes) 'network_context_too_large'
        $buffer = New-Object byte[] ([int]$stream.Length)
        $count = 0
        while ($count -lt $buffer.Length) {
            $read = $stream.Read($buffer,$count,$buffer.Length-$count)
            Need ($read -gt 0) 'network_context_invalid'
            $count += $read
        }
        $encoding = New-Object Text.UTF8Encoding($false,$true)
        $raw = $encoding.GetString($buffer).TrimStart([char]0xfeff)
        return ($raw | ConvertFrom-Json)
    } finally { $stream.Dispose() }
}
function Write-Report($Report) {
    $encoded = $Report | ConvertTo-Json -Depth 5 -Compress
    if ($reportDirectory) {
        $output = Join-Path $reportDirectory 'join_network_diagnostic.json'
        Plain-Path $reportDirectory | Out-Null
        if (Existing-Path $output) {
            $attributes = Plain-Path $output
            Need (($attributes -band [IO.FileAttributes]::Directory) -eq 0) 'network_report_path_invalid'
        }
        [IO.File]::WriteAllText((IO-Path $output),$encoded,(New-Object Text.UTF8Encoding($false)))
    }
    return $encoded
}

# Fixed native enum allowlist. Unknown strings are never echoed as reason codes.
$knownCodes = @{}
@'
BADDELTATICK BADRELAYPASSWORD BADSPECTATORPASSWORD BAD_SERVER_PASSWORD BANADDED
CLIENT_CONSISTENCY_FAIL CLIENT_DIFFERENT_MAP CLIENT_NO_MAP CLIENT_UNABLE_TO_CRC_MAP
CONNECTION_FAILURE CONNECT_REQUEST_TIMEDOUT CREATE_SERVER_FAILED DELTAENTMSG_OVERFLOW
DIFFERENTCLASSTABLES DIRECT_CONNECT_RESERVATION DISCONNECTED DISCONNECT_BY_SERVER
DISCONNECT_BY_USER EXITING HLTVDIRECT HLTVRESTRICTED HLTVSTOP HLTVUNAVAILABLE HOST_ENDGAME
INTERNAL_ERROR INVALID INVALID_MESSAGE_ERROR KICKBANADDED KICKED KICKED_COMPETITIVECOOLDOWN
KICKED_CONVICTEDACCOUNT KICKED_HOSTAGEKILLING KICKED_IDLE KICKED_INPUTAUTOMATION
KICKED_INSECURECLIENT KICKED_NOSTEAMLOGIN KICKED_NOSTEAMTICKET KICKED_SUICIDE KICKED_TEAMHURTING
KICKED_TEAMKILLING KICKED_TK_START KICKED_UNTRUSTEDACCOUNT KICKED_VACNETABNORMALBEHAVIOR
KICKED_VOTEDOFF LEAVINGSPLIT LOCALPROBLEM_HOSTEDSERVERPRIMARYRELAY LOCALPROBLEM_MANYRELAYS
LOCALPROBLEM_NETWORKCONFIG LOCALPROBLEM_OTHER LOOPDEACTIVATE LOOPSHUTDOWN LOOP_LEVELLOAD_ACTIVATE
LOST MESSAGE_PARSE_ERROR NOMORESPLITS NOSPECTATORS NO_PEER_GROUP_HANDLERS OVERFLOW
PURESERVER_CLIENTEXTRA PURESERVER_MISMATCH RECONNECTION REJECT REJECTED_BY_GAME
REJECT_BACKGROUND_MAP REJECT_BADCHALLENGE REJECT_BADPASSWORD REJECT_BANNED REJECT_CONNECT_FROM_LOBBY
REJECT_FAILEDCHANNEL REJECT_HIDDEN_GAME REJECT_INVALIDCERTLEN REJECT_INVALIDCONNECTION
REJECT_INVALIDKEYLENGTH REJECT_INVALIDRESERVATION REJECT_INVALIDSTEAMCERTLEN REJECT_LANRESTRICT
REJECT_NEWPROTOCOL REJECT_NOLOBBY REJECT_OLDPROTOCOL REJECT_RESERVED_FOR_LOBBY
REJECT_SERVERAUTHDISABLED REJECT_SERVERCDKEYAUTHINVALID REJECT_SERVERFULL REJECT_SINGLE_PLAYER
REJECT_STEAM RELIABLEOVERFLOW REMOTE_BADCRYPT REMOTE_CERTNOTTRUSTED REMOTE_OTHER REMOTE_TIMEOUT
REMOTE_TIMEOUT_CONNECTING REPLAY_INCOMPATIBLE REQUEST_HOSTSTATE_HLTVRELAY REQUEST_HOSTSTATE_IDLE
SERVERINFO_OVERFLOW SERVER_INCOMPATIBLE SERVER_REQUIRES_STEAM SERVER_SHUTDOWN SHUTDOWN
SNAPSHOTERROR SNAPSHOTOVERFLOW SOUNDSMSG_OVERFLOW STEAM_AUTHALREADYUSED STEAM_AUTHCANCELLED
STEAM_AUTHINVALID STEAM_BANNED STEAM_DENY_BAD_ANTI_CHEAT STEAM_DENY_MISC STEAM_DROPPED STEAM_INUSE
STEAM_LOGGED_IN_ELSEWHERE STEAM_LOGON STEAM_OWNERSHIP STEAM_TICKET STEAM_VACBANSTATE
STEAM_VAC_CHECK_TIMEDOUT STRINGTABLEMSG_OVERFLOW TEMPENTMSG_OVERFLOW TICKMSG_OVERFLOW TIMEDOUT
UNUSUAL USERCMD
'@ -split '\s+' | Where-Object { $_ } | ForEach-Object { $knownCodes['NETWORK_DISCONNECT_' + $_] = $true }

function Native-Body([string]$Line) {
    if ($Line.Length -gt 16384) { return $null }
    $body = $Line.TrimStart([char]0xfeff).Trim()
    # Console timestamps and known native channels only; JSON/chat is not a diagnostic source.
    $body = $body -replace '^(?:\d{1,2}/\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?\s*|\[\d{2,4}[-/:. 0-9T]+\]\s*|\d{2}:\d{2}:\d{2}(?:\.\d+)?\s*)',''
    if ($body -match '(?i)(?:^|[\s\]])(?:say|say_team|chat|saytext2?|chatwheel)(?:[\s:\[]|$)') { return $null }
    $native = $false
    for ($index=0; $index -lt 4; $index++) {
        if ($body -match '^\[(?:Networking|NetSteamConn|SteamNetSockets|Client|Server|Engine|EngineServiceManager|SignonState)\]\s*') {
            $body = $body.Substring($Matches[0].Length); $native = $true
        } elseif ($body -match '^(?:CL|SV|Client|Server):\s*') {
            $body = $body.Substring($Matches[0].Length); $native = $true
        } else { break }
    }
    if ($native) { $body = $body -replace '^\[#\d{1,12}[^\]\r\n]{0,240}\]\s*','' }
    if ($body.TrimStart().StartsWith('{') -or $body.TrimStart().StartsWith('[')) { return $null }
    if (-not $native -and $body -notmatch '^(?:NETWORK_DISCONNECT_[A-Z0-9_]+\b|Disconnect(?:ed|ing)?\b|Connection\b|Closing\b|Mismatch addon\b|map template_map:|Retrying connection\b|Connecting to\b|Connected\b|Sending C2S_CONNECT\b|Received S2C_CONNECTION\b)') { return $null }
    return $body
}

try {
    $contextFile = Local-Path $ContextPath
    Plain-Path $contextFile | Out-Null
    $reportDirectory = [IO.Path]::GetDirectoryName($contextFile)
    $context = Read-Context $contextFile
    Need ($context -is [PSCustomObject]) 'network_context_invalid'
    $allowed = @('schema','kind','revision','run_id','game_path','server','started_utc','dedicated_file','fallback_start_bytes','fallback_existed','fallback_last_write_utc')
    foreach ($property in $context.PSObject.Properties.Name) { Need ($allowed -contains $property) 'network_context_invalid' }
    Need (($context.schema -is [int] -or $context.schema -is [long]) -and $context.schema -eq 1 -and $context.kind -ceq 'WS4-NETWORK-CAPTURE' -and $context.revision -ceq 'WS4-JOIN-08') 'network_context_invalid'
    Need ($context.run_id -is [string] -and $context.run_id -cmatch '^[a-f0-9]{32}$') 'network_context_invalid'
    $runId = $context.run_id
    Need ($context.dedicated_file -is [string] -and $context.dedicated_file -ceq ('ws4_join_' + $runId + '.log')) 'network_context_invalid'
    Need ($context.server -is [string] -and $context.server -match '^(26\.\d{1,3}\.\d{1,3}\.\d{1,3}):27015$') 'network_context_invalid'
    $ip = [Net.IPAddress]::None
    $ipText = $Matches[1]
    Need ([Net.IPAddress]::TryParse($ipText,[ref]$ip) -and $ip.ToString() -ceq $ipText) 'network_context_invalid'
    $server = $context.server
    $started = UTC-Time $context.started_utc
    Need ($context.fallback_existed -is [bool]) 'network_context_invalid'
    Need (($context.fallback_start_bytes -is [int] -or $context.fallback_start_bytes -is [long]) -and $context.fallback_start_bytes -ge 0) 'network_context_invalid'
    $initialBytes = [long]$context.fallback_start_bytes
    $previousWrite = $null
    if ($context.fallback_existed) { $previousWrite = UTC-Time $context.fallback_last_write_utc }
    else { Need ($initialBytes -eq 0 -and $null -eq $context.fallback_last_write_utc) 'network_context_invalid' }
    Need ($context.game_path -is [string]) 'network_context_invalid'
    $game = Local-Path $context.game_path
    Need (((Plain-Path $game) -band [IO.FileAttributes]::Directory) -ne 0) 'network_game_path_invalid'
    $logRoot = Join-Path $game 'dota'
    Need (((Plain-Path $logRoot) -band [IO.FileAttributes]::Directory) -ne 0) 'network_game_path_invalid'
    $dedicated = Join-Path $logRoot $context.dedicated_file
    $fallback = Join-Path $logRoot 'console.log'
    $report = [ordered]@{schema=1;kind=$kind;revision=$revision;context_revision='WS4-JOIN-08';ok=$false;
        run_id=$runId;server=$server;log_source='none';fresh=$false;bytes=0;truncated=$false;
        status='reason_unknown';expected_target_seen=$false;disconnect_codes=@();reason_numbers=@();categories=@();
        counts=[ordered]@{lines=0;native_lines=0;oversized_lines=0;disconnect_codes=0;reason_numbers=0}}
    $selected = $null
    $startByte = [long]0
    $tryFallback = $true
    if (Existing-Path $dedicated) {
        Need (((Plain-Path $dedicated) -band [IO.FileAttributes]::Directory) -eq 0) 'network_log_path_invalid'
        $info = New-Object IO.FileInfo((IO-Path $dedicated))
        if ($info.LastWriteTimeUtc -ge $started -and $info.Length -gt 3) {
            $selected = $dedicated; $report.log_source = 'dedicated'; $tryFallback = $false
        } elseif ($info.Length -le 3) { $report.status = 'no_effective_log_bytes' }
        else { $report.status = 'log_not_fresh' }
    }
    if ($tryFallback -and (Existing-Path $fallback)) {
        Need (((Plain-Path $fallback) -band [IO.FileAttributes]::Directory) -eq 0) 'network_log_path_invalid'
        $info = New-Object IO.FileInfo((IO-Path $fallback))
        $report.log_source = 'console_increment'
        if ($info.Length -lt $initialBytes) { $report.truncated = $true; $report.status = 'fallback_truncated' }
        elseif ($info.Length -eq $initialBytes) { $report.status = 'no_new_log_bytes' }
        elseif ($info.LastWriteTimeUtc -lt $started -or ($previousWrite -and $info.LastWriteTimeUtc -le $previousWrite)) { $report.status = 'log_not_fresh' }
        else { $selected = $fallback; $startByte = $initialBytes }
    } elseif ($tryFallback -and $report.status -eq 'reason_unknown') { $report.status = 'log_not_created' }

    if ($selected) {
        $stream = [IO.File]::Open((IO-Path $selected),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try {
            $length = $stream.Length
            Need ($length -ge $startByte) 'network_log_changed_during_read'
            $offset = [Math]::Max($startByte,$length-$maximumLogBytes)
            $skipPartial = $offset -gt $startByte
            $report.truncated = $skipPartial
            $stream.Seek($offset,[IO.SeekOrigin]::Begin) | Out-Null
            $buffer = New-Object byte[] ([int]($length-$offset))
            $readBytes = 0
            while ($readBytes -lt $buffer.Length) {
                $amount = $stream.Read($buffer,$readBytes,$buffer.Length-$readBytes)
                if ($amount -le 0) { break }
                $readBytes += $amount
            }
        } finally { $stream.Dispose() }
        $report.bytes = $readBytes
        $text = [Text.Encoding]::UTF8.GetString($buffer,0,$readBytes)
        $report.fresh = $readBytes -gt 0 -and $text.TrimStart([char]0xfeff).Trim().Length -gt 0
        $report.ok = $report.fresh
        if ($skipPartial) {
            $newline = $text.IndexOf("`n")
            if ($newline -ge 0) { $text = $text.Substring($newline+1) } else { $text = '' }
        }
        $codes = @{}; $reasons = @{}; $categories = @{}
        $reader = New-Object IO.StringReader($text)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                $report.counts.lines++
                if ($line.Length -gt 16384) { $report.counts.oversized_lines++; continue }
                $body = Native-Body $line
                if ($null -eq $body) { continue }
                $report.counts.native_lines++
                $targetPattern = '(?<![0-9.])' + [regex]::Escape($server) + '(?![0-9])'
                if ($body -match '(?i)connect|server|remote|udp|address|challenge' -and $body -match $targetPattern) { $report.expected_target_seen = $true }
                $lineHasKnownCode = $false
                foreach ($match in [regex]::Matches($body,'\bNETWORK_DISCONNECT_[A-Z0-9_]{1,90}\b')) {
                    if ($knownCodes.ContainsKey($match.Value)) { $codes[$match.Value] = $true; $report.counts.disconnect_codes++; $lineHasKnownCode = $true }
                }
                if ($body -match '(?i)disconnect|connection|clos(?:e|ed|ing)|NETWORK_DISCONNECT_') {
                    foreach ($match in [regex]::Matches($body,'(?i)\b(?:reason|endreason|eend)\s*[:=]?\s*(-?\d{1,9})\b')) {
                        $reasons[[int]$match.Groups[1].Value] = $true; $report.counts.reason_numbers++
                    }
                    # Native Steam socket closure prints (2054 CODE) or (2054)
                    # CODE. Require a known enum on the same native line; handle
                    # #123 and Steam identifiers are not reason numbers.
                    if ($lineHasKnownCode) {
                        foreach ($match in [regex]::Matches($body,'\(\s*(-?\d{1,9})\s*(?:NETWORK_DISCONNECT_[A-Z0-9_]{1,90})?\s*\)')) {
                            $reasons[[int]$match.Groups[1].Value] = $true; $report.counts.reason_numbers++
                        }
                    }
                }
                if ($body -match '(?i)Mismatch addon.{0,160}CRC|CRC.{0,60}(?:mismatch|failed)|NETWORK_DISCONNECT_PURESERVER_MISMATCH') { $categories.addon_crc_mismatch = $true }
                if ($body -match '(?i)NETWORK_DISCONNECT_(?:REJECT_(?:OLD|NEW)PROTOCOL|SERVER_INCOMPATIBLE|DIFFERENTCLASSTABLES)|(?:version|protocol).{0,60}(?:mismatch|different|incompatible)') { $categories.version_mismatch = $true }
                if ($body -match '(?i)NETWORK_DISCONNECT_(?:STEAM_[A-Z_]+|REJECT_STEAM|SERVER_REQUIRES_STEAM|KICKED_NOSTEAM[A-Z_]+)|(?:Steam|auth).{0,50}(?:ticket|invalid|rejected|failed|canceled)') { $categories.steam_authentication = $true }
                if ($body -match '(?i)NETWORK_DISCONNECT_(?:DIRECT_CONNECT_RESERVATION|REJECT_(?:INVALIDRESERVATION|RESERVED_FOR_LOBBY|NOLOBBY|CONNECT_FROM_LOBBY))|requires lobby reservation|reserved for lobby') { $categories.lobby_reservation = $true }
                if ($body -match '(?i)map template_map:\s*invalid map name|(?:could not|couldn.t|cannot|unable to).{0,20}(?:find|load|open).{0,20}map|NETWORK_DISCONNECT_CLIENT_(?:NO_MAP|UNABLE_TO_CRC_MAP)') { $categories.map_missing = $true }
                if ($body -match '(?i)NETWORK_DISCONNECT_[A-Z_]*(?:TIMEOUT|TIMEDOUT)|\b(?:timed out|connection timeout)\b') { $categories.timeout = $true }
                if ($body -match '(?i)NETWORK_DISCONNECT_REJECT_SERVERFULL|\bserver (?:is )?full\b') { $categories.server_full = $true }
                if ($body -match '(?i)NETWORK_DISCONNECT_REJECTED_BY_GAME|Connection rejected by game') { $categories.game_rejected = $true }
            }
        } finally { $reader.Dispose() }
        $report.disconnect_codes = @($codes.Keys | Sort-Object)
        $report.reason_numbers = @($reasons.Keys | Sort-Object)
        $report.categories = @($categories.Keys | Sort-Object)
        if ($codes.Count -gt 0 -or $reasons.Count -gt 0 -or $categories.Count -gt 0) { $report.status = 'native_reason_observed' }
    }
    if (-not $report.fresh) {
        $report.next_step = 'exit_guest_dota_normally_then_collect_again'
        Write-Host 'No fresh native output. Exit guest Dota normally, keep Steam/VPN running, then run collect_network.cmd again.'
    }
    Write-Report $report
    exit 0
} catch {
    $code = 'network_capture_failed'
    $allowedErrors = @('network_path_invalid','network_linked_path','network_context_invalid','network_context_too_large',
        'network_game_path_invalid','network_log_path_invalid','network_report_path_invalid','network_log_changed_during_read')
    if ($allowedErrors -contains $_.Exception.Message) { $code = $_.Exception.Message }
    $failure = [ordered]@{schema=1;kind=$kind;revision=$revision;ok=$false;error=$code}
    if ($runId) { $failure.run_id = $runId }
    if ($server) { $failure.server = $server }
    try { Write-Report $failure }
    catch { $failure | ConvertTo-Json -Compress }
    exit 1
}
