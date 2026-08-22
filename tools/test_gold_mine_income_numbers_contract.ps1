$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText((Resolve-Path $Path), [Text.UTF8Encoding]::new($false, $true))
}

function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$system = Read-Utf8 "scripts/vscripts/systems/gold_mine_system.lua"
$js = Read-Utf8 "D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\panorama\scripts\custom_game\gold_mine_income_numbers.js"
$css = Read-Utf8 "D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\panorama\styles\custom_game\gold_mine_income_numbers.css"
$hud = Read-Utf8 "D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\panorama\layout\custom_game\survival_hud.xml"

Check ($system.Contains('if result and result.ok then')) "GOLD_MINE_INCOME_SUCCESS_GUARD_MISSING"
Check ($system.Contains('survival_gold_mine_income_number')) "GOLD_MINE_INCOME_EVENT_MISSING"
Check ($system.Contains('amount = math.floor(amount + 0.5)')) "GOLD_MINE_INCOME_AMOUNT_MISSING"
Check (-not $system.Contains('OVERHEAD_ALERT_GOLD')) "GOLD_MINE_NATIVE_GOLD_OVERHEAD_RESTORED"
Check (-not $system.Contains('OVERHEAD_ALERT_CRITICAL')) "GOLD_MINE_NATIVE_CRITICAL_OVERHEAD_RESTORED"
Check ($js.Contains('GameEvents.Subscribe("survival_gold_mine_income_number"')) "GOLD_MINE_INCOME_SUBSCRIPTION_MISSING"
Check ($js.Contains('SurvivalInputLifecycleGeneration')) "GOLD_MINE_INCOME_LIFECYCLE_GUARD_MISSING"
Check ($js.Contains('Entities.GetAbsOrigin') -and $js.Contains('Game.WorldToScreenX')) "GOLD_MINE_INCOME_WORLD_PROJECTION_MISSING"
Check ($js.Contains('DeleteAsync(0.0)') -and $js.Contains('$.Schedule(0.0, updatePositions)')) "GOLD_MINE_INCOME_CLEANUP_MISSING"
Check ($css.Contains('color: #ffd84a')) "GOLD_MINE_INCOME_GOLD_STYLE_MISSING"
Check ($hud.Contains('gold_mine_income_numbers.css') -and $hud.Contains('gold_mine_income_numbers.js')) "GOLD_MINE_INCOME_HUD_INCLUDE_MISSING"
Check ($hud.Contains('id="GoldMineIncomeNumbers"')) "GOLD_MINE_INCOME_HUD_CONTAINER_MISSING"

Write-Output "GOLD_MINE_INCOME_NUMBERS_CONTRACT_PASS"