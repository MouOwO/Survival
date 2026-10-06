$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$csv = (Resolve-Path (Join-Path $root "data\csv\*\blademaster_exclusive_runtime.csv")).Path
$runtime = Join-Path $root "scripts\vscripts\config\generated\blademaster_exclusive_runtime.lua"
$skills = Join-Path $root "scripts\vscripts\config\generated\hero_skill_definitions.lua"
$service = Join-Path $root "scripts\vscripts\systems\blademaster_exclusive_service.lua"
$damageFilter = Join-Path $root "scripts\vscripts\combat\damage_filter_service.lua"
$stats = Join-Path $root "scripts\vscripts\systems\hero_combat_stat_service.lua"
$fusion = Join-Path $root "scripts\vscripts\systems\tower_fusion_service.lua"
$skillSystem = Join-Path $root "scripts\vscripts\systems\hero_skill_system.lua"
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Text($path) { return [System.IO.File]::ReadAllText($path, $strictUtf8) }
function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$csvText = Text $csv
$runtimeText = Text $runtime
$skillsText = Text $skills
$skillsCsv = (Resolve-Path (Join-Path $root "data\csv\*\hero_skill_definitions.csv")).Path
$exclusiveCsv = (Resolve-Path (Join-Path $root "data\csv\*\hero_exclusive_skills.csv")).Path
$tooltipCsv = (Resolve-Path (Join-Path $root "data\csv\*\tooltip_definitions.csv")).Path
$skillRows = @(ConvertFrom-Csv (Text $skillsCsv))
$exclusiveRows = @(ConvertFrom-Csv (Text $exclusiveCsv) | Where-Object { $_.hero_id -eq "hero_blademaster" })
$tooltipRows = @(ConvertFrom-Csv (Text $tooltipCsv))
$exclusiveText = Text (Join-Path $root "scripts\vscripts\config\generated\hero_exclusive_skills.lua")
$tooltipText = Text (Join-Path $root "scripts\vscripts\config\generated\tooltip_definitions.lua")
$serviceText = Text $service
$damageFilterText = Text $damageFilter
$statsText = Text $stats
$fusionText = Text $fusion
$skillSystemText = Text $skillSystem
$gameModeText = Text (Join-Path $root "scripts\vscripts\addon_game_mode.lua")
$rewardEffectsText = Text (Join-Path $root "scripts\vscripts\config\generated\reward_effects.lua")
$choiceText = Text (Join-Path $root "scripts\vscripts\systems\hero_skill_choice_service.lua")
$localizationPaths = @(
    (Join-Path $root "panorama\localization\addon_schinese.txt"),
    (Join-Path $root "resource\addon_schinese.txt"),
    (Join-Path $root "resource\localization\addon_schinese.txt")
)

# Check the authoritative unlock rows, generated consumers and every tooltip
# projection together. Merely finding four ability names misses swapped W/E
# descriptions and the old all-at-first-ascension configuration.
$orderedSkills = @("exclusive", "agility", "swiftness", "mobility")
$unlockLevels = @(1, 3, 6, 10)
$slotNames = @("q", "w", "e", "r")
$ascensionNames = @([string][char]0x4E00, [string][char]0x4E09, [string][char]0x516D, [string][char]0x5341)
$activationSuffix = -join ([char[]]@(0x8F6C, 0x6FC0, 0x6D3B, 0x3002))
Check ($exclusiveRows.Count -eq 4) "EXCLUSIVE_UNLOCK_ROW_COUNT_INVALID"
for ($i = 0; $i -lt $orderedSkills.Count; $i++) {
    $skillId = "skill_blademaster_" + $orderedSkills[$i]
    $abilityName = "ability_survival_blademaster_" + $orderedSkills[$i]
    $unlock = $exclusiveRows[$i]
    Check ($unlock.skill_id -eq $skillId) ("EXCLUSIVE_SLOT_ORDER_INVALID: " + $skillId)
    Check ([int]$unlock.unlock_rebirth_level -eq $unlockLevels[$i]) ("EXCLUSIVE_UNLOCK_LEVEL_INVALID: " + $skillId)
    Check ($unlock.initial_level -eq "1" -and $unlock.guaranteed -eq "1" -and $unlock.enabled -eq "1") ("EXCLUSIVE_UNLOCK_FLAGS_INVALID: " + $skillId)
    $generatedUnlock = @($exclusiveText -split "`n" | Where-Object { $_.Contains('skill_id = "' + $skillId + '"') })
    Check ($generatedUnlock.Count -eq 1 -and $generatedUnlock[0] -match ('unlock_rebirth_level = ' + $unlockLevels[$i] + '(?:,| )')) ("EXCLUSIVE_GENERATED_UNLOCK_MISMATCH: " + $skillId)
    $definitions = @($skillRows | Where-Object { $_.skill_id -eq $skillId })
    Check ($definitions.Count -eq 1) ("SKILL_SOURCE_ROW_MISSING: " + $skillId)
    $definition = $definitions[0]
    Check ($definition.ability_name -eq $abilityName -and $definition.effect_type -eq ("blademaster_" + $slotNames[$i])) ("SKILL_SLOT_EFFECT_MISMATCH: " + $skillId)
    Check ($definition.description.StartsWith($ascensionNames[$i] + $activationSuffix)) ("SKILL_UNLOCK_DESCRIPTION_MISMATCH: " + $skillId)
    $generatedSkill = @($skillsText -split "`n" | Where-Object { $_.Contains('skill_id = "' + $skillId + '"') })
    Check ($generatedSkill.Count -eq 1 -and $generatedSkill[0].Contains('description = "' + $definition.description + '"')) ("SKILL_GENERATED_DESCRIPTION_MISMATCH: " + $skillId)
    $tooltip = @($tooltipRows | Where-Object { $_.tooltip_id -eq ("ability:" + $abilityName) })
    Check ($tooltip.Count -eq 1 -and $tooltip[0].desc -eq $definition.description -and $tooltip[0].source_id -eq $skillId) ("TOOLTIP_CSV_DESCRIPTION_MISMATCH: " + $skillId)
    $generatedTooltip = @($tooltipText -split "`n" | Where-Object { $_.Contains('tooltip_id = "ability:' + $abilityName + '"') })
    Check ($generatedTooltip.Count -eq 1 -and $generatedTooltip[0].Contains('desc = "' + $definition.description + '"')) ("TOOLTIP_GENERATED_DESCRIPTION_MISMATCH: " + $skillId)
    $token = "DOTA_Tooltip_ability_" + $abilityName + "_Description"
    foreach ($localizationPath in $localizationPaths) {
        $localized = [regex]::Matches((Text $localizationPath), '"' + [regex]::Escape($token) + '"\s+"([^\r\n"]*)"')
        Check ($localized.Count -eq 1 -and $localized[0].Groups[1].Value -eq $definition.description) ("LOCALIZATION_DESCRIPTION_MISMATCH: " + $localizationPath + ":" + $skillId)
    }
}
Check ($choiceText.Contains("rebirth_level >= (tonumber(row.unlock_rebirth_level) or 1)")) "RUNTIME_UNLOCK_THRESHOLD_CONSUMER_MISSING"
$englishStages = @("first", "third", "sixth", "tenth")
foreach ($directory in @("panorama\localization", "resource", "resource\localization")) {
    $englishText = Text (Join-Path $root ($directory + "\addon_english.txt"))
    for ($i = 0; $i -lt $orderedSkills.Count; $i++) {
        $token = "DOTA_Tooltip_ability_ability_survival_blademaster_" + $orderedSkills[$i] + "_Description"
        $localized = [regex]::Matches($englishText, '"' + [regex]::Escape($token) + '"\s+"([^\r\n"]*)"')
        Check ($localized.Count -eq 1 -and $localized[0].Groups[1].Value.StartsWith("Activates after the " + $englishStages[$i] + " ascension.")) ("ENGLISH_UNLOCK_DESCRIPTION_MISMATCH: " + $token)
        $description = $localized[0].Groups[1].Value
        if ($i -eq 1) {
            foreach ($term in @("permanent home-defending illusion", "automatically attacks", "attack damage and attack speed", "equipped appearance and effects", "1 second after death", "750%")) {
                Check ($description.Contains($term)) ("W_ILLUSION_DESCRIPTION_MISSING: " + $term)
            }
            Check (-not $description.Contains("Blade Fury")) "W_INCORRECTLY_DESCRIBES_BLADE_FURY"
        }
        if ($i -eq 2) {
            Check ($description.Contains("Blade Fury") -and $description.Contains("multiplied by 25")) "E_BLADE_FURY_DESCRIPTION_MISSING"
        }
    }
}

foreach ($contract in @(
    "q_critical_chance_pct = 30",
    "q_critical_damage_bonus_pct = 1500",
    "q_radius = 600",
    "w_clone_critical_damage_bonus_pct = 750",
    "w_clone_permanent = true",
    "e_duration = 3",
    "e_tick_interval = 1",
    "e_attribute_multiplier = 25",
    "e_radius = 600",
    "r_attack_interval_reduction = 0.1",
    "r_growth_interval = 150",
    "r_growth_pct = 1",
    "r_attack_multiplier = 3"
)) {
    Check ($runtimeText.Contains($contract)) ("GENERATED_RUNTIME_MISSING: " + $contract)
    Check ($csvText.Contains($contract.Split(" = ")[0])) ("CSV_SCHEMA_MISSING: " + $contract)
}
Check ($skillsText.Contains("skill_blademaster_exclusive")) "Q_DESCRIPTION_MISSING"
Check ($skillsText.Contains("skill_blademaster_agility")) "W_DESCRIPTION_MISSING"
Check ($skillsText.Contains("skill_blademaster_swiftness")) "E_DESCRIPTION_MISSING"
Check ($skillsText.Contains("skill_blademaster_mobility")) "R_DESCRIPTION_MISSING"
Check ($serviceText.Contains("HERO_FINAL_CRITICAL_ATTACK_DAMAGE, q_replicate")) "Q_FINAL_CRITICAL_EVENT_MISSING"
Check (-not $serviceText.Contains("HERO_MAIN_ATTACK_LANDED, q_replicate")) "Q_MAIN_ATTACK_EVENT_REMAINS"
Check ($serviceText.Contains("payload.critical ~= true")) "Q_CRITICAL_GATE_MISSING"
Check ($serviceText.Contains("payload.final_damage")) "Q_FINAL_DAMAGE_PAYLOAD_MISSING"
Check ($serviceText.Contains("non_recursive = true")) "SECONDARY_DAMAGE_RECURSION_GUARD_MISSING"
Check ($serviceText.Contains('local Q_VISUAL_UNIT = "npc_dota_hero_legion_commander"')) "Q_VISUAL_UNIT_MISSING"
Check ($serviceText.Contains('local Q_VISUAL_ABILITY = "legion_commander_overwhelming_odds"')) "Q_NATIVE_ABILITY_MISSING"
Check ($serviceText.Contains("create_visual_caster(Q_VISUAL_UNIT")) "Q_VISUAL_CASTER_MISSING"
Check ($serviceText.Contains("hide_unit_and_wearables(unit)")) "Q_VISUAL_HIDE_MISSING"
Check ($serviceText.Contains("DOTA_UNIT_ORDER_CAST_POSITION")) "Q_POSITION_ORDER_MISSING"
Check ($serviceText.Contains("AbilityIndex = native:entindex()")) "Q_POSITION_ABILITY_MISSING"
Check ($gameModeText.Contains('require("systems/blademaster_exclusive_service").init()')) "BLADEMASTER_SERVICE_INIT_MISSING"
Check ($serviceText.Contains("local position = target:GetAbsOrigin()") -and
    $serviceText.Contains("q_impact_visual(position, attacker, player_id)")) "Q_VISUAL_TARGET_POSITION_MISSING"
Check ($serviceText.Contains("function M.trigger_clone_q(player_id, clone, target, final_damage)")) "W_CLONE_Q_ENTRY_MISSING"
Check ($serviceText.Contains("prepare_combat_clone(clone, player_id)") -and
    $serviceText.Contains("native:GetAbilityName() ~= Q_ABILITY") -and
    $serviceText.Contains("clone:RemoveAbility(name)")) "W_NATIVE_ABILITIES_NOT_STRIPPED"
Check ($serviceText.Contains("clone:SetAttackCapability(DOTA_UNIT_CAP_MELEE_ATTACK)") -and
    $serviceText.Contains("clone:SetIdleAcquire(true)")) "W_NORMAL_ATTACK_CAPABILITY_MISSING"
Check ($serviceText.Contains('clone:AddNewModifier(clone, nil, "modifier_blademaster_clone"')) "W_COMBAT_MODIFIER_MISSING"
Check ($serviceText.Contains("local function guard_point(player_id, current)") -and
    $serviceText.Contains("local function guard_clone(player_id, current)") -and
    $serviceText.Contains("OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET") -and
    $serviceText.Contains("OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION")) "W_HOME_ATTACK_AND_RETURN_MISSING"
Check ($serviceText.Contains("sync_clone_stats(player_id, current)") -and
    $serviceText.Contains("guard_clone(player_id, current)")) "W_RUNTIME_SYNC_OR_GUARD_MISSING"
Check ($serviceText.Contains("e_tick_interval")) "E_PERIODIC_TICK_MISSING"
Check ($serviceText.Contains('local E_VISUAL_UNIT = "npc_dota_hero_juggernaut"')) "E_VISUAL_UNIT_MISSING"
Check ($serviceText.Contains('local E_VISUAL_ABILITY = "juggernaut_blade_fury"')) "E_NATIVE_ABILITY_MISSING"
Check ($serviceText.Contains("create_visual_caster(E_VISUAL_UNIT")) "E_VISUAL_CASTER_MISSING"
Check ($serviceText.Contains("CastAbilityNoTarget(native, player_id)")) "E_NATIVE_CAST_MISSING"
Check ($serviceText.Contains("survival_visual_only = true")) "VISUAL_ONLY_MARK_MISSING"
Check ($serviceText.Contains("SetHullRadius(0)")) "VISUAL_ZERO_HULL_MISSING"
Check ($serviceText.Contains("storms[id].visual_caster = create_storm_visual(") -and
    $serviceText.Contains("storms[id].position, payload.attacker")) "E_PARTICLE_TARGET_POSITION_MISSING"
Check ($serviceText.Contains("remove_visual_caster(storm.visual_caster)")) "E_VISUAL_CLEANUP_MISSING"
Check (-not $serviceText.Contains("E_OUTER_PARTICLE")) "E_OUTER_PARTICLE_REMAINS"
Check (-not $serviceText.Contains("e_visual_outer_count")) "E_OUTER_COUNT_CONFIG_REMAINS"
Check ($damageFilterText.Contains("attacker.survival_visual_only == true")) "VISUAL_DAMAGE_FILTER_MISSING"
Check ($serviceText.Contains("remove_visual_casters_for_owner(victim)")) "OWNER_DEATH_VISUAL_CLEANUP_MISSING"
Check ($serviceText.Contains("victim.survival_blademaster_visual_caster == true")) "VISUAL_SELF_DEATH_CLEANUP_MISSING"
Check ($serviceText.Contains("w_clone_critical_damage_bonus_pct")) "W_CLONE_CRITICAL_BONUS_MISSING"
Check ($serviceText.Contains("BLADEMASTER_BONUS_STATS_GET_REQUEST")) "R_GROWTH_REQUEST_MISSING"
Check ($statsText.Contains("blademaster_config.r_attack_multiplier")) "R_ATTACK_MULTIPLIER_PROJECTION_MISSING"
Check ($statsText.Contains("blademaster_config.q_critical_chance_pct")) "Q_CRITICAL_CHANCE_PROJECTION_MISSING"
Check ($fusionText.Contains("skill_blademaster_mobility")) "R_TOWER_INHERITANCE_MISSING"
Check ($skillSystemText.Contains('payload.hero_id == "hero_blademaster"')) "VIP_GATE_MISSING"
Check ($skillSystemText.Contains("state.unit:AddAbility(definition.ability_name)")) "ABILITY_REGISTRATION_MISSING"
Check ($skillSystemText.Contains("local function desired_ability_names(state)")) "ABILITY_BAR_ORDER_MISSING"
Check ($skillSystemText.Contains("local function rebuild_ability_layout(state, desired)")) "ABILITY_BAR_REBUILD_MISSING"
Check ($skillSystemText.Contains("local ability = state.unit:AddAbility(name)")) "ABILITY_ADD_ORDER_MISSING"
Check (-not $skillSystemText.Contains("SetAbilityIndex")) "UNRELIABLE_ABILITY_REINDEX_REMAINS"
foreach ($localizationPath in $localizationPaths) {
    $localizationText = Text $localizationPath
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_blademaster_exclusive")) "Q_LOCALIZATION_MISSING"
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_blademaster_agility")) "W_LOCALIZATION_MISSING"
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_blademaster_swiftness")) "E_LOCALIZATION_MISSING"
    Check ($localizationText.Contains("DOTA_Tooltip_ability_ability_survival_blademaster_mobility")) "R_LOCALIZATION_MISSING"
}
Check ($rewardEffectsText.Contains('skill_id = "skill_monkey_king_fury"')) "REWARD_SKILL_ID_MISSING"
Check ($skillSystemText.Contains("event_bus.subscribe(events.HERO_SKILL_REWARD_REQUEST, on_skill_reward)")) "REWARD_CONSUMER_MISSING"
Write-Host "BLADEMASTER_EXCLUSIVE_CONTRACT_PASS"
