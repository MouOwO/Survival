$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText((Resolve-Path $Path), [Text.UTF8Encoding]::new($false, $true))
}

function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$service = Read-Utf8 "scripts/vscripts/systems/gold_mine_batch_upgrade_service.lua"
$mine = Read-Utf8 "scripts/vscripts/systems/gold_mine_system.lua"
$shop = Read-Utf8 "scripts/vscripts/systems/shop_system.lua"
$router = Read-Utf8 "scripts/vscripts/ui/ui_request_router.lua"
$events = Read-Utf8 "scripts/vscripts/core/events.lua"

Check ($events.Contains('GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST = "gold_mine.level_upgrade_quote.request"')) `
    "GOLD_MINE_BATCH_QUOTE_EVENT_MISSING"
Check ($events.Contains('GOLD_MINE_AUTO_STATE_REQUEST = "gold_mine.auto_state.request"')) `
    "GOLD_MINE_BATCH_AUTO_STATE_EVENT_MISSING"
Check ($service.Contains('gold_mine.level_upgrade_quote.request') -or $service.Contains('events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST')) `
    "GOLD_MINE_BATCH_QUOTE_REQUEST_MISSING"
Check ($service.Contains('table.sort(queued, function(left, right)')) `
    "GOLD_MINE_BATCH_SORT_MISSING"
Check ($service.Contains('or not ability_ready(primary_ability, primary)')) `
    "GOLD_MINE_BATCH_PRIMARY_CASTABILITY_CHECK_MISSING"
Check ($service.Contains('technology_levels_purchased = cooled > 0 and 1 or 0')) `
    "GOLD_MINE_BATCH_SHARED_TECH_COUNT_MISSING"
Check ($service.Contains('silent_notification = true')) `
    "GOLD_MINE_BATCH_SILENT_PURCHASE_MISSING"
Check ($service.Contains('enabled = action.enabled')) `
    "GOLD_MINE_BATCH_EXPLICIT_AUTO_STATE_MISSING"
Check (-not $service.Contains('if result and result.ok == true then`n                        start_cooldown(ability)`n                        changed = changed + 1')) `
    "GOLD_MINE_BATCH_AUTO_USED_REMOVED_ABILITY_FOR_COOLDOWN"
Check ($mine.Contains('events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST,') -and `
       $mine.Contains('level_upgrade_quote')) `
    "GOLD_MINE_BATCH_QUOTE_HANDLER_MISSING"
Check ($mine.Contains('local requested = payload.enabled')) `
    "GOLD_MINE_AUTO_EXPLICIT_STATE_MISSING"
Check ($shop.Contains('payload.source_entindex or payload.entindex')) `
    "GOLD_MINE_TECH_SOURCE_NORMALIZATION_MISSING"
Check ($shop.Contains('entindex = gold_mine_source_entindex')) `
    "GOLD_MINE_TECH_OWNERSHIP_USES_WRONG_ENTINDEX"
Check ($router.Contains('gold_mine_batch_upgrade.execute')) `
    "GOLD_MINE_BATCH_ROUTER_MISSING"
Check (-not $router.Contains('ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))\n                direct_cooldown_started = true\n                ability_request_sequence')) `
    "GOLD_MINE_ROUTER_STARTED_COOLDOWN_BEFORE_RESULT"

Write-Output "GOLD_MINE_BATCH_UPGRADE_CONTRACT_PASS"
