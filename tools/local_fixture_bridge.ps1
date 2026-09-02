<#
    Local JSON bridge for the Dota VScript mock profile provider.

    VScript deliberately has no Lua file I/O, so the game emits lines with the
    PERSIST_BRIDGE marker. Run this process while Workshop Tools is running;
    it tails console.log and applies only those machine-readable snapshots to
    data/mock/player_profiles.json. This is a local test substitute only.

    Start:
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\local_fixture_bridge.ps1

    Dota must be launched with -condebug so its console output is written to
    game\dota\console.log.
#>
[CmdletBinding()]
param(
    [string]$LogPath,
    [string]$FixturePath,
    [string]$LuaFixturePath
)

$addonRoot = Split-Path -Parent $PSScriptRoot
$gameRoot = Split-Path -Parent (Split-Path -Parent $addonRoot)
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $gameRoot "dota\console.log"
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
    $FixturePath = Join-Path $addonRoot "data\mock\player_profiles.json"
}
if ([string]::IsNullOrWhiteSpace($LuaFixturePath)) {
    $LuaFixturePath = Join-Path $addonRoot "scripts\vscripts\config\fixtures\player_profiles.lua"
}

function Write-BridgeLog([string]$Message) {
    Write-Host ("[{0}] [LocalFixtureBridge] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

function Write-TextAtomically([string]$Path, [string]$Text) {
    $tempPath = "{0}.bridge.{1}.tmp" -f $Path, $PID
    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    try {
        [System.IO.File]::WriteAllText($tempPath, $Text, $utf8)
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($tempPath, $Path, $null)
        } else {
            [System.IO.File]::Move($tempPath, $Path)
        }
    } finally {
        if ([System.IO.File]::Exists($tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-FixtureFiles($Data) {
    $json = $Data | ConvertTo-Json -Depth 100
    Write-TextAtomically $FixturePath $json

    # VScript cannot read JSON directly when io.open is unavailable. Keep the
    # generated Lua wrapper in sync so the next addon restart can require it.
    $escaped = $json.Replace('\', '\\').Replace('"', '\"')
    $escaped = $escaped.Replace("`r", '\r').Replace("`n", '\n')
    $lua = "-- AUTO-GENERATED. Local bridge output; source JSON is authoritative.`n"
        + "local M = {}`n"
        + "M.json = `"$escaped`"`n"
        + "return M`n"
    Write-TextAtomically $LuaFixturePath $lua
}

function Set-GameplayStatsSnapshot($Payload) {
    if ([string]::IsNullOrWhiteSpace([string]$Payload.account_id)) {
        Write-BridgeLog "忽略无 account_id 的桥接事件"
        return
    }
    if ($null -eq $Payload.gameplay_stats -or $null -eq $Payload.revision) {
        Write-BridgeLog "忽略不完整桥接事件 account=$($Payload.account_id)"
        return
    }

    $data = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    $profileProperty = $data.profiles.PSObject.Properties[[string]$Payload.account_id]
    $profile = if ($null -ne $profileProperty) { $profileProperty.Value } else { $null }
    if ($null -eq $profile) {
        Write-BridgeLog "找不到档案 account=$($Payload.account_id)"
        return
    }
    $currentRevision = [int64]($profile.revision | ForEach-Object { $_ })
    $incomingRevision = [int64]$Payload.revision
    if ($incomingRevision -le $currentRevision) {
        Write-BridgeLog "跳过旧事件 account=$($Payload.account_id) revision=$incomingRevision current=$currentRevision"
        return
    }

    if ($null -eq $profile.save) {
        $profile | Add-Member -MemberType NoteProperty -Name save -Value ([pscustomobject]@{})
    }
    $statsProperty = $profile.save.PSObject.Properties["gameplay_stats"]
    if ($null -eq $statsProperty) {
        $profile.save | Add-Member -MemberType NoteProperty -Name gameplay_stats -Value $Payload.gameplay_stats
    } else {
        $profile.save.gameplay_stats = $Payload.gameplay_stats
    }
    if ([string]$Payload.gameplay_stats_mode -eq "isolated_test") {
        $profile.gameplay_stats_mode = "isolated_test"
    } elseif ($profile.PSObject.Properties.Name -contains "gameplay_stats_mode") {
        $profile.PSObject.Properties.Remove("gameplay_stats_mode")
    }
    $profile.revision = $incomingRevision
    Write-FixtureFiles $data
    Write-BridgeLog "已写入 JSON 与 Lua fixture account=$($Payload.account_id) revision=$incomingRevision fields=$(@($Payload.gameplay_stats.PSObject.Properties).Count)"
}

if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    throw "Fixture 文件不存在：$FixturePath"
}
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    Write-BridgeLog "等待日志文件：$LogPath"
    while (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        Start-Sleep -Milliseconds 500
    }
}

Write-BridgeLog "启动；log=$LogPath fixture=$FixturePath lua_fixture=$LuaFixturePath"
$stream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$reader = New-Object System.IO.StreamReader($stream)
$stream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
try {
    while ($true) {
        while ($null -ne ($line = $reader.ReadLine())) {
            $marker = "PERSIST_BRIDGE "
            $markerIndex = $line.IndexOf($marker, [System.StringComparison]::Ordinal)
            if ($markerIndex -lt 0) { continue }
            $payloadText = $line.Substring($markerIndex + $marker.Length).Trim()
            try {
                $payload = $payloadText | ConvertFrom-Json
                Set-GameplayStatsSnapshot $payload
            } catch {
                Write-BridgeLog "处理桥接事件失败：$($_.Exception.Message)"
            }
        }
        Start-Sleep -Milliseconds 200
        $reader.DiscardBufferedData()
        $stream.Seek(0, [System.IO.SeekOrigin]::Current) | Out-Null
    }
} finally {
    $reader.Dispose()
    $stream.Dispose()
}
