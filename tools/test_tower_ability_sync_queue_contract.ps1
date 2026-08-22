$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$sync = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/tower_ability_sync.lua") -Raw
$runtime = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/ui/ability_runtime_service.lua") -Raw
$events = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/core/events.lua") -Raw

Check ($sync.Contains("pending_by_entindex")) "TOWER_SYNC_QUEUE_STATE_MISSING"
Check ($sync.Contains("scheduler.after(0")) "TOWER_SYNC_NEXT_TICK_MISSING"
Check ($sync.Contains("tower_ability_sync_generation")) "TOWER_SYNC_GENERATION_MISSING"
Check ($sync.Contains("survival_tower_ability_sync_pending")) `
    "TOWER_SYNC_PENDING_FLAG_MISSING"
Check ($sync.Contains("function M.reset()")) "TOWER_SYNC_RESET_MISSING"
Check ($sync.Contains("mark_configured_route_abilities")) `
    "TOWER_SYNC_CONFIGURED_SKILL_CLEANUP_MISSING"
Check ($sync.Contains("survival_tower_managed_ability_names")) `
    "TOWER_SYNC_PREVIOUS_SKILL_CLEANUP_MISSING"
Check ($sync.Contains('type(state.unit.survival_tower_managed_ability_names) == "table"')) `
    "TOWER_SYNC_HOT_RELOAD_SELF_HEAL_MISSING"
Check ($runtime.Contains("survival_tower_ability_sync_pending")) `
    "TOWER_RUNTIME_PENDING_GUARD_MISSING"
Check ($runtime.Contains("events.TOWER_ABILITY_SYNC_COMPLETED")) `
    "TOWER_RUNTIME_COMPLETION_EVENT_MISSING"
Check ($events.Contains("TOWER_ABILITY_SYNC_COMPLETED")) `
    "TOWER_SYNC_COMPLETION_EVENT_UNDEFINED"

Write-Output "TOWER_ABILITY_SYNC_QUEUE_CONTRACT_PASS"