$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$contentRoot = Resolve-Path (Join-Path $root "../../../content/dota_addons/survival")
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Read-Utf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, $utf8)
}

function Count-TopLevelKvDefinition([string]$content, [string]$name) {
    $pattern = '(?m)^(?:    )?"' + [Regex]::Escape($name) + '"\r?$'
    return [Regex]::Matches($content, $pattern).Count
}

$csvPath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "tower_fusion_runtime.csv" |
    Select-Object -First 1).FullName
$csvPath = [System.IO.Path]::GetFullPath($csvPath)
$csvLines = (Read-Utf8 $csvPath) -split "`r?`n"
$businessLine = $csvLines | Where-Object {
    $_.StartsWith("ultimate_tower,")
} | Select-Object -First 1
Check ($null -ne $businessLine) "ULTIMATE_TOWER_CSV_ROW_MISSING"
$fields = $businessLine.Split(',')
Check ($fields.Count -eq 11) "ULTIMATE_TOWER_CSV_COLUMN_COUNT_INVALID"
Check ($fields[6] -eq "3") "ULTIMATE_TOWER_BASE_ATTACK_SPEED_INVALID"
Check ($fields[7] -eq "ultimate_tower") `
    "ULTIMATE_TOWER_SKILL_BINDING_CONFIG_INVALID"
Check ($fields[8] -eq (
    "ultimate_tower_passive_1|ultimate_tower_passive_2|" +
    "ultimate_tower_passive_3|ultimate_tower_passive_4|" +
    "ultimate_tower_passive_5"
)) "ULTIMATE_TOWER_PASSIVE_ORDER_INVALID"
Check ($fields[9] -eq (
    "ability_building_blink|ability_destroy_arrow_tower"
)) "ULTIMATE_TOWER_UTILITY_ORDER_INVALID"

$bindingsPath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "ultimate_tower_skill_bindings.csv" |
    Select-Object -First 1).FullName
$bindingRows = (Read-Utf8 $bindingsPath) -split "`r?`n" | Where-Object {
    $_ -and -not $_.StartsWith("#") -and -not $_.StartsWith("binding_id,")
}
Check ($bindingRows.Count -eq 13) "ULTIMATE_TOWER_BINDING_COUNT_INVALID"
$expectedSkills = @(
    "piercing_ballista_lv05", "critical_strike_lv05", "multi_attack_lv05",
    "bounty_machine_gun_lv05", "ice_blizzard_lv05",
    "explosive_gatling_lv01", "arcane_cannon_lv05", "frost_attack_lv05",
    "death_grenade_lv01", "polar_obelisk_lv01", "lightning_strike_lv05",
    "lightning_storm_lv05", "lightning_diffusion_lv01"
)
$actualSkills = @($bindingRows | ForEach-Object { $_.Split(',')[3] })
Check (($actualSkills -join '|') -eq ($expectedSkills -join '|')) `
    "ULTIMATE_TOWER_SKILL_ORDER_INVALID"
Check (($actualSkills | Select-Object -Unique).Count -eq 13) `
    "ULTIMATE_TOWER_SKILLS_NOT_UNIQUE"
$categoryCounts = @{}
foreach ($row in $bindingRows) {
    $category = $row.Split(',')[1]
    $categoryCounts[$category] = 1 + [int]($categoryCounts[$category])
}
Check ($categoryCounts["直接作用于普通攻击"] -eq 3) `
    "ULTIMATE_DIRECT_CATEGORY_COUNT_INVALID"
Check ($categoryCounts["由普通攻击引出"] -eq 4) `
    "ULTIMATE_ATTACK_DERIVED_CATEGORY_COUNT_INVALID"
Check ($categoryCounts["面板被动"] -eq 2) `
    "ULTIMATE_PANEL_CATEGORY_COUNT_INVALID"
Check ($categoryCounts["光环"] -eq 1) "ULTIMATE_AURA_CATEGORY_COUNT_INVALID"
Check ($categoryCounts["次生技能"] -eq 3) `
    "ULTIMATE_SECONDARY_CATEGORY_COUNT_INVALID"

$tooltipCsvPath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "tooltip_definitions.csv" |
    Select-Object -First 1).FullName
$tooltipCsv = Read-Utf8 $tooltipCsvPath
$tooltipRows = Import-Csv -LiteralPath $tooltipCsvPath -Encoding UTF8
$schinese = Read-Utf8 (Join-Path $root "resource/localization/addon_schinese.txt")
$english = Read-Utf8 (Join-Path $root "resource/localization/addon_english.txt")
$abilities = Read-Utf8 (Join-Path $root "scripts/npc/npc_abilities_custom.txt")
$abilityTooltip = Read-Utf8 (Join-Path $contentRoot `
    "panorama/scripts/custom_game/ability_tooltip.js")
$tooltipExpectations = @(
    @("ultimate_tower_passive_1", "终极塔·普通攻击强化", "对空塔、死亡塔和多重塔", "Ultimate Tower: Attack Enhancements", "razor_static_link"),
    @("ultimate_tower_passive_2", "终极塔·攻击触发", "机枪塔、冰霜塔和神秘塔", "Ultimate Tower: Attack Triggers", "warlock_fatal_bonds"),
    @("ultimate_tower_passive_3", "终极塔·面板被动", "冰霜塔和死亡塔", "Ultimate Tower: Passive Effects", "windrunner_focusfire"),
    @("ultimate_tower_passive_4", "终极塔·光环", "冰霜塔的范围光环", "Ultimate Tower: Aura", "vengefulspirit_nether_swap"),
    @("ultimate_tower_passive_5", "终极塔·次生技能", "闪电塔的闪电链、风暴和扩散", "Ultimate Tower: Secondary Skills", "crystal_maiden_brilliance_aura")
)
foreach ($expected in $tooltipExpectations) {
    $abilityId, $name, $description, $englishName, $icon = $expected
    Check ((Count-TopLevelKvDefinition $abilities $abilityId) -eq 1) `
        "ULTIMATE_ABILITY_KV_DEFINITION_INVALID_$abilityId"
    $tooltipRow = $tooltipRows | Where-Object {
        $_.tooltip_id -eq "ability:$abilityId"
    } | Select-Object -First 1
    Check ($null -ne $tooltipRow -and $tooltipRow.tooltip_type -eq "ability" `
        -and $tooltipRow.id -eq $abilityId -and $tooltipRow.name -eq $name) `
        "ULTIMATE_TOOLTIP_CSV_NAME_INVALID_$abilityId"
    Check ($null -ne $tooltipRow -and $tooltipRow.desc.Contains($description)) `
        "ULTIMATE_TOOLTIP_CSV_DESCRIPTION_INVALID_$abilityId"
    Check ($schinese.Contains(
        '"DOTA_Tooltip_ability_' + $abilityId + '" "' + $name + '"')) `
        "ULTIMATE_TOOLTIP_SCHINESE_NAME_INVALID_$abilityId"
    Check ($schinese.Contains($description)) `
        "ULTIMATE_TOOLTIP_SCHINESE_DESCRIPTION_INVALID_$abilityId"
    Check ($schinese.Contains("由多个技能复合而成")) `
        "ULTIMATE_TOOLTIP_SCHINESE_UNIFIED_PREFIX_MISSING_$abilityId"
    Check ($english.Contains(
        '"DOTA_Tooltip_ability_' + $abilityId + '" "' + $englishName + '"')) `
        "ULTIMATE_TOOLTIP_ENGLISH_NAME_INVALID_$abilityId"
    Check ($english.Contains("Composed of multiple skills")) `
        "ULTIMATE_TOOLTIP_ENGLISH_UNIFIED_PREFIX_MISSING_$abilityId"
    $abilityStart = $abilities.IndexOf('"' + $abilityId + '"')
    $abilityEnd = $abilities.IndexOf('"MaxLevel"', $abilityStart)
    Check ($abilityStart -ge 0 -and $abilityEnd -gt $abilityStart) `
        "ULTIMATE_ABILITY_KV_MISSING_$abilityId"
    $abilityBlock = $abilities.Substring($abilityStart, $abilityEnd - $abilityStart)
    Check ($abilityBlock.Contains('"AbilityTextureName" "' + $icon + '"')) `
        "ULTIMATE_ABILITY_ICON_INVALID_$abilityId"
}
Check (-not $abilities.Contains('"ultimate_tower_passive_6"')) `
    "ULTIMATE_PASSIVE_6_KV_REMAINS"
Check (-not $abilities.Contains('"ultimate_tower_passive_7"')) `
    "ULTIMATE_PASSIVE_7_KV_REMAINS"
Check ($abilityTooltip.Contains("function nativeTooltipOwners(sourcePanel)")) `
    "ABILITY_TOOLTIP_NATIVE_OWNER_DISCOVERY_MISSING"
Check ($abilityTooltip.Contains('current.FindChildTraverse("AbilityButton")') -and `
    $abilityTooltip.Contains('current.FindChildTraverse("ButtonWell")') -and `
    $abilityTooltip.Contains('current.FindChildTraverse("AbilityImage")')) `
    "ABILITY_TOOLTIP_NATIVE_OWNER_TREE_INCOMPLETE"
Check ($abilityTooltip.Contains("function suppressNativeTooltip(abilityIndex, sourcePanel)") -and `
    $abilityTooltip.Contains("nativeTooltipSuppressionSerial += 1") -and `
    $abilityTooltip.Contains("[0.0, 0.03, 0.08, 0.16, 0.30]")) `
    "ABILITY_TOOLTIP_HOVER_SUPPRESSION_MISSING"
Check ($abilityTooltip.Contains("suppressNativeTooltip(abilityIndex, sourcePanel);") -and `
    $abilityTooltip.Contains("Number(activeAbilityIndex) !== Number(abilityIndex)")) `
    "ABILITY_TOOLTIP_SUPPRESSION_LIFECYCLE_UNBOUND"
Check ($abilityTooltip.Contains("if (sourceInside) {") -and `
    $abilityTooltip.Contains("hideNativeTooltip(proxy);")) `
    "ABILITY_TOOLTIP_LONG_HOVER_SUPPRESSION_MISSING"
Check (-not $abilityTooltip.Contains('$.DispatchEvent("DOTAShowAbilityTooltip"')) `
    "ABILITY_TOOLTIP_NATIVE_SHOW_FALLBACK_PRESENT"

$stageCsvPath = (Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Recurse -File -Filter "builder_ability_stages.csv" |
    Select-Object -First 1).FullName
$stageRows = Import-Csv -LiteralPath $stageCsvPath -Encoding UTF8 | Where-Object {
    $_.stage_id -and -not $_.stage_id.StartsWith("#") -and $_.enabled -eq "1"
}
foreach ($abilityId in @($stageRows.ability_name | Select-Object -Unique)) {
    Check ((Count-TopLevelKvDefinition $abilities $abilityId) -eq 1) `
        "BUILDER_STAGE_ABILITY_KV_DEFINITION_INVALID_$abilityId"
}
foreach ($slot in 1..6) {
    $placeholder = "ability_survival_builder_slot_${slot}_placeholder"
    Check ((Count-TopLevelKvDefinition $abilities $placeholder) -eq 1) `
        "BUILDER_PLACEHOLDER_KV_DEFINITION_INVALID_$slot"
}
$arrowPattern = '(?ms)^    "ability_build_arrow_tower"\r?\n' +
    '    \{\r?\n' +
    '        "BaseClass"\s+"ability_lua"\r?\n' +
    '        "ScriptFile"\s+"abilities/ability_build_arrow_tower"\r?\n' +
    '        "AbilityBehavior"\s+"DOTA_ABILITY_BEHAVIOR_POINT"\r?\n' +
    '        "AbilityTextureName"\s+"drow_ranger_marksmanship"\r?\n' +
    '        "MaxLevel"\s+"1"'
Check ([Regex]::IsMatch($abilities, $arrowPattern)) `
    "BUILD_ARROW_TOWER_KV_BLOCK_INVALID"

$generated = Read-Utf8 (Join-Path $root `
    "scripts/vscripts/config/generated/tower_fusion_runtime.lua")
Check ($generated.Contains('passive_slot_ability_ids = {' +
    '"ultimate_tower_passive_1", "ultimate_tower_passive_2", ' +
    '"ultimate_tower_passive_3", "ultimate_tower_passive_4", ' +
    '"ultimate_tower_passive_5"}')) "GENERATED_PASSIVE_ORDER_INVALID"
Check ($generated.Contains('utility_ability_ids = {' +
    '"ability_building_blink", "ability_destroy_arrow_tower"}')) `
    "GENERATED_UTILITY_ORDER_INVALID"
Check ($generated.Contains('base_attack_speed = 3')) `
    "GENERATED_BASE_ATTACK_SPEED_INVALID"
Check (-not $generated.Contains('ultimate_tower_passive_6')) `
    "GENERATED_PASSIVE_6_REMAINS"
Check (-not $generated.Contains('ultimate_tower_passive_7')) `
    "GENERATED_PASSIVE_7_REMAINS"

$service = Read-Utf8 (Join-Path $root `
    "scripts/vscripts/systems/tower_fusion_service.lua")
$passiveScript = Read-Utf8 (Join-Path $root `
    "scripts/vscripts/abilities/ability_tower_passive.lua")
$events = Read-Utf8 (Join-Path $root "scripts/vscripts/core/events.lua")
$router = Read-Utf8 (Join-Path $root `
    "scripts/vscripts/ui/ui_request_router.lua")
$runtime = Read-Utf8 (Join-Path $root `
    "scripts/vscripts/ui/ability_runtime_service.lua")
$move = Read-Utf8 (Join-Path $contentRoot `
    "panorama/scripts/custom_game/building_move.js")
$units = Read-Utf8 (Join-Path $root "scripts/npc/npc_units_custom.txt")

$mainPassive = $service.IndexOf(
    "ipairs(config().passive_slot_ability_ids or {})")
$mainUtility = $service.IndexOf(
    "ipairs(config().utility_ability_ids or {})")
$mainSkills = $service.LastIndexOf("add_ultimate_skills(unit)")
Check ($mainSkills -ge 0) "MAIN_SKILL_ATTACHMENT_MISSING"
Check ($mainPassive -ge 0) "MAIN_PASSIVE_ATTACHMENT_MISSING"
Check ($mainUtility -gt $mainPassive) "MAIN_UTILITY_NOT_AFTER_PASSIVES"
Check ($mainSkills -gt $mainUtility) "REAL_SKILLS_NOT_AFTER_VISIBLE_SLOTS"
Check ($service.Contains("tower_skills.apply(unit, skill_ids)")) `
    "REAL_ROUTE_SKILLS_NOT_ATTACHED_TO_MAIN_TOWER"
Check ($service.Contains(
    'unit:AddNewModifier(unit, nil, "modifier_tower_attack_effects"')) `
    "MAIN_TOWER_ATTACK_EFFECTS_MISSING"
Check ($service.Contains("unit:SetBaseAttackTime(1 / attack_speed)")) `
    "MAIN_TOWER_BASE_ATTACK_TIME_MISSING"
Check ($service.Contains("unit.survival_attack_speed = attack_speed")) `
    "MAIN_TOWER_ATTACK_SPEED_DIAGNOSTIC_MISSING"
Check ($service.Contains("ability:SetHidden(true)")) `
    "REAL_SKILLS_NOT_HIDDEN"
Check ($passiveScript.Contains(
    'require("config/generated/tower_fusion_runtime")')) `
    "DISPLAY_PASSIVE_CONFIG_NOT_LOADED"
Check ($passiveScript.Contains(
    "ipairs(definition.passive_slot_ability_ids or {})")) `
    "DISPLAY_PASSIVE_GLOBAL_REGISTRATION_MISSING"
Check ($passiveScript.Contains("_G[ability_id] = M")) `
    "DISPLAY_PASSIVE_CLASS_NOT_REGISTERED"
Check (-not $service.Contains("create_proxy")) "FUSION_PROXY_CREATION_REMAINS"
Check (-not $service.Contains("survival_ultimate_tower_proxy")) `
    "FUSION_PROXY_IDENTITY_REMAINS"
Check (-not $service.Contains("state.streams")) "FUSION_STREAM_STATE_REMAINS"
Check (-not $service.Contains("ultimate_tower_streams")) `
    "FUSION_STREAM_SCHEDULER_REMAINS"
Check ($service.Contains("state_by_entindex")) "FUSION_ENTINDEX_INDEX_MISSING"
Check ($service.Contains("CreateUnitByName(")) `
    "FUSION_DIRECT_CREATE_MISSING"
Check ($service.Contains("BUILDING_FUSION_CONSUME_REQUEST")) `
    "FUSION_DIRECT_CONSUME_MISSING"
Check ($service.Contains("move_state(state")) "FUSION_ATOMIC_MOVE_MISSING"
Check (-not $service.Contains("SetInvulnerable")) `
    "ULTIMATE_TOWER_UNSUPPORTED_INVULNERABLE_API_REMAINS"

foreach ($name in @(
    "TOWER_FUSION_MOVE_REQUEST",
    "TOWER_FUSION_DESTROY_REQUEST",
    "TOWER_FUSION_RUNTIME_CHANGED",
    "TOWER_FUSION_RUNTIME_REMOVED"
)) {
    Check ($events.Contains($name)) "FUSION_EVENT_MISSING_$name"
}
Check ($router.Contains("events.TOWER_FUSION_MOVE_REQUEST")) `
    "FUSION_MOVE_ROUTE_MISSING"
Check ($router.Contains("events.TOWER_FUSION_DESTROY_REQUEST")) `
    "FUSION_DESTROY_ROUTE_MISSING"
Check ($runtime.Contains(
    "events.TOWER_FUSION_RUNTIME_CHANGED, publish_unit")) `
    "FUSION_RUNTIME_PUBLISH_MISSING"
Check ($runtime.Contains(
    "events.TOWER_FUSION_RUNTIME_REMOVED, clear_unit")) `
    "FUSION_RUNTIME_CLEAR_MISSING"

Check ($move.Contains("function isUtilityTower(unit)")) `
    "UTILITY_TOWER_CLIENT_DETECTION_MISSING"
Check ($move.Contains("abilityOnUnit(unit, MOVE_ABILITY) >= 0")) `
    "UTILITY_MOVE_PAIR_CHECK_MISSING"
Check ($move.Contains("abilityOnUnit(unit, DESTROY_ABILITY) >= 0")) `
    "UTILITY_DESTROY_PAIR_CHECK_MISSING"
Check (-not $move.Contains("if (unit < 0 || !isArrowTower(unit))")) `
    "ARROW_ONLY_CLIENT_GUARD_REMAINS"
Check ($move.Contains('if (normalized !== "D") return false;')) `
    "BUILDER_BLINK_FALLTHROUGH_MISSING"

$ultimateStart = $units.IndexOf('"npc_dota_unit_ultimate_tower"')
$ultimateEnd = $units.IndexOf('"building_research_lab"', $ultimateStart)
Check ($ultimateStart -ge 0 -and $ultimateEnd -gt $ultimateStart) `
    "ULTIMATE_TOWER_NPC_BLOCK_MISSING"
$ultimateBlock = $units.Substring($ultimateStart, $ultimateEnd - $ultimateStart)
Check ($ultimateBlock.Contains('"AbilityLayout"          "7"')) `
    "ULTIMATE_TOWER_LAYOUT_NOT_SEVEN"
Check (-not $ultimateBlock.Contains('"Ability1"')) `
    "ULTIMATE_TOWER_NATIVE_ABILITY_PRESENT"
Check (-not $ultimateBlock.Contains("undying")) `
    "UNDYING_PLACEHOLDER_REFERENCE_PRESENT"

Write-Output "ULTIMATE_TOWER_SKILL_BAR_CONTRACT_PASS"