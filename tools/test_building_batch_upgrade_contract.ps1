$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText((Resolve-Path $Path), [Text.UTF8Encoding]::new($false, $true))
}

function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$batch = Read-Utf8 "scripts/vscripts/systems/building_batch_upgrade_service.lua"
$upgrade = Read-Utf8 "scripts/vscripts/systems/building_upgrade_system.lua"
$router = Read-Utf8 "scripts/vscripts/ui/ui_request_router.lua"
$events = Read-Utf8 "scripts/vscripts/core/events.lua"
$content = "D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival"
$tooltip = Read-Utf8 "$content/panorama/scripts/custom_game/ability_tooltip.js"
$combat = Read-Utf8 "$content/panorama/scripts/custom_game/combat_stats.js"

Check ($events.Contains('BUILDING_UPGRADE_QUOTE_REQUEST = "building.upgrade_quote.request"')) `
    "BATCH_UPGRADE_QUOTE_EVENT_MISSING"
Check ($upgrade.Contains('event_bus.handle_request(events.BUILDING_UPGRADE_QUOTE_REQUEST, upgrade_quote)')) `
    "BATCH_UPGRADE_QUOTE_HANDLER_MISSING"
Check ($upgrade.Contains('tower_routes.stage_end_level(state)')) `
    "BATCH_UPGRADE_W_STAGE_TARGET_MISSING"
Check ($upgrade.Contains('tower_routes.cost_to(state, target_level)')) `
    "BATCH_UPGRADE_AUTHORITATIVE_COST_MISSING"
Check ($batch.Contains('max = { "ability_upgrade_tower_max" }')) `
    "BATCH_UPGRADE_W_ABILITY_MISSING"
Check (-not $batch.Contains('candidate.survival_tower_class')) `
    "BATCH_UPGRADE_STILL_REQUIRES_SAME_ROUTE"
Check ($batch.Contains('table.sort(queued, function(left, right)')) `
    "BATCH_UPGRADE_SORT_MISSING"
Check ($batch.Contains('if left_wood ~= right_wood then return left_wood < right_wood end')) `
    "BATCH_UPGRADE_WOOD_PRIORITY_MISSING"
Check ($batch.Contains('if left_gold ~= right_gold then return left_gold < right_gold end')) `
    "BATCH_UPGRADE_GOLD_TIEBREAK_MISSING"
Check ($batch.IndexOf('event_bus.emit(events.BUILDING_UPGRADE_REQUEST, request)') -lt `
       $batch.IndexOf('ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))')) `
    "BATCH_UPGRADE_COOLDOWN_STARTS_BEFORE_RESULT"
Check ($router.Contains('TOWER_BATCH_UPGRADE_DISPATCHED mode=')) `
    "BATCH_UPGRADE_ROUTER_MODE_DIAGNOSTIC_MISSING"
Check (-not $router.Contains('TOWER_UPGRADE_DISPATCHED mode=')) `
    "BATCH_UPGRADE_W_STILL_USES_SINGLE_DISPATCH"

foreach ($source in @($tooltip, $combat)) {
    Check ($source.Contains('Players.GetSelectedEntities(Players.GetLocalPlayer())')) `
        "BATCH_UPGRADE_CLIENT_SELECTION_MISSING"
    Check ($source.Contains('result.length < 64')) `
        "BATCH_UPGRADE_CLIENT_LIMIT_MISSING"
    Check ($source.Contains('selected_entindexes: selectedEntindexesForRequest()')) `
        "BATCH_UPGRADE_CLIENT_PAYLOAD_MISSING"
}

Write-Output "BUILDING_BATCH_UPGRADE_CONTRACT_PASS"