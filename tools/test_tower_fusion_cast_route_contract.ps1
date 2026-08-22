$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Read-Utf8([string]$relativePath) {
    return [System.IO.File]::ReadAllText((Join-Path $root $relativePath), $utf8)
}

$router = Read-Utf8 "scripts/vscripts/ui/ui_request_router.lua"
$ability = Read-Utf8 "scripts/vscripts/abilities/ability_tower_fusion.lua"
$service = Read-Utf8 "scripts/vscripts/systems/tower_fusion_service.lua"

Check ($router.Contains(
    'local tower_fusion_matches = ability_name == "ability_tower_fusion"')) `
    "TOWER_FUSION_DIRECT_MATCH_MISSING"
Check ($router.Contains(
    'unit:FindAbilityByName(ability_name) == ability')) `
    "TOWER_FUSION_ABILITY_IDENTITY_CHECK_MISSING"
Check ($router.Contains(
    'elseif tower_fusion_matches and owner_matches and not passive')) `
    "TOWER_FUSION_OWNER_VALIDATED_ROUTE_MISSING"
Check ($router.Contains(
    'and not is_point_target then')) `
    "TOWER_FUSION_POINT_TARGET_REJECTION_MISSING"
Check ($router.Contains(
    'if not ability:IsActivated() or ability:IsHidden()')) `
    "TOWER_FUSION_ACTIVATION_VISIBILITY_CHECK_MISSING"
Check ($router.Contains(
    'or not ability:IsFullyCastable() then')) `
    "TOWER_FUSION_CASTABLE_CHECK_MISSING"
Check ($router.Contains(
    'direct_result = { ok = false, error = "七塔合一技能当前不可用" }')) `
    "TOWER_FUSION_UNAVAILABLE_REJECTION_MISSING"
Check ($router.Contains(
    'direct_result = event_bus.request(events.TOWER_FUSION_REQUEST')) `
    "TOWER_FUSION_DIRECT_DISPATCH_MISSING"
Check ($router.Contains(
    'source = "ui_ability_cast_request"')) `
    "TOWER_FUSION_DIRECT_SOURCE_MISSING"
Check ($router.Contains(
    '[SURVIVAL_CAST][SERVER] TOWER_FUSION_DISPATCHED')) `
    "TOWER_FUSION_DIRECT_DIAGNOSTIC_MISSING"
Check ($router.IndexOf(
    'elseif tower_fusion_matches and owner_matches and not passive') -lt `
    $router.IndexOf('elseif gold_mine_ability_matches and owner_matches')) `
    "TOWER_FUSION_DIRECT_ROUTE_ORDER_INVALID"

Check ($ability.Contains('events.TOWER_FUSION_REQUEST')) `
    "TOWER_FUSION_NATIVE_FALLBACK_MISSING"
Check ($service.Contains('[TowerFusion] failed player=')) `
    "TOWER_FUSION_SERVICE_FAILURE_DIAGNOSTIC_MISSING"
Check ($service.Contains('[TowerFusion] completed player=')) `
    "TOWER_FUSION_SERVICE_SUCCESS_DIAGNOSTIC_MISSING"

Write-Output "TOWER_FUSION_CAST_ROUTE_CONTRACT_PASS"