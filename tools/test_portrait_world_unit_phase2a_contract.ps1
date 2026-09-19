param(
    [string]$GeneratedContentRoot = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$spike = Join-Path $repo 'spikes\portrait_world_unit_phase2a'

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Text([string]$path) {
    Check (Test-Path -LiteralPath $path -PathType Leaf) "MISSING_FILE: $path"
    return [IO.File]::ReadAllText($path)
}

function EntityTail([string]$text, [string]$className) {
    $anchor = '"classname" "string" "' + $className + '"'
    $anchorIndex = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($anchorIndex -ge 0) "ENTITY_CLASS_MISSING: $className"
    $endIndex = $text.IndexOf('"CMapEntity"', $anchorIndex, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { $endIndex = $text.Length }
    return $text.Substring($anchorIndex, $endIndex - $anchorIndex)
}

function EntityTailByTargetname([string]$text, [string]$targetname) {
    $anchor = '"targetname" "string" "' + $targetname + '"'
    $anchorIndex = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($anchorIndex -ge 0) "ENTITY_TARGETNAME_MISSING: $targetname"
    $startIndex = $text.LastIndexOf('"CMapEntity"', $anchorIndex, [StringComparison]::Ordinal)
    Check ($startIndex -ge 0) "ENTITY_START_MISSING: $targetname"
    $endIndex = $text.IndexOf('"CMapEntity"', $anchorIndex, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { $endIndex = $text.Length }
    return $text.Substring($startIndex, $endIndex - $startIndex)
}

$csv = Join-Path $spike 'data\axe_stages.csv'
$controlCsv = Join-Path $spike 'data\renderer_sanity_control.csv'
$layout = Join-Path $spike 'content\panorama\layout\custom_game\phase2a_portrait_spike.xml.in'
$style = Join-Path $spike 'content\panorama\styles\custom_game\phase2a_portrait_spike.css'
$script = Join-Path $spike 'content\panorama\scripts\custom_game\phase2a_portrait_spike.js'
$builder = Join-Path $repo 'tools\build_portrait_world_unit_phase2a.ps1'
$rows = @(Import-Csv -LiteralPath $csv)
$controlRows = @(Import-Csv -LiteralPath $controlCsv)
$layoutText = Text $layout
$styleText = Text $style
[xml]$layoutXml = $layoutText

Check ($rows.Count -eq 4) 'STAGE_COUNT_MUST_BE_FOUR'
Check ($controlRows.Count -eq 1) 'RENDERER_SANITY_CONTROL_COUNT_MUST_BE_ONE'
$control = $controlRows[0]
Check ($control.control_id -eq 'axe_prop_control') 'RENDERER_SANITY_CONTROL_ID_INVALID'
Check ($control.scene_map -eq 'phase2a_portrait/axe_prop_control') 'RENDERER_SANITY_CONTROL_MAP_INVALID'
Check ($control.map_usage_type -eq 'background') 'RENDERER_SANITY_CONTROL_MAP_USAGE_TYPE_INVALID'
Check ($control.particle_only -eq 'false') 'RENDERER_SANITY_CONTROL_PARTICLE_ONLY_INVALID'
Check ($control.camera_name -eq 'hero_camera') 'RENDERER_SANITY_CONTROL_CAMERA_INVALID'
Check ($control.light_targetname -eq 'prop_control_key_light') 'RENDERER_SANITY_CONTROL_LIGHT_INVALID'
Check ($control.hero_model -eq 'models/heroes/axe/axe.vmdl') 'RENDERER_SANITY_CONTROL_AXE_MODEL_INVALID'
Check ($control.test_model -eq 'models/props_gameplay/red_box.vmdl') 'RENDERER_SANITY_CONTROL_TEST_MODEL_INVALID'
Check ($control.hero_force_hidden -eq '0') 'RENDERER_SANITY_CONTROL_AXE_FORCE_HIDDEN_INVALID'
Check ($control.hero_editor_only -eq '0') 'RENDERER_SANITY_CONTROL_AXE_EDITOR_ONLY_INVALID'
Check ($control.test_force_hidden -eq '0') 'RENDERER_SANITY_CONTROL_TEST_FORCE_HIDDEN_INVALID'
Check ($control.test_editor_only -eq '0') 'RENDERER_SANITY_CONTROL_TEST_EDITOR_ONLY_INVALID'
Check (-not ((Text $controlCsv).Contains('portrait_world_unit'))) 'RENDERER_SANITY_CONTROL_PORTRAIT_WORLD_UNIT_FORBIDDEN'
Check (-not ((Text $controlCsv).Contains('22217'))) 'RENDERER_SANITY_CONTROL_ITEM_DEF_FORBIDDEN'
Check (($rows.stage_id -join ',') -eq 'base,head,head_weapon,all_five') 'STAGE_ORDER_INVALID'
Check (($rows | Where-Object map_unit_name -ne 'npc_dota_hero_axe').Count -eq 0) 'NON_AXE_STAGE_FOUND'
Check ($rows[0].portrait_contract -eq 'base_minimal') 'BASE_PORTRAIT_CONTRACT_INVALID'
Check (($rows | Where-Object { $_.portrait_contract -notin @('base_minimal', 'item_defs') }).Count -eq 0) 'PORTRAIT_CONTRACT_INVALID'
Check (($rows | Where-Object map_usage_type -ne 'background').Count -eq 0) 'BACKGROUND_MAP_USAGE_TYPE_REQUIRED'
Check (($rows | Where-Object particle_only -ne 'false').Count -eq 0) 'PARTICLE_ONLY_MUST_BE_FALSE'
Check (($rows | Where-Object camera_name -ne 'hero_camera').Count -eq 0) 'BACKGROUND_CAMERA_NAME_INVALID'
Check (($rows | Where-Object light_targetname -ne 'light_hero').Count -eq 0) 'BACKGROUND_LIGHT_TARGETNAME_INVALID'
Check ($rows[0].portrait_targetname -eq 'phase2a_axe_portrait_unit') 'BASE_PORTRAIT_TARGETNAME_INVALID'
Check (($rows | Select-Object -Skip 1 | Where-Object { -not [string]::IsNullOrEmpty($_.portrait_targetname) }).Count -eq 0) 'NON_BASE_PORTRAIT_TARGETNAME_FORBIDDEN'
Check ($rows[0].m_iTeamNum -eq '2') 'BASE_TEAM_MUST_BE_TWO'
Check ($rows[0].ModelScale -eq '1') 'BASE_MODEL_SCALE_MUST_BE_ONE'
Check ($rows[0].StartDisabled -eq '0') 'BASE_PORTRAIT_MUST_BE_ENABLED'
Check ($rows[0].spawn_wearable_item_defs -eq '0') 'BASE_SPAWN_WEARABLE_ITEM_DEFS_MUST_BE_ZERO'
Check ($rows[0].skip_background_entities -eq '1') 'BASE_SKIP_BACKGROUND_ENTITIES_MUST_BE_ONE'
Check ($rows[0].suppress_intro_effects -eq '1') 'BASE_SUPPRESS_INTRO_EFFECTS_MUST_BE_ONE'
Check ($rows[0].skip_pet_spawn -eq '1') 'BASE_SKIP_PET_SPAWN_MUST_BE_ONE'
foreach ($property in @('enable_auto_styles', 'spawn_background_models', 'rare_loadout_anim_chance', 'suppress_anim_event_sounds', 'flying_courier', 'activity', 'activity_modifier')) {
    Check ([string]::IsNullOrEmpty($rows[0].$property)) "BASE_NON_MINIMAL_CSV_VALUE_FORBIDDEN: $property"
}
Check (($rows | Where-Object { $_.portrait_contract -eq 'item_defs' -and $_.spawn_wearable_item_defs -ne '1' }).Count -eq 0) 'ITEM_DEF_STAGES_SPAWN_WEARABLE_REQUIRED'
Check (($rows | Where-Object { $_.portrait_contract -eq 'item_defs' -and $_.enable_auto_styles -ne '0' }).Count -eq 0) 'ENABLE_AUTO_STYLES_MUST_BE_ZERO'
Check (($rows | Where-Object { $_.portrait_contract -eq 'item_defs' -and $_.activity -ne 'ACT_DOTA_LOADOUT' }).Count -eq 0) 'LOADOUT_ACTIVITY_REQUIRED'
Check ((@($rows.camera_origin | Sort-Object -Unique).Count -eq 1)) 'CAMERA_ORIGIN_MUST_BE_SHARED'
Check ((@($rows.camera_angles | Sort-Object -Unique).Count -eq 1)) 'CAMERA_ANGLES_MUST_BE_SHARED'
Check ($rows[0].camera_angles -eq '11.553546 171.313448 0.000000') 'CAMERA_MUST_AIM_AT_PORTRAIT_WORLD_UNIT'

$baseDefs = 0..7 | ForEach-Object { $rows[0].("item_def$_") }
Check (($baseDefs -join ',') -eq '0,0,0,0,0,0,0,0') 'BASE_STAGE_MUST_HAVE_NO_ITEM_DEFS'
$headDefs = 0..7 | ForEach-Object { $rows[1].("item_def$_") }
Check (($headDefs -join ',') -eq '22217,0,0,0,0,0,0,0') 'HEAD_STAGE_INVALID'
$headWeaponDefs = 0..7 | ForEach-Object { $rows[2].("item_def$_") }
Check (($headWeaponDefs -join ',') -eq '22217,22218,0,0,0,0,0,0') 'HEAD_WEAPON_STAGE_INVALID'
$allDefs = 0..7 | ForEach-Object { $rows[3].("item_def$_") }
Check (($allDefs -join ',') -eq '22217,22218,22215,22216,22219,0,0,0') 'ALL_FIVE_STAGE_INVALID'

foreach ($row in $rows) {
    $styles = 0..7 | ForEach-Object { $row.("style_index$_") }
    Check (($styles | Where-Object { $_ -ne '0' }).Count -eq 0) "STYLE_MUST_BE_EXPLICIT_ZERO: $($row.stage_id)"
}

$allSource = (Text $csv) + $layoutText + (Text $script) + (Text $builder)
Check (-not $allSource.Contains('skin_override')) 'SKIN_OVERRIDE_IS_FORBIDDEN'
Check (-not (Text $script).Contains('SetUnit(')) 'SET_UNIT_IS_FORBIDDEN'
Check (-not (Text $script).Contains('SetScene(')) 'SET_SCENE_IS_FORBIDDEN'
Check ((Text $script).Contains('function metricsComplete()')) 'PASS_METRICS_GATE_MISSING'
Check ((Text $script).Contains('function passCriteria()')) 'PASS_CRITERIA_MISSING'
Check ((Text $script).Contains('Array.isArray(stages)')) 'PANORAMA_STAGE_ARRAY_CONTRACT_MISSING'
Check ((Text $script).Contains('function hasStageSchema(stage)')) 'PANORAMA_STAGE_SCHEMA_GUARD_MISSING'
Check (-not (Text $script).Contains('Phase2APortraitData || []')) 'PANORAMA_STAGE_SCHEMA_FALLBACK_FORBIDDEN'
Check ((Text $script).Contains('loaded === false')) 'SNIPPET_LOAD_FAILURE_CHECK_MISSING'
Check (([regex]::Matches((Text $script), 'setButtonEnabled\("Phase2AReload", false\);')).Count -eq 2) 'TERMINAL_RELOAD_LOCK_MISSING'
Check (([regex]::Matches($layoutText, 'particleonly="__[A-Z_]+PARTICLE_ONLY__"')).Count -eq 5) 'PARTICLE_ONLY_TEMPLATE_BINDING_MISSING'
Check (([regex]::Matches($layoutText, 'light="__[A-Z_]+LIGHT_TARGETNAME__"')).Count -eq 5) 'LIGHT_TEMPLATE_BINDING_MISSING'
Check (-not $layoutText.Contains('camera="herocamera"')) 'LEGACY_STATIC_CAMERA_BINDING_FOUND'
Check ($layoutText.Contains('<DOTAScenePanel')) 'DOTA_SCENE_PANEL_MISSING'
Check (-not $layoutText.Contains('<Panel id="Phase2ARoot"')) 'ROOT_PANEL_ID_IS_FORBIDDEN'

$directPanels = @($layoutXml.SelectNodes('//DOTAScenePanel[@id="DirectUnitSanity"]'))
Check ($directPanels.Count -eq 1) 'DIRECT_UNIT_SANITY_MUST_EXIST_ONCE'
$direct = $directPanels[0]
Check ($direct.Attributes.Count -eq 2) 'DIRECT_UNIT_SANITY_MUST_HAVE_ONLY_ID_AND_UNIT'
Check ($direct.GetAttribute('unit') -eq 'npc_dota_hero_axe') 'DIRECT_UNIT_SANITY_MUST_USE_BASE_AXE'
Check (-not $direct.HasAttribute('map')) 'DIRECT_UNIT_SANITY_MAP_IS_FORBIDDEN'
Check (-not $direct.HasAttribute('camera')) 'DIRECT_UNIT_SANITY_CAMERA_IS_FORBIDDEN'
Check (-not $direct.HasAttribute('portrait_world_unit')) 'DIRECT_UNIT_SANITY_PORTRAIT_WORLD_UNIT_IS_FORBIDDEN'
Check (-not $direct.OuterXml.Contains('item')) 'DIRECT_UNIT_SANITY_ITEM_DEF_IS_FORBIDDEN'
Check (-not $direct.OuterXml.Contains('phase2a_portrait')) 'DIRECT_UNIT_SANITY_SCENE_REFERENCE_IS_FORBIDDEN'

$backgroundPanels = @($layoutXml.SelectNodes('//DOTAScenePanel[@id="BackgroundSceneSanity"]'))
Check ($backgroundPanels.Count -eq 4) 'BACKGROUND_SCENE_SANITY_STAGE_COUNT_INVALID'
$baseBackground = $layoutXml.SelectSingleNode('//snippet[@name="Phase2AStageBase"]/DOTAScenePanel[@id="BackgroundSceneSanity"]')
Check ($null -ne $baseBackground) 'BASE_BACKGROUND_SCENE_SANITY_MISSING'
Check ($baseBackground.GetAttribute('map') -eq '__BASE_SCENE_MAP__') 'BASE_BACKGROUND_SCENE_MAP_INVALID'
Check ($baseBackground.GetAttribute('camera') -eq '__BASE_CAMERA_NAME__') 'BASE_BACKGROUND_SCENE_CAMERA_INVALID'
Check ($baseBackground.GetAttribute('light') -eq '__BASE_LIGHT_TARGETNAME__') 'BASE_BACKGROUND_SCENE_LIGHT_INVALID'
Check ($baseBackground.GetAttribute('particleonly') -eq '__BASE_PARTICLE_ONLY__') 'BASE_BACKGROUND_SCENE_PARTICLE_ONLY_INVALID'
Check (-not $baseBackground.HasAttribute('unit')) 'BACKGROUND_SCENE_DIRECT_UNIT_IS_FORBIDDEN'
Check ($layoutXml.SelectNodes('//DOTAScenePanel[@id="BackgroundPropControl"]').Count -eq 1) 'BACKGROUND_PROP_CONTROL_MUST_EXIST_ONCE'
$controlPanel = $layoutXml.SelectSingleNode('//DOTAScenePanel[@id="BackgroundPropControl"]')
Check ($controlPanel.GetAttribute('map') -eq '__PROP_CONTROL_SCENE_MAP__') 'BACKGROUND_PROP_CONTROL_SCENE_MAP_INVALID'
Check ($controlPanel.GetAttribute('camera') -eq '__PROP_CONTROL_CAMERA_NAME__') 'BACKGROUND_PROP_CONTROL_CAMERA_INVALID'
Check ($controlPanel.GetAttribute('light') -eq '__PROP_CONTROL_LIGHT_TARGETNAME__') 'BACKGROUND_PROP_CONTROL_LIGHT_INVALID'
Check ($controlPanel.GetAttribute('particleonly') -eq '__PROP_CONTROL_PARTICLE_ONLY__') 'BACKGROUND_PROP_CONTROL_PARTICLE_ONLY_INVALID'
Check (-not $controlPanel.HasAttribute('unit')) 'BACKGROUND_PROP_CONTROL_DIRECT_UNIT_IS_FORBIDDEN'
Check (-not $controlPanel.OuterXml.Contains('22217')) 'BACKGROUND_PROP_CONTROL_ITEM_DEF_FORBIDDEN'
Check (-not $controlPanel.OuterXml.Contains('portrait_world_unit')) 'BACKGROUND_PROP_CONTROL_PORTRAIT_WORLD_UNIT_FORBIDDEN'
Check ($styleText.Contains("#DirectUnitSanity {`n    width: 340px;`n    height: 340px;")) 'DIRECT_UNIT_SANITY_MINIMUM_SIZE_MISSING'
Check ($styleText.Contains(".BackgroundSceneSanity {`n    width: 340px;`n    height: 340px;")) 'BACKGROUND_SCENE_SANITY_MINIMUM_SIZE_MISSING'
Check ($styleText.Contains("#BackgroundPropControl {`n    width: 340px;`n    height: 340px;")) 'BACKGROUND_PROP_CONTROL_MINIMUM_SIZE_MISSING'
Check ($styleText.Contains('flow-children: right;')) 'RENDERER_SANITY_SIDE_BY_SIDE_LAYOUT_MISSING'
Check ((Text $builder).Contains('Import-Csv -LiteralPath $StageCsv')) 'BUILDER_MUST_CONSUME_STAGE_CSV'
Check ((Text $builder).Contains('Import-Csv -LiteralPath $RendererSanityCsv')) 'BUILDER_MUST_CONSUME_RENDERER_SANITY_CSV'
Check ((Text $builder).Contains('RENDERER_SANITY_MUST_ONLY_ACTIVATE_BASE')) 'RENDERER_SANITY_STAGE_LOCK_MISSING'
Check ((Text $builder).Contains('[switch]$SceneAndPanoramaOnly')) 'SELECTIVE_BUILD_MODE_MISSING'
Check ((Text $builder).Contains('SELECTIVE_BUILD_CONTENT_TARGET_MISSING')) 'SELECTIVE_BUILD_CONTENT_GUARD_MISSING'
Check ((Text $builder).Contains('SELECTIVE_BUILD_GAME_TARGET_MISSING')) 'SELECTIVE_BUILD_GAME_GUARD_MISSING'
Check ((Text $builder).Contains('function Check-OutputIsFresh')) 'OUTPUT_FRESHNESS_CHECK_MISSING'
Check ((Text $builder).Contains('${label}_SOURCE_MISSING')) 'OUTPUT_SOURCE_CHECK_MISSING'
Check ((Text $builder).Contains('${label}_OUTPUT_EMPTY')) 'OUTPUT_NONEMPTY_CHECK_MISSING'
Check ((Text $builder).Contains('${label}_OUTPUT_STALE')) 'OUTPUT_TIMESTAMP_CHECK_MISSING'
Check ((Text $builder).Contains('($relative + ''.vmap'')')) 'SCENE_FRESHNESS_SOURCE_EXTENSION_INVALID'
Check ((Text $builder).Contains('($relative + ''.vpk'')')) 'SCENE_FRESHNESS_OUTPUT_EXTENSION_INVALID'
Check ((Text $builder).Contains('($controlRelative + ''.vmap'')')) 'CONTROL_FRESHNESS_SOURCE_EXTENSION_INVALID'
Check ((Text $builder).Contains('($controlRelative + ''.vpk'')')) 'CONTROL_FRESHNESS_OUTPUT_EXTENSION_INVALID'
Check ((Text $builder).Contains('portrait_world_unit')) 'PORTRAIT_WORLD_UNIT_GENERATION_MISSING'
Check ((Text $builder).Contains("Get-RowValue `$row 'portrait_targetname'")) 'PORTRAIT_TARGETNAME_GENERATION_MISSING'
Check ((Text $builder).Contains('ConvertTo-Json -InputObject $panoramaStages')) 'PANORAMA_STAGE_ARRAY_SERIALIZATION_MISSING'
Check ((Text $builder).Contains('Set-OrAddStringPropertyAfterAnchor')) 'PORTRAIT_PROPERTY_ADD_SUPPORT_MISSING'
Check ((Text $builder).Contains('Remove-StringPropertyAfterAnchor')) 'PORTRAIT_PROPERTY_REMOVE_SUPPORT_MISSING'
Check ((Text $builder).Contains("Get-RowValue `$row 'm_iTeamNum'")) 'PORTRAIT_TEAM_GENERATION_MISSING'
Check ((Text $builder).Contains("Get-RowValue `$row 'skip_background_entities'")) 'SKIP_BACKGROUND_ENTITIES_GENERATION_MISSING'
Check ((Text $builder).Contains('New-PropControlMap')) 'PROP_CONTROL_MAP_GENERATION_MISSING'
Check ((Text $builder).Contains('CONTROL_PORTRAIT_WORLD_UNIT_FORBIDDEN')) 'PROP_CONTROL_PORTRAIT_GUARD_MISSING'
Check ((Text $builder).Contains('CONTROL_ITEM_DEF_22217_FORBIDDEN')) 'PROP_CONTROL_ITEM_DEF_GUARD_MISSING'
Check ((Text $builder).Contains("Get-RowValue `$row 'map_usage_type'")) 'MAP_USAGE_TYPE_GENERATION_MISSING'
Check ((Text $builder).Contains("Get-RowValue `$row 'camera_name'")) 'CAMERA_NAME_GENERATION_MISSING'
Check ((Text $builder).Contains("Get-RowValue `$row 'light_targetname'")) 'LIGHT_TARGETNAME_GENERATION_MISSING'
Check ((Text $builder).Contains("(`$prefix + '_force_hidden')")) 'PROP_CONTROL_FORCE_HIDDEN_GENERATION_MISSING'
Check ((Text $builder).Contains("(`$prefix + '_editor_only')")) 'PROP_CONTROL_EDITOR_ONLY_GENERATION_MISSING'
Check ((Text $builder).Contains("Get-RowValue `$row 'particle_only'")) 'PARTICLE_ONLY_GENERATION_MISSING'
Check ((Text $builder).Contains("'parentname' ''")) 'CAMERA_PARENTNAME_ENFORCEMENT_MISSING'
Check ((Text $builder).Contains("'parentAttachmentName' ''")) 'CAMERA_PARENT_ATTACHMENT_ENFORCEMENT_MISSING'
Check ((Text $builder).Contains('loadout_camera_model')) 'LOADOUT_CAMERA_MODEL_GUARD_MISSING'
Check ((Text $builder).Contains('CAMERA_PITCH_NOT_AIMED_AT_PORTRAIT')) 'CAMERA_PITCH_AIM_GUARD_MISSING'
Check ((Text $builder).Contains('CAMERA_YAW_NOT_AIMED_AT_PORTRAIT')) 'CAMERA_YAW_AIM_GUARD_MISSING'

if ($GeneratedContentRoot -ne '') {
    Check (Test-Path -LiteralPath $GeneratedContentRoot -PathType Container) 'GENERATED_CONTENT_ROOT_MISSING'
    $generatedLayoutPath = Join-Path $GeneratedContentRoot 'panorama\layout\custom_game\phase2a_portrait_spike.xml'
    [xml]$generatedLayout = Text $generatedLayoutPath
    foreach ($row in $rows) {
        $panel = $generatedLayout.SelectSingleNode(('//snippet[@name="{0}"]/DOTAScenePanel[@id="BackgroundSceneSanity"]' -f $row.snippet_name))
        Check ($null -ne $panel) "GENERATED_BACKGROUND_PANEL_MISSING: $($row.stage_id)"
        Check ($panel.GetAttribute('map') -eq $row.scene_map) "GENERATED_BACKGROUND_MAP_INVALID: $($row.stage_id)"
        Check ($panel.GetAttribute('camera') -eq $row.camera_name) "GENERATED_BACKGROUND_CAMERA_INVALID: $($row.stage_id)"
        Check ($panel.GetAttribute('light') -eq $row.light_targetname) "GENERATED_BACKGROUND_LIGHT_INVALID: $($row.stage_id)"
        Check ($panel.GetAttribute('particleonly') -eq $row.particle_only) "GENERATED_BACKGROUND_PARTICLE_ONLY_INVALID: $($row.stage_id)"
    }
    $generatedControlPanel = $generatedLayout.SelectSingleNode('//DOTAScenePanel[@id="BackgroundPropControl"]')
    Check ($null -ne $generatedControlPanel) 'GENERATED_CONTROL_PANEL_MISSING'
    Check ($generatedControlPanel.GetAttribute('map') -eq $control.scene_map) 'GENERATED_CONTROL_MAP_INVALID'
    Check ($generatedControlPanel.GetAttribute('camera') -eq $control.camera_name) 'GENERATED_CONTROL_CAMERA_INVALID'
    Check ($generatedControlPanel.GetAttribute('light') -eq $control.light_targetname) 'GENERATED_CONTROL_LIGHT_INVALID'
    Check ($generatedControlPanel.GetAttribute('particleonly') -eq $control.particle_only) 'GENERATED_CONTROL_PARTICLE_ONLY_INVALID'
    Check (-not (Text $generatedLayoutPath).Contains('__')) 'GENERATED_LAYOUT_PLACEHOLDER_REMAINS'

    $generatedDataPath = Join-Path $GeneratedContentRoot 'panorama\scripts\custom_game\phase2a_portrait_data.js'
    $generatedDataText = Text $generatedDataPath
    $generatedDataMatch = [regex]::Match($generatedDataText, 'Phase2APortraitData\s*=\s*(\[.*\]);')
    Check ($generatedDataMatch.Success) 'GENERATED_PANORAMA_DATA_MUST_BE_ARRAY'
    $runtimeStages = @(ConvertFrom-Json -InputObject $generatedDataMatch.Groups[1].Value)
    Check ($runtimeStages.Count -eq 1) 'GENERATED_PANORAMA_STAGE_COUNT_MUST_BE_ONE'
    $runtimeStage = $runtimeStages[0]
    Check ($runtimeStage.id -eq $rows[0].stage_id) 'GENERATED_PANORAMA_STAGE_ID_INVALID'
    foreach ($property in @('label', 'sceneMap', 'snippet', 'expectedItems', 'directUnit')) {
        Check ($null -ne $runtimeStage.PSObject.Properties[$property]) "GENERATED_PANORAMA_STAGE_FIELD_MISSING: $property"
    }
    Check ($runtimeStage.directUnit -eq $rows[0].map_unit_name) 'GENERATED_PANORAMA_DIRECT_UNIT_INVALID'
    Check ($runtimeStage.backgroundScene.map -eq $rows[0].scene_map) 'GENERATED_PANORAMA_BACKGROUND_MAP_INVALID'
    Check ($runtimeStage.backgroundScene.camera -eq $rows[0].camera_name) 'GENERATED_PANORAMA_BACKGROUND_CAMERA_INVALID'
    Check ($runtimeStage.backgroundScene.light -eq $rows[0].light_targetname) 'GENERATED_PANORAMA_BACKGROUND_LIGHT_INVALID'
    Check ($runtimeStage.backgroundScene.particleOnly -eq $rows[0].particle_only) 'GENERATED_PANORAMA_BACKGROUND_PARTICLE_ONLY_INVALID'
    Check ($runtimeStage.backgroundProp.map -eq $control.scene_map) 'GENERATED_PANORAMA_CONTROL_MAP_INVALID'
    Check ($runtimeStage.backgroundProp.camera -eq $control.camera_name) 'GENERATED_PANORAMA_CONTROL_CAMERA_INVALID'
    Check ($runtimeStage.backgroundProp.light -eq $control.light_targetname) 'GENERATED_PANORAMA_CONTROL_LIGHT_INVALID'
    Check ($runtimeStage.backgroundProp.particleOnly -eq $control.particle_only) 'GENERATED_PANORAMA_CONTROL_PARTICLE_ONLY_INVALID'

    $baseMap = Text (Join-Path $GeneratedContentRoot 'maps\phase2a_portrait\axe_base.vmap')
    Check ($baseMap.Contains('"mapUsageType" "string" "background"')) 'GENERATED_BASE_MAP_USAGE_TYPE_INVALID'
    $baseLight = EntityTail $baseMap 'env_global_light'
    Check ($baseLight.Contains('"targetname" "string" "light_hero"')) 'GENERATED_BASE_LIGHT_INVALID'
    $basePortrait = EntityTail $baseMap 'portrait_world_unit'
    Check ($basePortrait.Contains('"targetname" "string" "phase2a_axe_portrait_unit"')) 'GENERATED_BASE_PORTRAIT_TARGETNAME_INVALID'
    Check ($basePortrait.Contains('"MapUnitName" "string" "npc_dota_hero_axe"')) 'GENERATED_BASE_MAP_UNIT_NAME_INVALID'
    Check ($basePortrait.Contains('"m_iTeamNum" "string" "2"')) 'GENERATED_BASE_TEAM_INVALID'
    Check ($basePortrait.Contains('"ModelScale" "string" "1"')) 'GENERATED_BASE_MODEL_SCALE_INVALID'
    Check ($basePortrait.Contains('"force_hidden" "bool" "0"')) 'GENERATED_BASE_FORCE_HIDDEN_INVALID'
    Check ($basePortrait.Contains('"StartDisabled" "string" "0"')) 'GENERATED_BASE_START_DISABLED_INVALID'
    Check ($basePortrait.Contains('"spawn_wearable_item_defs" "string" "0"')) 'GENERATED_BASE_SPAWN_WEARABLE_INVALID'
    Check ($basePortrait.Contains('"skip_background_entities" "string" "1"')) 'GENERATED_BASE_SKIP_BACKGROUND_ENTITIES_INVALID'
    Check ($basePortrait.Contains('"suppress_intro_effects" "string" "1"')) 'GENERATED_BASE_SUPPRESS_INTRO_INVALID'
    Check ($basePortrait.Contains('"skip_pet_spawn" "string" "1"')) 'GENERATED_BASE_SKIP_PET_INVALID'
    Check ($basePortrait.Contains('"parentname" "string" ""')) 'GENERATED_BASE_PARENTNAME_NOT_EMPTY'
    Check ($basePortrait.Contains('"parentAttachmentName" "string" ""')) 'GENERATED_BASE_PARENT_ATTACHMENT_NOT_EMPTY'
    Check (-not $basePortrait.Contains('"item_def')) 'GENERATED_BASE_ITEM_DEF_FIELDS_FORBIDDEN'
    Check (-not $basePortrait.Contains('"style_index')) 'GENERATED_BASE_STYLE_FIELDS_FORBIDDEN'
    Check (-not $basePortrait.Contains('"activity" "string"')) 'GENERATED_BASE_ACTIVITY_FORBIDDEN'
    Check (-not $basePortrait.Contains('"activity_modifier" "string"')) 'GENERATED_BASE_ACTIVITY_MODIFIER_FORBIDDEN'
    foreach ($property in @('EnableAutoStyles', 'spawn_background_models', 'rare_loadout_anim_chance', 'suppress_anim_event_sounds', 'flying_courier')) {
        Check (-not $basePortrait.Contains(('"{0}" "string"' -f $property))) "GENERATED_BASE_NON_MINIMAL_FIELD_FORBIDDEN: $property"
    }
    foreach ($forbiddenKey in @('unit_name', 'NPCScriptName', 'CustomNPCName', 'model', 'hero', 'arcana', 'persona', 'cosmetic')) {
        Check (-not $basePortrait.Contains(('"{0}"' -f $forbiddenKey))) "GENERATED_BASE_FORBIDDEN_FIELD_PRESENT: $forbiddenKey"
    }
    $baseCamera = EntityTail $baseMap 'point_camera'
    Check ($baseCamera.Contains('"targetname" "string" "hero_camera"')) 'GENERATED_BASE_CAMERA_INVALID'
    Check ($baseCamera.Contains('"parentname" "string" ""')) 'GENERATED_BASE_CAMERA_PARENTNAME_NOT_EMPTY'
    Check ($baseCamera.Contains('"parentAttachmentName" "string" ""')) 'GENERATED_BASE_CAMERA_PARENT_ATTACHMENT_NOT_EMPTY'

    $controlMap = Text (Join-Path $GeneratedContentRoot 'maps\phase2a_portrait\axe_prop_control.vmap')
    Check ($controlMap.Contains('"mapUsageType" "string" "background"')) 'GENERATED_CONTROL_MAP_USAGE_TYPE_INVALID'
    $classNames = @([regex]::Matches($controlMap, '"classname" "string" "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    Check (($classNames | Where-Object { $_ -eq 'prop_dynamic' }).Count -eq 2) 'GENERATED_CONTROL_PROP_DYNAMIC_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -eq 'env_global_light' }).Count -eq 1) 'GENERATED_CONTROL_LIGHT_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -eq 'point_camera' }).Count -eq 1) 'GENERATED_CONTROL_CAMERA_COUNT_INVALID'
    Check ($controlMap.Contains('"model" "string" "models/heroes/axe/axe.vmdl"')) 'GENERATED_CONTROL_AXE_MODEL_MISSING'
    Check ($controlMap.Contains('"model" "string" "models/props_gameplay/red_box.vmdl"')) 'GENERATED_CONTROL_RED_BOX_MODEL_MISSING'
    $controlAxe = EntityTailByTargetname $controlMap 'axe_prop_control_hero'
    Check ($controlAxe.Contains('"classname" "string" "prop_dynamic"')) 'GENERATED_CONTROL_AXE_CLASS_INVALID'
    Check ($controlAxe.Contains('"model" "string" "models/heroes/axe/axe.vmdl"')) 'GENERATED_CONTROL_AXE_MODEL_INVALID'
    Check ($controlAxe.Contains('"force_hidden" "bool" "0"')) 'GENERATED_CONTROL_AXE_FORCE_HIDDEN_INVALID'
    Check ($controlAxe.Contains('"editorOnly" "bool" "0"')) 'GENERATED_CONTROL_AXE_EDITOR_ONLY_INVALID'
    $controlRedBox = EntityTailByTargetname $controlMap 'prop_control_red_box'
    Check ($controlRedBox.Contains('"classname" "string" "prop_dynamic"')) 'GENERATED_CONTROL_RED_BOX_CLASS_INVALID'
    Check ($controlRedBox.Contains('"model" "string" "models/props_gameplay/red_box.vmdl"')) 'GENERATED_CONTROL_RED_BOX_MODEL_INVALID'
    Check ($controlRedBox.Contains('"force_hidden" "bool" "0"')) 'GENERATED_CONTROL_RED_BOX_FORCE_HIDDEN_INVALID'
    Check ($controlRedBox.Contains('"editorOnly" "bool" "0"')) 'GENERATED_CONTROL_RED_BOX_EDITOR_ONLY_INVALID'
    Check (-not $controlMap.Contains('portrait_world_unit')) 'GENERATED_CONTROL_PORTRAIT_WORLD_UNIT_FORBIDDEN'
    Check (-not $controlMap.Contains('22217')) 'GENERATED_CONTROL_ITEM_DEF_FORBIDDEN'
    $controlLight = EntityTail $controlMap 'env_global_light'
    Check ($controlLight.Contains('"targetname" "string" "prop_control_key_light"')) 'GENERATED_CONTROL_LIGHT_INVALID'
    $controlCamera = EntityTail $controlMap 'point_camera'
    Check ($controlCamera.Contains('"targetname" "string" "hero_camera"')) 'GENERATED_CONTROL_CAMERA_INVALID'
    Check ($controlCamera.Contains('"parentname" "string" ""')) 'GENERATED_CONTROL_CAMERA_PARENTNAME_NOT_EMPTY'
    Check ($controlCamera.Contains('"parentAttachmentName" "string" ""')) 'GENERATED_CONTROL_CAMERA_PARENT_ATTACHMENT_NOT_EMPTY'
}

Write-Host 'PORTRAIT_WORLD_UNIT_PHASE2A_CONTRACT_PASS' -ForegroundColor Green
