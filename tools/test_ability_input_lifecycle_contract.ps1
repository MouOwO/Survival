$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot "..\$Path"),
        [System.Text.UTF8Encoding]::new($false, $true)
    )
}

function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$contentRoot = Join-Path $PSScriptRoot "..\..\..\..\content\dota_addons\survival"
$bootstrap = [System.IO.File]::ReadAllText(
    (Join-Path $contentRoot "panorama\scripts\custom_game\ui_bootstrap.js"),
    [System.Text.UTF8Encoding]::new($false, $true)
)
$combat = [System.IO.File]::ReadAllText(
    (Join-Path $contentRoot "panorama\scripts\custom_game\combat_stats.js"),
    [System.Text.UTF8Encoding]::new($false, $true)
)
$tooltip = [System.IO.File]::ReadAllText(
    (Join-Path $contentRoot "panorama\scripts\custom_game\ability_tooltip.js"),
    [System.Text.UTF8Encoding]::new($false, $true)
)
$grid = [System.IO.File]::ReadAllText(
    (Join-Path $contentRoot "panorama\scripts\custom_game\survival_grid_placement.js"),
    [System.Text.UTF8Encoding]::new($false, $true)
)
$netTables = Read-Utf8 "scripts\custom_net_tables.txt"
$move = [System.IO.File]::ReadAllText(
    (Join-Path $contentRoot "panorama\scripts\custom_game\building_move.js"),
    [System.Text.UTF8Encoding]::new($false, $true)
)

Check ($bootstrap.Contains("SurvivalInputLifecycleGeneration")) "INPUT_GENERATION_MISSING"
Check ($bootstrap.Contains("Always") -and $bootstrap.Contains("SetKeyPressedCallback")) "SECOND_RUN_REBIND_MISSING"
Check ($bootstrap.Contains('fallbackKeys = ["Q", "W", "E", "R", "T", "Y", "U", "A", "S", "D", "F", "G", "F2", "TAB", "SPACE"]')) "FALLBACK_KEYS_MISSING"
Check ($bootstrap.Contains("DispatchKey(key, true)")) "FALLBACK_NOT_USING_DISPATCHER"
Check ($bootstrap.Contains("FALLBACK_TRIGGER") -and $bootstrap.Contains("FALLBACK_BINDS_APPLIED")) "FALLBACK_DIAGNOSTICS_MISSING"
Check ($bootstrap.Contains('var inputContextId = String(Date.now())') -and $bootstrap.Contains('var command = "survival_input_" + inputContextId + "_"')) "FALLBACK_CONTEXT_COMMAND_MISSING"
Check ($bootstrap.Contains("FALLBACK_BINDS_SKIPPED") -and $bootstrap.Contains("activeDispatcher.context_id !== inputContextId")) "STALE_CONTEXT_REBIND_GUARD_MISSING"
Check ($bootstrap.Contains("dispatcher_generation=") -and $bootstrap.Contains("currentConfig.SurvivalInputDispatcher")) "FALLBACK_CURRENT_DISPATCHER_MISSING"
Check ($bootstrap.Contains("BOOTSTRAP_ENTER") -and $bootstrap.Contains("FALLBACK_COMMAND_FAILED") -and $bootstrap.Contains("FALLBACK_BIND_FAILED")) "INPUT_BOOTSTRAP_DIAGNOSTIC_GUARD_MISSING"
Check ($netTables.Contains('"survival_builder_identity"')) "BUILDER_IDENTITY_NETTABLE_UNDECLARED"
Check (-not $bootstrap.Contains("SurvivalKeyDispatcherBound")) "STALE_KEY_BOUND_FLAG_PRESENT"
Check ($combat.Contains('RegisterKeyHandler("ability_input"')) "ABILITY_HANDLER_NOT_REGISTERED"
Check ($combat.Contains("casterForAbility")) "ABILITY_CASTER_RESOLUTION_MISSING"
Check ($bootstrap.Contains("SurvivalSelectionResolver")) "AUTHORITATIVE_SELECTION_RESOLVER_MISSING"
Check ($bootstrap.Contains("Players.GetSelectedEntities(playerId)")) "ACTUAL_SELECTION_QUERY_MISSING"
Check ($bootstrap.Contains('"placeholder_space_guard"') -and $bootstrap.Contains('heroName === "npc_dota_hero_undying" ? builder : hero')) "PLACEHOLDER_SPACE_GUARD_MISSING"
Check ($bootstrap.Contains('GameUI.SelectUnit(target, false)') -and $bootstrap.Contains('GameUI.MoveCameraToEntity(target)') -and $bootstrap.Contains('action=') -and $bootstrap.Contains('block_placeholder')) "PLACEHOLDER_SPACE_REDIRECT_MISSING"
Check ($combat.Contains("resolver.Resolve()") -and $tooltip.Contains("resolver.Resolve()")) "CLICK_HOTKEY_SELECTION_PIPELINE_DIVERGED"
Check ($combat.Contains('" runtime_owner="')) "HOTKEY_RUNTIME_OWNER_DIAGNOSTIC_MISSING"
Check ($combat.Contains("selection_owner_mismatch")) "SELECTION_OWNER_GUARD_MISSING"
Check ($combat.Contains("function orderVisibleAbilities(entries)") -and $combat.Contains("function visibleAbilityEntries(unit)")) "ABILITY_DISPLAY_ORDER_PIPELINE_MISSING"
Check ($combat.Contains("return !utilityHotkeys[entry.name]") -and $combat.Contains("standard[slot].ability")) "STANDARD_HOTKEY_UTILITY_FILTER_MISSING"
Check ($combat.Contains('function builderDisplaySlotForKey(key)') -and $combat.Contains('"builder_key_dispatch"')) "BUILDER_A_INPUT_MAPPING_MISSING"
Check ($combat.Contains('abilityName === "ability_challenge_auto_summon"') -and $combat.Contains('(behavior & 512) === 0')) "CHALLENGE_TOGGLE_INPUT_MISSING"
Check ($tooltip.Contains('abilityName === "ability_challenge_auto_summon"')) "CHALLENGE_TOGGLE_PROXY_MISSING"
Check ($combat.Contains('RegisterMouseHandler(') -and $combat.Contains('"ability_point_target"')) "POINT_MOUSE_HANDLER_NOT_REGISTERED"
Check ($tooltip.Contains('return /^ability_build_/.test(abilityName)')) "BUILD_CLICK_PROXY_MISSING"
Check ($tooltip.Contains('var projectManagedInput = /^ability_build_/.test(abilityName)') -and
    $tooltip.Contains('if (!projectManagedInput)')) "BUILD_PROXY_NATIVE_FALLBACK_PRESENT"
Check ($tooltip.Contains("runtime.owner_entindex")) "CLICK_CASTER_RUNTIME_OWNER_MISSING"
Check ($grid.Contains("customPointTargetState")) "GRID_FROZEN_POINT_STATE_MISSING"
Check ($grid.Contains("SurvivalSelectionResolver") -and -not $grid.Contains("GetLocalPlayerPortraitUnit")) "GRID_SELECTION_RESOLVER_MISSING"
Check ($grid.Contains('RegisterKeyHandler("grid_placement"')) "GRID_KEY_HANDLER_NOT_REGISTERED"
Check ($grid.Contains('request_anchor_x') -and $grid.Contains('RESPONSE_REJECTED')) "GRID_RESPONSE_IDENTITY_DIAGNOSTIC_MISSING"
Check ($grid.Contains('[GridPlacement][CLIENT] VALIDATE_SEND')) "GRID_CLIENT_VALIDATE_LOG_MISSING"
Check ($move.Contains("!isMovable(selectedUnit())")) "BUILDER_D_CONFLICT_GUARD_MISSING"
Check ($move.Contains("SurvivalSelectionResolver") -and -not $move.Contains("GetLocalPlayerPortraitUnit")) "BUILD_MOVE_SELECTION_RESOLVER_MISSING"
Check (-not $move.Contains("SurvivalKeyDispatcherBound")) "BUILD_MOVE_STALE_BOUND_FLAG_PRESENT"

Write-Output "ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS"