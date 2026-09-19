$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $root 'scripts/vscripts/systems/challenge_session_service.lua') -Raw
$locations = Get-Content -LiteralPath (Join-Path $root 'scripts/vscripts/config/generated/challenge_locations.lua') -Raw

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Check ($locations.Contains('location_id = "challenge_06_room"')) 'ICE_LOCATION_MISSING'
Check ($locations.Contains('location_id = "challenge_07_room"')) 'MOLTEN_LOW_LOCATION_MISSING'
Check ($locations.Contains('room_radius = 1200')) 'CHALLENGE_ROOM_RADIUS_MISSING'
Check ($source.Contains('spread_maintain_count_position')) 'MAINTAIN_SPAWN_SPREAD_FUNCTION_MISSING'
Check ($source.Contains('location.room_radius')) 'ROOM_RADIUS_NOT_USED_FOR_SPAWN_SPREAD'
Check ($source.Contains('(tonumber(location.room_radius) or 1200) * 0.5')) 'SPAWN_RADIUS_NOT_HALVED'
Check ($source.Contains('session.spawn_serial')) 'SPAWN_SERIAL_NOT_USED'
Check ($source.Contains('GridNav:IsTraversable(candidate)')) 'SPAWN_TRAVERSABILITY_CHECK_MISSING'
Check ($source.Contains('member.spawn_mode ~= "maintain_count"')) 'SPAWN_MODE_GUARD_MISSING'
Check ($source.Contains('session.challenge.challenge_id == "challenge_10"')) 'TEN_SINS_EXCEPTION_MISSING'

Write-Output 'CHALLENGE_MAINTAIN_SPAWN_CONTRACT_PASS'