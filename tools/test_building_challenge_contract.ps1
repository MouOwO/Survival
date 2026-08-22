$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$contentRoot = 'D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival'

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$definitions = Import-Csv (Join-Path $root 'data/csv/挑战与奖励系统/building_challenge_definitions.csv') |
    Where-Object { -not $_.challenge_id.StartsWith('#') }
$waves = Import-Csv (Join-Path $root 'data/csv/挑战与奖励系统/building_challenge_waves.csv') |
    Where-Object { -not $_.challenge_wave_id.StartsWith('#') }
$globalRules = Import-Csv (Join-Path $root 'data/csv/公共规则/global_rules.csv') |
    Where-Object { -not $_.rule_id.StartsWith('#') }
$service = Get-Content (Join-Path $root 'scripts/vscripts/systems/building_challenge_service.lua') -Raw
$collision = Get-Content (Join-Path $root 'scripts/vscripts/systems/wave_monster_collision.lua') -Raw
$abilityFactory = Get-Content (Join-Path $root `
    'scripts/vscripts/abilities/building_challenge_ability_factory.lua') -Raw
$waveSystem = Get-Content (Join-Path $root 'scripts/vscripts/systems/wave_system.lua') -Raw
$buildingSystem = Get-Content (Join-Path $root 'scripts/vscripts/systems/building_system.lua') -Raw
$abilities = Get-Content (Join-Path $root 'scripts/npc/npc_abilities_custom.txt') -Raw
$goldMine = Get-Content (Join-Path $root 'scripts/vscripts/systems/gold_mine_system.lua') -Raw
$router = Get-Content (Join-Path $root 'scripts/vscripts/ui/ui_request_router.lua') -Raw
$combatStats = Get-Content (Join-Path $contentRoot `
    'panorama/scripts/custom_game/combat_stats.js') -Raw
$abilityTooltip = Get-Content (Join-Path $contentRoot `
    'panorama/scripts/custom_game/ability_tooltip.js') -Raw
$construction = Import-Csv (Join-Path $root 'data/csv/建筑与工人系统/building_construction_rules.csv') |
    Where-Object { $_.building_id -eq 'building_challenge' }
$visual = Import-Csv (Join-Path $root 'data/csv/建筑与工人系统/building_visual_levels.csv') |
    Where-Object { $_.building_id -eq 'building_challenge' }
$rewards = Import-Csv (Join-Path $root 'data/csv/挑战与奖励系统/reward_effects.csv') |
    Where-Object { -not $_.effect_id.StartsWith('#') -and $_.effect_id.StartsWith('effect_building_challenge_') }

Check ($definitions.Count -eq 5) 'CHALLENGE_DEFINITION_COUNT_INVALID'
Check ($waves.Count -eq 500) 'CHALLENGE_WAVE_MATRIX_COUNT_INVALID'
Check (@($waves | Group-Object challenge_wave_id | Where-Object Count -ne 1).Count -eq 0) `
    'CHALLENGE_WAVE_ID_NOT_UNIQUE'
$difficultyIds = @('N1', 'N2', 'N3', 'N4', 'N5')
foreach ($difficultyId in $difficultyIds) {
    $difficultyWaves = @($waves | Where-Object difficulty_id -eq $difficultyId)
    Check ($difficultyWaves.Count -eq 100) "CHALLENGE_DIFFICULTY_MATRIX_INVALID:$difficultyId"
    Check (($difficultyWaves | Group-Object wave_number).Count -eq 20) `
        "CHALLENGE_WAVE_COUNT_INVALID:$difficultyId"
    Check (@($difficultyWaves | Group-Object wave_number | Where-Object Count -ne 5).Count -eq 0) `
        "CHALLENGE_WAVE_KIND_COUNT_INVALID:$difficultyId"
}
$cooldowns = @('100', '110', '120', '130', '140')
for ($index = 0; $index -lt $definitions.Count; $index++) {
    Check ($definitions[$index].cooldown_seconds -eq $cooldowns[$index]) 'CHALLENGE_COOLDOWN_INVALID'
    Check ($definitions[$index].max_alive -eq '1' -and $definitions[$index].max_challenge_waves -eq '20') `
        'CHALLENGE_LIMIT_INVALID'
}
Check ($definitions[3].required_main_city_level -eq '5') 'CHALLENGE_BLADEMASTER_PREREQUISITE_INVALID'
Check (@($definitions | Where-Object {
    [string]::IsNullOrWhiteSpace($_.model_path) -or $_.unit_name -ne 'npc_survival_wave_monster'
}).Count -eq 0) 'CHALLENGE_VISUAL_CONFIG_INVALID'
Check (@($waves | Where-Object {
    ([int]$_.health -ne ([int]$_.wave_number * 1000) -and
        -not ($_.challenge_id -eq 'challenge_monster_01' -and [int]$_.wave_number -eq 1 -and [int]$_.health -eq 6000)) -or
    [int]$_.armor -ne ([int]$_.wave_number * 10) -or
    $_.attack -ne '2' -or $_.attack_speed -ne '1'
}).Count -eq 0) 'CHALLENGE_STATS_INVALID'
$definitionNames = @{}
foreach ($definition in $definitions) { $definitionNames[$definition.challenge_id] = $definition.display_name }
Check (@($waves | Where-Object {
    -not $definitionNames.ContainsKey($_.challenge_id) -or
    $_.display_name -ne $definitionNames[$_.challenge_id] -or
    $_.challenge_wave_id -ne ("{0}_{1}_wave_{2:d2}" -f $_.difficulty_id.ToLower(), $_.challenge_id, [int]$_.wave_number)
}).Count -eq 0) 'CHALLENGE_ID_OR_DISPLAY_NAME_INVALID'
$n1ByKey = @{}
foreach ($row in ($waves | Where-Object difficulty_id -eq 'N1')) {
    $n1ByKey["$($row.challenge_id):$($row.wave_number)"] = $row
}
Check (@($waves | Where-Object difficulty_id -ne 'N1' | Where-Object {
    $source = $n1ByKey["$($_.challenge_id):$($_.wave_number)"]
    -not $source -or $_.health -ne $source.health -or $_.attack -ne $source.attack -or
        $_.armor -ne $source.armor -or $_.attack_speed -ne $source.attack_speed
}).Count -eq 0) 'CHALLENGE_TEMP_DIFFICULTY_COPY_INVALID'
Check ($rewards.Count -eq 8) 'CHALLENGE_REWARD_EFFECT_COUNT_INVALID'
$hullRule = $globalRules | Where-Object rule_id -eq 'building_challenge_hull_radius'
$lifetimeRule = $globalRules | Where-Object rule_id -eq 'building_challenge_lifetime_seconds'
$wallHealthRule = $globalRules | Where-Object rule_id -eq 'building_challenge_wall_failure_health_pct'
$checkIntervalRule = $globalRules | Where-Object rule_id -eq 'building_challenge_failure_check_interval_seconds'
Check ($hullRule.Count -eq 1 -and $hullRule.value -eq '0' -and $hullRule.enabled -eq '1') `
    'CHALLENGE_HULL_RULE_INVALID'
Check ($lifetimeRule.Count -eq 1 -and $lifetimeRule.value -eq '60' -and $lifetimeRule.enabled -eq '1') `
    'CHALLENGE_LIFETIME_RULE_INVALID'
Check ($wallHealthRule.Count -eq 1 -and $wallHealthRule.value -eq '50' -and $wallHealthRule.enabled -eq '1') `
    'CHALLENGE_WALL_HEALTH_RULE_INVALID'
Check ($checkIntervalRule.Count -eq 1 -and $checkIntervalRule.value -eq '0.1' -and $checkIntervalRule.enabled -eq '1') `
    'CHALLENGE_FAILURE_CHECK_INTERVAL_RULE_INVALID'
Check ($service.Contains('scheduler.every(1, auto_tick, TASK_ID)')) 'CHALLENGE_AUTO_INTERVAL_MISSING'
Check ($service.Contains('break')) 'CHALLENGE_AUTO_ONE_PER_TICK_MISSING'
Check ($service.Contains('if result.ok then break end')) 'CHALLENGE_AUTO_SUCCESS_BREAK_MISSING'
Check ($service.Contains('alive_by_team[state.team]')) 'CHALLENGE_TEAM_ALIVE_LIMIT_MISSING'
Check ($service.Contains('challenge_count_by_team[state.team]')) 'CHALLENGE_INDEPENDENT_PROGRESS_MISSING'
Check ($service.Contains('wave_system.get_difficulty()')) 'CHALLENGE_DIFFICULTY_SOURCE_MISSING'
Check ($service.Contains('unit.survival_display_name = row.display_name or definition.display_name')) `
    'CHALLENGE_INSTANCE_DISPLAY_NAME_MISSING'
Check (-not $service.Contains('wave_system.current_wave_number')) 'CHALLENGE_FORMAL_WAVE_DEPENDENCY_RESTORED'
Check ($service.Contains('MONSTER_REWARD_GRANT_REQUEST')) 'CHALLENGE_REWARD_REQUEST_MISSING'
Check (-not $service.Contains('MONSTER_KILLED')) 'CHALLENGE_FORMAL_REWARD_EVENT_LEAK'
Check ($service.Contains('current * 100 < maximum * WALL_FAILURE_HEALTH_PCT')) `
    'CHALLENGE_STRICT_WALL_HEALTH_BOUNDARY_MISSING'
Check ($service.Contains('scheduler.after(') -and $service.Contains('LIFETIME_SECONDS')) `
    'CHALLENGE_TIMEOUT_TASK_MISSING'
Check ($service.Contains('if not settle(meta, "killed") then return end')) `
    'CHALLENGE_IDEMPOTENT_KILL_SETTLEMENT_MISSING'
Check ($service.Contains('= meta.challenge_wave_number')) `
    'CHALLENGE_PROGRESS_ON_KILL_MISSING'
Check ($abilityFactory.Contains('result.cast_consumed ~= true')) `
    'CHALLENGE_CONSUMED_FAILURE_COOLDOWN_MISSING'
Check ($waveSystem.Contains('function M.spawn_challenge_monster')) 'CHALLENGE_SPAWN_BOUNDARY_MISSING'
Check ($waveSystem.Contains('unit.survival_is_challenge_monster = true')) 'CHALLENGE_IDENTITY_MISSING'
Check ($waveSystem.Contains('collision_profile.base_hull_radius')) 'CHALLENGE_SHARED_HULL_MISSING'
Check ($waveSystem.Contains('unit.survival_wave_no_unit_collision = collision_profile.no_unit_collision')) `
    'CHALLENGE_SHARED_COLLISION_MISSING'
Check ($waveSystem.Contains('is_challenge_monster = true')) `
    'CHALLENGE_COLLISION_IDENTITY_MISSING'
Check ($collision.Contains('base_hull_radius = global_rules.building_challenge_hull_radius')) `
    'CHALLENGE_ZERO_HULL_PROFILE_MISSING'
Check ($waveSystem.Contains('no_unit_collision = collision_profile.no_unit_collision and 1 or 0')) `
    'CHALLENGE_NO_UNIT_COLLISION_FORWARDING_MISSING'
Check ($waveSystem.Contains('member_role = "assault_boss"')) `
    'CHALLENGE_COMBAT_ROLE_MISSING'
Check ($buildingSystem.Contains('count_for(builder.player_id, "building_research_lab") < 1')) `
    'CHALLENGE_RESEARCH_PREREQUISITE_MISSING'
Check ($abilities.Contains('"ability_challenge_monster_05"')) 'CHALLENGE_FIFTH_ABILITY_MISSING'
Check ($goldMine.Contains('gold_mine.income_bonus_pct')) 'CHALLENGE_GOLD_MINE_REWARD_NOT_CONSUMED'
Check ($construction.Count -eq 1 -and $construction.build_visual_scale -eq '0.34' `
    -and $construction.build_loop_particle -eq 'particles/items2_fx/teleport_start.vpcf') `
    'CHALLENGE_CONSTRUCTION_RULE_MISSING'
Check ($visual.Count -eq 1 -and $visual.model_scale -eq '0.34' `
    -and $visual.model_name -eq 'models/props_structures/radiant_ancient001.vmdl') `
    'CHALLENGE_BUILDING_VISUAL_INVALID'
Check ($router.Contains('CHALLENGE_AUTO_DISPATCHED')) 'CHALLENGE_AUTO_UI_ROUTE_MISSING'
Check ($router.Contains('ability.survival_reverting_toggle = true')) `
    'CHALLENGE_AUTO_TOGGLE_REENTRY_GUARD_MISSING'
Check ($combatStats.Contains('abilityName === "ability_challenge_auto_summon"')) `
    'CHALLENGE_AUTO_MAIN_HUD_NOT_MANAGED'
Check ($combatStats.Contains('(behavior & 4) === 0 && (behavior & 512) === 0')) `
    'CHALLENGE_AUTO_TOGGLE_BEHAVIOR_REJECTED'
Check ($abilityTooltip.Contains('abilityName === "ability_challenge_auto_summon"')) `
    'CHALLENGE_AUTO_TOOLTIP_INPUT_NOT_MANAGED'

'BUILDING_CHALLENGE_CONTRACT_PASS definitions=5 rows=500 difficulties=5 waves=20 rewards=8'