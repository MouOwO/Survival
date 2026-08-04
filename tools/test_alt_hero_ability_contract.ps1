$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$gameMode = Get-Content (Join-Path $root "scripts\vscripts\addon_game_mode.lua") -Raw
$policy = Get-Content (Join-Path $root "scripts\vscripts\core\hero_ability_policy.lua") -Raw
$builderProgression = Get-Content (Join-Path $root "scripts\vscripts\systems\builder_progression_system.lua") -Raw
$heroSummon = Get-Content (Join-Path $root "scripts\vscripts\systems\hero_summon_system.lua") -Raw
$heroSkills = Get-Content (Join-Path $root "scripts\vscripts\systems\hero_skill_system.lua") -Raw
$builderStages = Get-Content (Join-Path $root "scripts\vscripts\config\generated\builder_ability_stages.lua") -Raw

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

Check (-not $gameMode.Contains('require("core/hero_ability_policy")')) "ALT_FIX_PLACEHOLDER_POLICY_DEPENDENCY_REMAINS"
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

$configureCall = $gameMode.IndexOf("hero_anchor_service.register_placeholder", $gameMode.IndexOf("local function initialize_survival_hero"))
$heroReady = $gameMode.IndexOf("event_bus.emit(events.HERO_READY", $configureCall)
Check ($configureCall -ge 0) "ALT_FIX_PLACEHOLDER_REGISTRATION_MISSING"
Check ($heroReady -gt $configureCall) "ALT_FIX_PLACEHOLDER_MUST_REGISTER_BEFORE_HERO_READY"

Check ($builderProgression.Contains("for ability_name, _ in pairs(managed_abilities) do")) "ALT_FIX_BUILDER_STAGE_MUST_REMOVE_ONLY_MANAGED_ABILITIES"
Check (-not $builderProgression.Contains("ability_utils.remove_all")) "ALT_FIX_BUILDER_STAGE_REMOVE_ALL_PRESENT"
Check ($builderProgression.Contains("event_bus.subscribe(events.BUILDER_READY, on_builder_ready)")) "ALT_FIX_BUILDER_STAGE_BUILDER_READY_SYNC_MISSING"
Check ($builderStages.Contains('ability_name = "ability_build_wall"')) "ALT_FIX_WALL_NOT_STAGE_MANAGED"
Check ($builderStages.Contains('ability_name = "ability_build_main_city"')) "ALT_FIX_MAIN_CITY_NOT_STAGE_MANAGED"
Check ($builderStages.Contains('ability_name = "ability_build_arrow_tower"')) "ALT_FIX_ARROW_TOWER_NOT_STAGE_MANAGED"
Check ($builderStages.Contains('ability_name = "ability_build_gold_mine"')) "ALT_FIX_GOLD_MINE_NOT_STAGE_MANAGED"
Check (-not $heroSummon.Contains('require("core/ability_utils")')) "ALT_FIX_SUMMON_ABILITY_UTILS_DEPENDENCY_PRESENT"
Check (-not $heroSummon.Contains("ability_utils.remove_all(unit)")) "ALT_FIX_SUMMON_REMOVE_ALL_PRESENT"
Check ($heroSummon.Contains("local function preserve_and_hide_native_abilities(unit)")) "ALT_FIX_SUMMON_PRESERVE_POLICY_MISSING"
Check ($heroSummon.Contains("ability:SetHidden(true)")) "ALT_FIX_SUMMON_NATIVE_HIDE_MISSING"
Check ($heroSummon.Contains("ability:SetActivated(false)")) "ALT_FIX_SUMMON_NATIVE_DISABLE_MISSING"
Check ($heroSummon.Contains("preserve_and_hide_native_abilities(unit)")) "ALT_FIX_SUMMON_POLICY_CALL_MISSING"
Check (-not $heroSkills.Contains("ability_utils.remove_all(state.unit)")) "ALT_FIX_SKILL_SYNC_REMOVE_ALL_PRESENT"
Check (-not $heroSkills.Contains("ability_utils.remove_all_except")) "ALT_FIX_SKILL_SYNC_REMOVE_ALL_EXCEPT_PRESENT"
Check ($heroSkills.Contains("local function remove_unowned_custom_abilities(state)")) "ALT_FIX_SKILL_SYNC_MANAGED_CLEANUP_MISSING"
Check ($heroSkills.Contains("for _, definition in ipairs(skills.rows or {}) do")) "ALT_FIX_SKILL_SYNC_MANAGED_WHITELIST_MISSING"
Check (-not $heroSkills.Contains('require("core/ability_utils")')) "ALT_FIX_SKILL_SYNC_ABILITY_UTILS_DEPENDENCY_PRESENT"
Check ($heroSkills.Contains("local function preserve_native_abilities(unit)")) "ALT_FIX_SKILL_SYNC_PRESERVE_POLICY_MISSING"
Check ($heroSkills.Contains("ability:SetHidden(true)")) "ALT_FIX_SKILL_SYNC_NATIVE_HIDE_MISSING"
Check ($heroSkills.Contains("ability:SetActivated(false)")) "ALT_FIX_SKILL_SYNC_NATIVE_DISABLE_MISSING"
Check ($heroSkills.Contains("preserve_native_abilities(state.unit)")) "ALT_FIX_SKILL_SYNC_POLICY_CALL_MISSING"

Write-Host "ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK"
