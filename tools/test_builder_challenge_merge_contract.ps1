$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$contentRoot = $root -replace '\\game\\dota_addons\\survival$', '\content\dota_addons\survival'

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText(
        $Path,
        [Text.UTF8Encoding]::new($false, $true)
    )
}

function Check($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$stages = Read-Utf8 (Join-Path $root 'data\csv\建筑与工人系统\builder_ability_stages.csv')
$generatedStages = Read-Utf8 (Join-Path $root 'scripts\vscripts\config\generated\builder_ability_stages.lua')
$levels = Read-Utf8 (Join-Path $root 'data\csv\建筑与工人系统\building_levels.csv')
$construction = Read-Utf8 (Join-Path $root 'data\csv\建筑与工人系统\building_construction_rules.csv')
$visuals = Read-Utf8 (Join-Path $root 'data\csv\建筑与工人系统\building_visual_levels.csv')
$abilities = Read-Utf8 (Join-Path $root 'scripts\npc\npc_abilities_custom.txt')
$units = Read-Utf8 (Join-Path $root 'scripts\npc\npc_units_custom.txt')
$addon = Read-Utf8 (Join-Path $root 'scripts\vscripts\addon_game_mode.lua')
$progression = Read-Utf8 (Join-Path $root 'scripts\vscripts\systems\builder_progression_system.lua')
$buildings = Read-Utf8 (Join-Path $root 'scripts\vscripts\config\buildings_config.lua')
$runtime = Read-Utf8 (Join-Path $root 'scripts\vscripts\ui\ability_runtime_builder.lua')
$router = Read-Utf8 (Join-Path $root 'scripts\vscripts\ui\ui_request_router.lua')
$combat = Read-Utf8 (Join-Path $contentRoot 'panorama\scripts\custom_game\combat_stats.js')
$takeover = Read-Utf8 (Join-Path $contentRoot 'panorama\scripts\custom_game\hud_takeover.js')
$tooltip = Read-Utf8 (Join-Path $contentRoot 'panorama\scripts\custom_game\ability_tooltip.js')

Check ($stages.Contains('ability_build_advanced_research_lab,2,4,building_advanced_research_lab,1,building_research_lab,0,1')) 'ADVANCED_RESEARCH_W_STAGE_MISSING'
Check ($stages.Contains('ability_build_challenge,6,1,building_challenge,1,building_research_lab,0,1')) 'CHALLENGE_A_STAGE_MISSING'
Check ($generatedStages -match 'ability_name = "ability_build_challenge"[^\r\n]+slot_order = 6[^\r\n]+requires_building_id = "building_research_lab"') 'CHALLENGE_A_GENERATED_MISSING'
Check (($levels -split "`n" | Where-Object { $_ -match '^building_advanced_research_lab_lv01,' }).Count -eq 1) 'ADVANCED_RESEARCH_LEVEL_DUPLICATED'
Check ($levels -match 'building_advanced_research_lab_lv01,building_advanced_research_lab,1,[^\r\n]+,2500,8,100,0,0,4,') 'ADVANCED_RESEARCH_LEVEL_INVALID'
Check ($levels -match 'building_challenge_lv01,building_challenge,1,[^\r\n]+,2500,8,100,0,0,1,') 'CHALLENGE_LEVEL_INVALID'
Check ($construction.Contains('building_advanced_research_lab,200,3,') -and $construction.Contains('building_challenge,200,3,')) 'MERGED_CONSTRUCTION_ROWS_MISSING'
Check ($visuals.Contains('building_advanced_research_lab,1,models/props_structures/radiant_ancient001.vmdl,0.34,') -and $visuals.Contains('building_challenge,1,models/props_structures/radiant_ancient001.vmdl,0.34,')) 'MERGED_VISUAL_ROWS_MISSING'
Check ($abilities.Contains('"ability_build_advanced_research_lab"') -and $abilities.Contains('"ability_build_challenge"')) 'MERGED_BUILD_ABILITIES_MISSING'
foreach ($index in 1..5) {
    Check ($abilities.Contains(('"ability_challenge_monster_0{0}"' -f $index))) ('CHALLENGE_ABILITY_0{0}_MISSING' -f $index)
    Check ($addon.Contains(('require("abilities/ability_challenge_monster_0{0}")' -f $index))) ('CHALLENGE_REQUIRE_0{0}_MISSING' -f $index)
}
Check ($abilities.Contains('"ability_challenge_auto_summon"')) 'CHALLENGE_AUTO_ABILITY_MISSING'
Check ($units -match '"building_challenge"[\s\S]+?"AbilityLayout"\s+"6"') 'CHALLENGE_UNIT_LAYOUT_INVALID'
Check ($units -match '"building_advanced_research_lab"[\s\S]+?"AbilityLayout"\s+"12"') 'ADVANCED_RESEARCH_UNIT_LAYOUT_INVALID'
Check ($buildings.Contains('M.building_challenge =') -and $buildings.Contains('M.building_advanced_research_lab =')) 'MERGED_BUILDING_CONFIG_MISSING'
Check ($buildings.Contains('local builder_ability_stages = require(') -and $buildings.Contains('definition.requires_building_id = builder_stage.requires_building_id')) 'BUILDING_PREREQUISITE_STAGE_PROJECTION_MISSING'
Check (-not ($buildings -match 'M\.building_research_lab\s*=\s*\{[\s\S]+?requires_building_id\s*=\s*"building_research_lab"')) 'RESEARCH_LAB_SELF_PREREQUISITE_PRESENT'
Check ($runtime.Contains('ability_build_challenge = buildings.building_challenge')) 'CHALLENGE_RUNTIME_DEFINITION_MISSING'
Check ($progression.Contains('function enumerate_abilities(builder)') -and $progression.Contains('function layout_is_valid(builder, desired, entries)') -and $progression.Contains('index = domain_start + BUILDER_SLOT_COUNT')) 'BUILDER_LAYOUT_VALIDATION_MISSING'
Check ($combat.Contains('builderHotkeysBySlotOrder') -and $combat.Contains('function builderDisplaySlotForKey(key)') -and $combat.Contains('builder_slot_order')) 'BUILDER_A_INPUT_MISSING'
Check ($takeover.Contains('builderHotkeysBySlotOrder') -and $takeover.Contains('builderRuntime.builder_slot_order')) 'BUILDER_A_LABEL_MISSING'
Check ($combat.Contains('abilityName === "ability_challenge_auto_summon"') -and $combat.Contains('(behavior & 512) === 0')) 'CHALLENGE_TOGGLE_CLIENT_ROUTE_MISSING'
Check ($tooltip.Contains('abilityName === "ability_challenge_auto_summon"')) 'CHALLENGE_TOGGLE_PROXY_MISSING'
Check ($router.Contains('CHALLENGE_AUTO_DISPATCHED') -and $router.Contains('RESEARCH_DISPATCHED')) 'MERGED_SERVER_DIRECT_ROUTES_MISSING'

Write-Output 'BUILDER_CHALLENGE_MERGE_CONTRACT_PASS'