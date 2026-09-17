$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $root 'scripts/vscripts/systems/building_system.lua') -Raw
$gridSource = Get-Content -LiteralPath (Join-Path $root 'scripts/vscripts/systems/grid_placement_system.lua') -Raw

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Check ($source.Contains('local function release_grid_for_state')) 'GRID_RELEASE_HELPER_MISSING'
Check ($source.Contains('local function release_grid_for_unit')) 'GRID_RELEASE_FALLBACK_MISSING'
Check ($source.Contains('unit.survival_grid_footprint')) 'GRID_FOOTPRINT_METADATA_MISSING'
Check ($source.Contains('if not state then') -and
    $source.Contains('release_grid_for_unit(victim)')) 'STATELESS_KILL_RELEASE_MISSING'
Check ($source.Contains('release_grid_for_state(state, victim)')) 'STATEFUL_KILL_RELEASE_MISSING'
Check ($gridSource.Contains('local function unit_is_dead')) 'DEAD_UNIT_FILTER_MISSING'
Check ($gridSource.Contains('and not unit_is_dead(unit)')) 'DEAD_UNIT_FILTER_NOT_APPLIED'
Check ($gridSource.Contains('local reconcile_occupied') -and
    $gridSource.Contains('reconcile_occupied = function')) 'OCCUPANCY_RECONCILE_MISSING'
Check ($gridSource.Contains('reconcile_occupied()') -and
    $gridSource.Contains('local function clear_occupied_entindex')) 'OCCUPANCY_RECONCILE_NOT_CONNECTED'

Write-Output 'TOWER_GRID_RELEASE_CONTRACT_PASS'