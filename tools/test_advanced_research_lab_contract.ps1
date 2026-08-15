$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$contentRoot = $root -replace '\\game\\dota_addons\\survival$', '\content\dota_addons\survival'

function Read-Utf8([string]$relative) {
    $path = Join-Path $root $relative
    $stream = [IO.File]::Open(
        $path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    )
    try {
        $reader = [IO.StreamReader]::new(
            $stream,
            [Text.UTF8Encoding]::new($false, $true),
            $true
        )
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function Check($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$levelsBytes = [IO.File]::ReadAllBytes((Join-Path $root 'data\csv\建筑与工人系统\building_levels.csv'))
$levels = [Text.Encoding]::GetEncoding(54936).GetString($levelsBytes)
$generatedLevels = Read-Utf8 'scripts\vscripts\config\generated\building_levels.lua'
$stages = Read-Utf8 'data\csv\建筑与工人系统\builder_ability_stages.csv'
$generatedStages = Read-Utf8 'scripts\vscripts\config\generated\builder_ability_stages.lua'
$visuals = Read-Utf8 'data\csv\建筑与工人系统\building_visual_levels.csv'
$generatedVisuals = Read-Utf8 'scripts\vscripts\config\generated\building_visual_levels.lua'
$buildings = Read-Utf8 'scripts\vscripts\config\buildings_config.lua'
$shop = Read-Utf8 'scripts\vscripts\systems\shop_system.lua'
$catalog = Read-Utf8 'scripts\vscripts\systems\shop_catalog.lua'
$router = Read-Utf8 'scripts\vscripts\ui\ui_request_router.lua'
$researchAbilities = Read-Utf8 'data\csv\建筑与工人系统\research_lab_abilities.csv'
$generatedResearchAbilities = Read-Utf8 'scripts\vscripts\config\generated\research_lab_abilities.lua'
$technologyDefinitions = Read-Utf8 'data\csv\建筑与工人系统\technology_definitions.csv'
$generatedTechnologies = Read-Utf8 'scripts\vscripts\config\generated\technology_definitions.lua'
$researchConfig = Read-Utf8 'scripts\vscripts\config\research_technology_config.lua'
$runtimeBuilder = Read-Utf8 'scripts\vscripts\ui\ability_runtime_builder.lua'
$runtimeService = Read-Utf8 'scripts\vscripts\ui\ability_runtime_service.lua'
$abilitySync = Read-Utf8 'scripts\vscripts\systems\research_lab_ability_sync.lua'
$projection = Read-Utf8 'scripts\vscripts\ui\ui_projection.lua'
$ui = [IO.File]::ReadAllText(
    (Join-Path $contentRoot 'panorama\scripts\custom_game\shop_ui.js'),
    [Text.UTF8Encoding]::new($false, $true)
)
$css = [IO.File]::ReadAllText(
    (Join-Path $contentRoot 'panorama\styles\custom_game\shop.css'),
    [Text.UTF8Encoding]::new($false, $true)
)
$kv = Read-Utf8 'scripts\npc\npc_abilities_custom.txt'
$units = Read-Utf8 'scripts\npc\npc_units_custom.txt'
$hud = [IO.File]::ReadAllText(
    (Join-Path $contentRoot 'panorama\layout\custom_game\survival_hud.xml'),
    [Text.UTF8Encoding]::new($false, $true)
)
$combat = [IO.File]::ReadAllText(
    (Join-Path $contentRoot 'panorama\scripts\custom_game\combat_stats.js'),
    [Text.UTF8Encoding]::new($false, $true)
)
$takeover = [IO.File]::ReadAllText(
    (Join-Path $contentRoot 'panorama\scripts\custom_game\hud_takeover.js'),
    [Text.UTF8Encoding]::new($false, $true)
)
$tooltip = [IO.File]::ReadAllText(
    (Join-Path $contentRoot 'panorama\scripts\custom_game\ability_tooltip.js'),
    [Text.UTF8Encoding]::new($false, $true)
)

Check ($levels -match 'building_advanced_research_lab_lv01,building_advanced_research_lab,1,[^\r\n]+,2500,8,100,0,0,4,') 'ADVANCED_RESEARCH_COST_CSV_INVALID'
Check ($generatedLevels -match 'building_id = "building_advanced_research_lab"[^\r\n]+wood_cost = 100') 'ADVANCED_RESEARCH_COST_GENERATED_INVALID'
Check ($stages.Contains('ability_build_advanced_research_lab,2,4,building_advanced_research_lab,1,building_research_lab,0,1')) 'ADVANCED_RESEARCH_W_REPLACEMENT_STAGE_MISSING'
Check ($generatedStages -match 'ability_name = "ability_build_advanced_research_lab"[^\r\n]+slot_order = 2[^\r\n]+required_city_level = 4[^\r\n]+requires_building_id = "building_research_lab"') 'ADVANCED_RESEARCH_STAGE_GENERATED_INVALID'
Check ($visuals.Contains('building_advanced_research_lab,1,models/props_structures/radiant_ancient001.vmdl,0.34,')) 'ADVANCED_RESEARCH_VISUAL_CSV_INVALID'
Check ($generatedVisuals -match 'building_id = "building_advanced_research_lab"[^\r\n]+model_scale = 0\.34') 'ADVANCED_RESEARCH_VISUAL_GENERATED_INVALID'
Check ($kv.Contains('"ability_build_advanced_research_lab"')) 'ADVANCED_RESEARCH_ABILITY_KV_MISSING'
Check ($units.Contains('"building_advanced_research_lab"')) 'ADVANCED_RESEARCH_UNIT_KV_MISSING'
Check ($units -match '"building_advanced_research_lab"[\s\S]+?"AbilityLayout"\s+"12"') 'ADVANCED_RESEARCH_LAYOUT_INVALID'
Check (($researchAbilities -split "`n" | Where-Object { $_ -match '^ability_research_' }).Count -eq 19) 'RESEARCH_ABILITY_CSV_COUNT_INVALID'
$researchRows = @($researchAbilities | ConvertFrom-Csv)
Check (@($researchRows | Where-Object { $_.building_id -eq 'building_research_lab' }).Count -eq 9) 'STANDARD_RESEARCH_ABILITY_CSV_COUNT_INVALID'
Check (@($researchRows | Where-Object { $_.building_id -eq 'building_advanced_research_lab' }).Count -eq 10) 'ADVANCED_RESEARCH_ABILITY_CSV_COUNT_INVALID'
Check (($generatedResearchAbilities -split 'ability_name = "ability_research_').Count -eq 20) 'RESEARCH_GENERATED_COUNT_INVALID'
Check ($researchAbilities.Contains('ability_research_ars_01,building_advanced_research_lab,ARS-01,researcher_lumberjack_attack_growth,ars_01,1,1,伐木工攻击成长,研究伐木工攻击成长的下一级。等级、费用、前置与效果读取科技配置。,furion_force_of_nature,1,高级研究所Q槽')) 'ARS_01_ICON_CSV_INVALID'
Check ($generatedResearchAbilities -match 'ability_name = "ability_research_ars_01"[^\r\n]+icon_name = "furion_force_of_nature"') 'ARS_01_ICON_GENERATED_INVALID'
Check ($kv -match '"ability_research_ars_01"\s*\{[^{}]*"AbilityTextureName"\s*"furion_force_of_nature"') 'ARS_01_ICON_KV_INVALID'
Check ($researchAbilities.Contains('ability_research_lumberjack_efficiency,building_research_lab,RS-04,lumberjack_efficiency,lumberjack_efficiency,1,2')) 'STANDARD_RESEARCH_W_MAPPING_INVALID'
Check ($researchAbilities.Contains('ability_research_tower_attack,building_research_lab,RS-06,tower_attack,tower_attack,1,3')) 'STANDARD_RESEARCH_E_MAPPING_INVALID'
Check ($researchAbilities.Contains('ability_research_wall_health,building_research_lab,RS-08,wall_health,wall_health,1,4')) 'STANDARD_RESEARCH_R_MAPPING_INVALID'
Check ($researchAbilities.Contains('ability_research_advanced_lumberjack_efficiency,building_research_lab,RS-05,advanced_lumberjack_efficiency,advanced_lumberjack_efficiency,1,5')) 'STANDARD_RESEARCH_T_MAPPING_INVALID'
Check ($researchAbilities.Contains('ability_research_lumberjack_crit,building_research_lab,RS-03,lumberjack_crit,lumberjack_crit,1,6')) 'STANDARD_RESEARCH_A_MAPPING_INVALID'
Check ($technologyDefinitions -match 'advanced_tower_attack_01,advanced_tower_attack,[^\r\n]+,tower_attack,10,1,20,') 'ADVANCED_TOWER_UNLOCK_CSV_INVALID'
Check ($technologyDefinitions -match 'advanced_wall_health_01,advanced_wall_health,[^\r\n]+,wall_health,10,1,20,') 'ADVANCED_WALL_UNLOCK_CSV_INVALID'
Check ($technologyDefinitions -match 'researcher_hero_final_damage_01,[^\r\n]+,3,,') 'HERO_FINAL_DAMAGE_REBIRTH_CSV_INVALID'
Check ($technologyDefinitions -match 'researcher_hero_armor_reduction_01,[^\r\n]+,3,,') 'HERO_ARMOR_REBIRTH_CSV_INVALID'
Check ($technologyDefinitions -match 'researcher_hero_attack_01,[^\r\n]+,3,,') 'HERO_ATTACK_REBIRTH_CSV_INVALID'
Check ($generatedTechnologies -match 'technology_id = "advanced_tower_attack_01"[^\r\n]+unlock_required_level = 10') 'ADVANCED_TOWER_UNLOCK_GENERATED_INVALID'
Check ($generatedTechnologies -match 'technology_id = "advanced_wall_health_01"[^\r\n]+unlock_required_level = 10') 'ADVANCED_WALL_UNLOCK_GENERATED_INVALID'
Check ($researchConfig.Contains('require("config/generated/technology_definitions")')) 'RESEARCH_GENERATED_SOURCE_MISSING'
Check (-not $researchConfig.Contains('gold_base')) 'RESEARCH_HANDWRITTEN_COST_PRESENT'
Check ($buildings.Contains('abilities = research_lab_skill_names')) 'STANDARD_RESEARCH_BUILDING_BINDING_MISSING'
Check ($buildings.Contains('research_lab_ability_sync.initial_abilities')) 'ADVANCED_RESEARCH_BUILDING_BINDING_MISSING'
Check ($abilitySync.Contains('local function desired_rows')) 'RESEARCH_CHAIN_RESOLVER_MISSING'
Check ($abilitySync.Contains('ability:SetAbilityIndex')) 'RESEARCH_FIXED_SLOT_MISSING'
Check ($abilitySync.Contains('and current < maximum(row)')) 'RESEARCH_MAX_LEVEL_DISABLE_MISSING'
Check ($runtimeService.Contains('sync_research_ability_active')) 'RESEARCH_RUNTIME_ACTIVATION_SYNC_MISSING'
Check ($catalog.Contains('allowed_in_research_scope')) 'ADVANCED_RESEARCH_EXCLUSIVE_FILTER_MISSING'
Check ($catalog.Contains('definition.building_id == "advanced_research_lab"')) 'ARS_IDENTITY_FILTER_MISSING'
Check ($shop.Contains('SHOP_AUTO_RESEARCH_TOGGLE_REQUEST')) 'AUTO_RESEARCH_SERVER_EVENT_MISSING'
Check ($shop.Contains('source = "advanced_auto_research"')) 'AUTO_RESEARCH_SHARED_PURCHASE_PATH_MISSING'
Check ($shop.Contains('for _, definition in ipairs(research_config.technologies)')) 'AUTO_RESEARCH_ORDER_SOURCE_MISSING'
Check ($shop.Contains('queue_auto_research(team, AUTO_RESEARCH_RETRY_INTERVAL)')) 'AUTO_RESEARCH_RETRY_MISSING'
Check ($shop.Contains('validate_research_source')) 'ADVANCED_RESEARCH_SOURCE_VALIDATION_MISSING'
Check ($shop.Contains('return { ok = false, error = "research_source_required" }')) 'RESEARCH_SOURCE_REQUIRED_MISSING'
Check ($router.Contains('ui_shop_auto_research_toggle_request')) 'AUTO_RESEARCH_UI_ROUTE_MISSING'
Check ($router.Contains('source_entindex = tonumber(payload.source_entindex)')) 'SHOP_PURCHASE_SOURCE_ROUTE_MISSING'
Check ($router.Contains('source = "research_lab_ability"')) 'STANDARD_RESEARCH_DIRECT_SOURCE_MISSING'
Check ($router.Contains('research_lab_abilities.by_id[ability_name]')) 'STANDARD_RESEARCH_TRUSTED_MAPPING_MISSING'
Check ($router.Contains('building.building_id ~= research_upgrade.building_id')) 'RESEARCH_SOURCE_BUILDING_CHECK_MISSING'
Check ($router.Contains('tonumber(building.player_id) ~= player_id')) 'STANDARD_RESEARCH_SOURCE_OWNER_CHECK_MISSING'
Check ($runtimeBuilder.Contains('research_status_code')) 'STANDARD_RESEARCH_RUNTIME_STATUS_MISSING'
Check ($runtimeBuilder.Contains('research_effect_next')) 'STANDARD_RESEARCH_RUNTIME_EFFECT_MISSING'
Check ($runtimeService.Contains('research_events.STATE_GET_REQUESTED')) 'STANDARD_RESEARCH_LEGACY_LEVEL_READ_MISSING'
Check ($runtimeService.Contains('TECHNOLOGY_RESEARCH_STATE_CHANGED')) 'STANDARD_RESEARCH_START_REFRESH_MISSING'
Check ($runtimeService.Contains('research_events.LEVEL_CHANGED')) 'STANDARD_RESEARCH_COMPLETE_REFRESH_MISSING'
Check ($projection.Contains('building_advanced_research_lab')) 'ADVANCED_RESEARCH_UI_UNLOCK_MISSING'
Check ($projection.Contains('BUILDING_LIST_REQUEST')) 'ADVANCED_RESEARCH_UI_RECOVERY_MISSING'
Check ($projection.Contains('and 1 or 0')) 'ADVANCED_RESEARCH_UI_UNLOCK_TYPE_INVALID'
Check ($shop.Contains('local function team_player')) 'AUTO_RESEARCH_TEAM_PLAYER_FALLBACK_MISSING'
Check ($ui.Contains('card.SetPanelEvent("onactivate"')) 'RESEARCH_LEFT_CLICK_MISSING'
Check ($ui.Contains('card.SetPanelEvent("oncontextmenu"')) 'RESEARCH_RIGHT_CLICK_MISSING'
Check ($ui.Contains('ui_shop_auto_research_toggle_request')) 'AUTO_RESEARCH_CLIENT_EVENT_MISSING'
Check (-not $ui.Contains('selectedResearchSource')) 'LEGACY_SELECTED_RESEARCH_SOURCE_PRESENT'
Check (-not $hud.Contains('CustomResearchButton')) 'LEGACY_GLOBAL_RESEARCH_BUTTON_PRESENT'
Check (-not $hud.Contains('ShopModeResearch')) 'LEGACY_RESEARCH_MODE_TOGGLE_PRESENT'
Check ($takeover.Contains('advancedResearchHotkeys = ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G"]')) 'ADVANCED_RESEARCH_HOTKEYS_MISSING'
Check ($takeover.Contains('researchHotkeys = ["Q", "W", "E", "R", "T", "A"]')) 'STANDARD_RESEARCH_HOTKEYS_MISSING'
Check (-not $takeover.Contains('AdvancedResearchGrid')) 'ADVANCED_RESEARCH_TWO_ROW_LAYOUT_PRESENT'
Check (-not $takeover.Contains('advancedGrid')) 'ADVANCED_RESEARCH_GRID_LOGIC_PRESENT'
Check ($takeover.Contains('function abilityTakeoverEnabled()') -and $takeover.Contains('return takeover.abilities && !researchLabSelected();')) 'RESEARCH_NATIVE_ABILITY_MODE_MISSING'
Check (-not $takeover.Contains('return takeover.abilities || researchLabSelected();')) 'RESEARCH_CUSTOM_ABILITY_TAKEOVER_PRESENT'
Check ($tooltip.Contains('isSelectedResearchLab')) 'RESEARCH_TOOLTIP_COORDINATION_MISSING'
Check (-not ($tooltip -match 'if\s*\(isSelectedResearchLab\(\)\)\s*\{\s*disableExternalProxies\(\)')) 'RESEARCH_TOOLTIP_PROXY_STILL_DISABLED'
Check ($tooltip -match 'function authorityAbilitySignature\(\)[\s\S]+?isSelectedResearchLab\(\)[\s\S]+?visibleAbilitySignature\(\)') 'RESEARCH_TOOLTIP_AUTHORITY_SIGNATURE_MISSING'
Check ($runtimeService.Contains('"unit:" .. tostring(unit_key)') -and $runtimeService.Contains('ability_count = math.max(0, tonumber(unit:GetAbilityCount()) or 0)')) 'RESEARCH_RUNTIME_ABILITY_COUNT_PUBLICATION_MISSING'
Check ($tooltip.Contains('function unitAbilityCount(unit)') -and $tooltip.Contains('engineSlot < unitAbilityCount(unit)')) 'RESEARCH_TOOLTIP_SAFE_ENGINE_SLOT_ENUMERATION_MISSING'
Check ([regex]::Matches($combat, 'for \(var (?:i|slot) = 0; (?:i|slot) < unitAbilityCount\(unit\); (?:i|slot)\+\+\)').Count -eq 4) 'RESEARCH_COMBAT_SAFE_ENGINE_SLOT_ENUMERATION_MISSING'
Check ($tooltip.Contains('for (var nodeIndex = 0; nodeIndex < maxAbilityEngineSlots; nodeIndex++)') -and $tooltip.Contains('"Ability" + String(nodeIndex)')) 'RESEARCH_TOOLTIP_PANEL_ENUMERATION_MISSING'
Check ($tooltip.Contains('function extendResearchAbilityPanels(entries, requiredCount)') -and $tooltip.Contains('officialPanels = extendResearchAbilityPanels(officialPanels, abilityIndexes.length);')) 'RESEARCH_TOOLTIP_VIRTUAL_SLOT_EXTENSION_MISSING'
Check ($tooltip.Contains('var stepX = Number(last.x) - Number(previous.x);') -and $tooltip.Contains('stepX = Number(last.width || previous.width || 0);')) 'RESEARCH_TOOLTIP_SLOT_EXTRAPOLATION_INVALID'
Check ($tooltip.Contains('anchor.actuallayoutwidth') -and $tooltip.Contains('anchor.actuallayoutheight') -and $tooltip.Contains('anchor.GetPositionWithinWindow()')) 'RESEARCH_TOOLTIP_REAL_BUTTON_GEOMETRY_MISSING'
Check ($tooltip.Contains('anchor: null') -and $tooltip.Contains('virtual: true') -and $tooltip.Contains('var explicitRect = entry && entry.virtual ? entry : null;')) 'RESEARCH_TOOLTIP_VIRTUAL_RECT_MISSING'
Check ($tooltip.Contains('var hitTarget = binding.entry.anchor || binding.proxy;')) 'RESEARCH_TOOLTIP_VIRTUAL_CURSOR_HIT_MISSING'
Check ($tooltip -match 'isSelectedResearchLab\(\)\s*&&\s*/\^ability_research_/\.test\(abilityName\)') 'RESEARCH_CUSTOM_TOOLTIP_SCOPE_MISSING'
Check ($tooltip.Contains('|| /^ability_research_/.test(abilityName)') -and $tooltip.Contains('input.ExecuteAbility(boundAbility)')) 'RESEARCH_PROXY_LEFT_CLICK_ROUTE_MISSING'
Check ($runtimeBuilder.Contains('display_name = mapping.display_name')) 'RESEARCH_CSV_DISPLAY_NAME_RUNTIME_MISSING'
Check (-not (Read-Utf8 'scripts\vscripts\research\research_technology_description.lua').Contains('{ label = "科技编号"')) 'RESEARCH_TECHNOLOGY_ID_FIELD_PRESENT'
Check ($tooltip.Contains('setText("CustomAbilityTitle", runtime.display_name || localizedTitle')) 'RESEARCH_TOOLTIP_RUNTIME_TITLE_MISSING'
Check (-not $tooltip.Contains('localizedResearchTitle')) 'RESEARCH_TOOLTIP_LOCALIZED_INTERNAL_NAME_PRESENT'
Check ($tooltip.Contains('proxy.SetPanelEvent("oncontextmenu"')) 'RESEARCH_PROXY_RIGHT_CLICK_MISSING'
Check ($tooltip.Contains('shop.OpenResearch(unit)')) 'RESEARCH_PROXY_OPEN_WINDOW_MISSING'
Check ($tooltip.Contains('if (!render(abilityIndex, abilityName, sourcePanel))') -and $tooltip.Contains('hideNativeTooltip(sourcePanel);')) 'RESEARCH_NATIVE_TOOLTIP_FALLBACK_PRESENT'
Check ($combat.Contains('/^ability_research_/.test(abilityName)')) 'RESEARCH_CLIENT_MANAGED_ROUTE_MISSING'
Check ($combat.Contains('var researchSlot = Number(runtime.research_slot_order || 0) - 1;')) 'RESEARCH_NATIVE_HOTKEY_SLOT_MISSING'
Check ($combat.Contains('? ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G"]')) 'ADVANCED_RESEARCH_NATIVE_HOTKEY_LABELS_MISSING'
Check ($ui.Contains('ShopTechnologyCode')) 'ARS_VISIBLE_CODE_MISSING'
Check ($css.Contains('.ShopShelfSlot.Technology.AutoResearchActive')) 'AUTO_RESEARCH_ACTIVE_STYLE_MISSING'
Check ($css.Contains('.ShopShelfSlot.Technology.AutoResearchActive.Unavailable')) 'AUTO_RESEARCH_LOCKED_ACTIVE_STYLE_MISSING'

Write-Output 'ADVANCED_RESEARCH_LAB_CONTRACT_PASS'