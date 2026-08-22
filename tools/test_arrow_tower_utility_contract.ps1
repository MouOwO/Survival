$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$towerCsv = @(
    "arrow_tower_base.csv",
    "tower_class_anti_air.csv",
    "tower_class_death.csv",
    "tower_class_frost.csv",
    "tower_class_lightning.csv",
    "tower_class_machine_gun.csv",
    "tower_class_multi.csv",
    "tower_class_mystery.csv"
)
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
foreach ($name in $towerCsv) {
    $path = Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
        -Recurse -File -Filter $name | Select-Object -First 1 -ExpandProperty FullName
    Check ($null -ne $path) "TOWER_CSV_MISSING_$name"
    $rows = Import-Csv -LiteralPath $path -Encoding UTF8 | Where-Object {
        $_.record_id -and -not $_.record_id.StartsWith("#")
    }
    Check ($rows.Count -gt 0) "TOWER_ROWS_MISSING_$name"
    $csvText = [System.IO.File]::ReadAllText($path, $utf8)
    Check (-not $csvText.Contains([char]0xFFFD)) "TOWER_CSV_REPLACEMENT_CHAR_$name"
    foreach ($row in $rows) {
        Check ($row.active_skill_ids.EndsWith(
            "ability_building_blink|ability_destroy_arrow_tower"
        )) "UTILITY_ORDER_INVALID_$($row.record_id)"
    }
    $generatedName = [System.IO.Path]::GetFileNameWithoutExtension($name) + ".lua"
    $generatedPath = Join-Path $root "scripts/vscripts/config/generated/$generatedName"
    Check (Test-Path -LiteralPath $generatedPath) "TOWER_LUA_MISSING_$generatedName"
    $generatedText = [System.IO.File]::ReadAllText($generatedPath, $utf8)
    Check (-not $generatedText.Contains([char]0xFFFD)) `
        "TOWER_LUA_REPLACEMENT_CHAR_$generatedName"
    if ($name -eq "arrow_tower_base.csv") {
        $expectedPrefix = ([char]0x7bad) + ([char]0x5854)
        for ($level = 1; $level -le 5; $level++) {
            $actualName = $rows[$level - 1].PSObject.Properties["name"].Value
            Check ($actualName -eq ($expectedPrefix + "1-$level")) `
                "BASE_TOWER_NAME_INVALID_LV$level"
        }
    }
}

$sync = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/tower_utility_ability_sync.lua") -Raw
$towerSync = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/tower_ability_sync.lua") -Raw
$building = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/building_system.lua") -Raw
$router = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/ui/ui_request_router.lua") -Raw
$clientRoot = Resolve-Path (Join-Path $root "../../../content/dota_addons/survival")
$move = Get-Content -LiteralPath (Join-Path $clientRoot `
    "panorama/scripts/custom_game/building_move.js") -Raw
$bootstrap = Get-Content -LiteralPath (Join-Path $clientRoot `
    "panorama/scripts/custom_game/ui_bootstrap.js") -Raw
$layout = Get-Content -LiteralPath (Join-Path $clientRoot `
    "panorama/layout/custom_game/survival_hud.xml") -Raw

Check ($sync.Contains("MAX_VISIBLE_ABILITIES = 6")) "SLOT_LIMIT_MISSING"
Check ($sync.Contains("free_slots >= 2")) "MOVE_SLOT_RULE_MISSING"
Check ($sync.Contains("free_slots >= 1")) "DESTROY_SLOT_RULE_MISSING"
Check ($sync.IndexOf("add_utility(unit, MOVE_ABILITY") -lt `
    $sync.IndexOf("add_utility(unit, DESTROY_ABILITY")) "DESTROY_NOT_LAST"
Check ($sync.Contains("function M.clear(unit)")) "UTILITY_CLEAR_API_MISSING"
$clearIndex = $towerSync.IndexOf("tower_utility_abilities.clear(state.unit)")
$routeIndex = $towerSync.IndexOf("add_ability(state.unit, skill_id)")
$utilityIndex = $towerSync.IndexOf("tower_utility_abilities.sync(state, row)")
Check ($clearIndex -ge 0 -and $clearIndex -lt $routeIndex) `
    "UTILITY_NOT_CLEARED_BEFORE_ROUTE_ABILITIES"
Check ($routeIndex -lt $utilityIndex) "UTILITY_NOT_REAPPENDED_AFTER_ROUTE_ABILITIES"
Check ($building.Contains('state.building_id ~= "arrow_tower"')) `
    "ARROW_TOWER_SCOPE_MISSING"
Check ($building.Contains("ForceKill(false)")) "FORCE_KILL_MISSING"
Check ($building.Contains("ability:IsHidden()")) "SERVER_VISIBILITY_CHECK_MISSING"
Check ($router.Contains("ui_arrow_tower_destroy_request")) "DESTROY_ROUTE_MISSING"
Check ($move.Contains('normalized === "G"')) "G_HOTKEY_MISSING"
Check ($move.Contains('normalized === "ESCAPE"')) "ESC_CANCEL_MISSING"
Check (-not $move.Contains('"ENTER"')) "ENTER_CONFIRM_MUST_NOT_BE_BOUND"
Check (-not $bootstrap.Contains('"ENTER"')) "ENTER_FALLBACK_MUST_NOT_BE_BOUND"
Check (-not $layout.Contains("确认  Enter")) "ENTER_CONFIRM_LABEL_REMAINS"
Check (-not $layout.Contains("BuildingMoveButton")) "BACKUP_MOVE_BUTTON_REMAINS"
Check ($layout.Contains("ArrowTowerDestroyConfirm")) "CONFIRM_DIALOG_MISSING"

Write-Output "ARROW_TOWER_UTILITY_CONTRACT_PASS"