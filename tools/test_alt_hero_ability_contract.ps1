$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$gameMode = Get-Content (Join-Path $root "scripts\vscripts\addon_game_mode.lua") -Raw
$policy = Get-Content (Join-Path $root "scripts\vscripts\core\hero_ability_policy.lua") -Raw
$builderProgression = Get-Content (Join-Path $root "scripts\vscripts\systems\builder_progression_system.lua") -Raw
$builderStages = Get-Content (Join-Path $root "scripts\vscripts\config\generated\builder_ability_stages.lua") -Raw

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

Check ($gameMode.Contains('require("core/hero_ability_policy")')) "ALT_FIX_POLICY_DEPENDENCY_MISSING"
Check ($policy.Contains('local BUILD = "preserve_engine_abilities_origin_dev_v1_20260731"')) "ALT_FIX_BUILD_MISSING"
Check ($policy.Contains("local VISIBLE_REPLACEMENTS = {")) "ALT_FIX_WHITELIST_MISSING"
Check ($policy.Contains('{ native = "undying_decay", custom = "ability_build_wall" }')) "ALT_FIX_DECAY_PAIR_MISSING"
Check ($policy.Contains('{ native = "undying_soul_rip", custom = "ability_build_main_city" }')) "ALT_FIX_SOUL_RIP_PAIR_MISSING"
Check ($policy.Contains('{ native = "undying_tombstone", custom = "ability_build_arrow_tower" }')) "ALT_FIX_TOMBSTONE_PAIR_MISSING"
Check ($policy.Contains('{ native = "undying_ceaseless_dirge", custom = "ability_build_gold_mine" }')) "ALT_FIX_DIRGE_PAIR_MISSING"
Check ($policy.Contains("hero:GetAbilityCount()) or 0) <= 1")) "ALT_FIX_NONZERO_GUARD_MISSING"
Check ($policy.Contains('hero:FindAbilityByName("undying_flesh_golem")')) "ALT_FIX_ULTIMATE_LOOKUP_MISSING"
Check ($policy.Contains("ultimate:SetHidden(true)")) "ALT_FIX_ULTIMATE_HIDE_MISSING"
Check ($policy.Contains("engine_abilities_preserved=true")) "ALT_FIX_RESULT_LOG_MISSING"

Check (-not $gameMode.Contains('require("core/ability_utils")')) "ALT_FIX_ABILITY_UTILS_DEPENDENCY_PRESENT"
Check (-not $gameMode.Contains("ability_utils.remove_all(hero)")) "ALT_FIX_REMOVE_ALL_PRESENT"
Check (-not $policy.Contains('RemoveAbility("undying_flesh_golem")')) "ALT_FIX_ULTIMATE_REMOVED"

$configureCall = $gameMode.IndexOf("hero_ability_policy.apply(hero)", $gameMode.IndexOf("local function initialize_survival_hero"))
$heroReady = $gameMode.IndexOf("event_bus.emit(events.HERO_READY", $configureCall)
Check ($configureCall -ge 0) "ALT_FIX_NOT_APPLIED_DURING_HERO_INITIALIZATION"
Check ($heroReady -gt $configureCall) "ALT_FIX_MUST_RUN_BEFORE_HERO_READY"

Check ($builderProgression.Contains("for ability_name, _ in pairs(managed_abilities) do")) "ALT_FIX_BUILDER_STAGE_MUST_REMOVE_ONLY_MANAGED_ABILITIES"
Check (-not $builderProgression.Contains("ability_utils.remove_all")) "ALT_FIX_BUILDER_STAGE_REMOVE_ALL_PRESENT"
Check ($builderProgression.Contains("event_bus.subscribe(events.HERO_READY, on_hero_ready)")) "ALT_FIX_BUILDER_STAGE_HERO_READY_SYNC_MISSING"
Check ($builderStages.Contains('ability_name = "ability_build_wall"')) "ALT_FIX_WALL_NOT_STAGE_MANAGED"
Check ($builderStages.Contains('ability_name = "ability_build_main_city"')) "ALT_FIX_MAIN_CITY_NOT_STAGE_MANAGED"
Check ($builderStages.Contains('ability_name = "ability_build_arrow_tower"')) "ALT_FIX_ARROW_TOWER_NOT_STAGE_MANAGED"
Check ($builderStages.Contains('ability_name = "ability_build_gold_mine"')) "ALT_FIX_GOLD_MINE_NOT_STAGE_MANAGED"

Write-Host "ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK"