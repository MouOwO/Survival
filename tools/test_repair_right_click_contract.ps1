$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$modifier = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/modifiers/modifier_repair_worker_ai.lua") -Raw
$orders = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/repair_order_service.lua") -Raw
$filter = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/tree_attack_order_filter.lua") -Raw
$builder = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/builder_service.lua") -Raw
$worker = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/worker_system.lua") -Raw

Check ($orders.Contains("DOTA_UNIT_ORDER_MOVE_TO_TARGET")) `
    "REPAIR_MOVE_TO_TARGET_ORDER_MISSING"
Check ($orders.Contains("SetManualRepairTarget")) `
    "REPAIR_MANUAL_TARGET_DISPATCH_MISSING"
Check ($filter.Contains('require("systems/repair_order_service")')) `
    "REPAIR_NOT_COMPOSED_IN_GLOBAL_ORDER_FILTER"
Check (([regex]::Matches($filter, "mode:SetExecuteOrderFilter")).Count -eq 1) `
    "REPAIR_CREATED_MULTIPLE_ORDER_FILTER_REGISTRATIONS"
Check ($modifier.Contains("manual_repair_target_entindex")) `
    "REPAIR_MANUAL_TARGET_STATE_MISSING"
Check ($modifier.Contains("edge_distance > self.repair_range")) `
    "REPAIR_EDGE_RANGE_CHECK_MISSING"
Check ($modifier.Contains("DOTA_UNIT_ORDER_MOVE_TO_POSITION")) `
    "REPAIR_APPROACH_ORDER_MISSING"
Check ($modifier.Contains("DOTA_UNIT_ORDER_STOP")) `
    "REPAIR_ARRIVAL_STOP_MISSING"
Check ($modifier.Contains("parent.survival_build_task = nil")) `
    "BUILDER_PENDING_BUILD_TASK_NOT_CANCELLED"
Check ($modifier.Contains('reason ~= "player_order"')) `
    "REPAIR_INVALID_TARGET_STOP_GUARD_MISSING"
Check ($builder.Contains("builder.survival_player_id = player_id")) `
    "BUILDER_REPAIR_OWNER_IDENTITY_MISSING"
Check ($worker.Contains("worker.survival_player_id = city_state.player_id")) `
    "REPAIRER_OWNER_IDENTITY_MISSING"

Write-Host "REPAIR_RIGHT_CLICK_CONTRACT_PASS"