param(
    [string]$GeneratedContentRoot = '',
    [string]$GeneratedGameRoot = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$spike = Join-Path $repo 'spikes\ta_portrait_probe'
$sceneCsv = Join-Path $spike 'data\scene.csv'
$assetCatalogCsv = Join-Path $repo 'data\csv\资源系统\asset_catalog.csv'
$assetComponentsCsv = Join-Path $repo 'data\csv\资源系统\asset_components.csv'
$towerDeathCsv = Join-Path $repo 'data\csv\建筑与工人系统\防御塔\tower_class_death.csv'
$builder = Join-Path $repo 'tools\build_ta_portrait_probe.ps1'
$layoutTemplate = Join-Path $spike 'content\panorama\layout\custom_game\ta_portrait_probe.xml.in'
$manifest = Join-Path $spike 'content\panorama\layout\custom_game\custom_ui_manifest.xml'
$panoramaScript = Join-Path $spike 'content\panorama\scripts\custom_game\ta_portrait_probe.js'
$panoramaStyle = Join-Path $spike 'content\panorama\styles\custom_game\ta_portrait_probe.css'
$runtimeAddonInfo = Join-Path $spike 'runtime\addoninfo.txt'
$runtimeGameMode = Join-Path $spike 'runtime\scripts\vscripts\addon_game_mode.lua'
$readme = Join-Path $spike 'README.md'

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Text([string]$path) {
    Check (Test-Path -LiteralPath $path -PathType Leaf) "MISSING_FILE: $path"
    return [IO.File]::ReadAllText($path)
}

function Get-RowValue($row, [string]$name) {
    $property = $row.PSObject.Properties[$name]
    Check ($null -ne $property) "CSV_COLUMN_MISSING: $name"
    return [string]$property.Value
}

function Get-EntityBlockByTargetname([string]$text, [string]$targetname) {
    $anchor = '"targetname" "string" "' + $targetname + '"'
    $anchorIndex = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($anchorIndex -ge 0) "ENTITY_TARGETNAME_MISSING: $targetname"
    $startIndex = $text.LastIndexOf('"CMapEntity"', $anchorIndex, [StringComparison]::Ordinal)
    Check ($startIndex -ge 0) "ENTITY_START_MISSING: $targetname"
    $openIndex = $text.IndexOf('{', $startIndex)
    Check ($openIndex -ge 0 -and $openIndex -lt $anchorIndex) "ENTITY_OPEN_MISSING: $targetname"
    $depth = 0
    $inString = $false
    $escaped = $false
    for ($index = $openIndex; $index -lt $text.Length; $index++) {
        $character = $text[$index]
        if ($inString) {
            if ($escaped) { $escaped = $false }
            elseif ($character -eq '\') { $escaped = $true }
            elseif ($character -eq '"') { $inString = $false }
            continue
        }
        if ($character -eq '"') { $inString = $true }
        elseif ($character -eq '{') { $depth += 1 }
        elseif ($character -eq '}') {
            $depth -= 1
            if ($depth -eq 0) { return $text.Substring($startIndex, $index - $startIndex + 1) }
        }
    }
    throw "ENTITY_END_MISSING: $targetname"
}

function Get-PropertyValue([string]$block, [string]$property, [string]$type) {
    $pattern = '"' + [regex]::Escape($property) + '" "' + [regex]::Escape($type) + '" "([^"]*)"'
    $match = [regex]::Match($block, $pattern)
    Check ($match.Success) "ENTITY_PROPERTY_MISSING: $property/$type"
    return $match.Groups[1].Value
}

function Get-LinesWith([string]$text, [string]$pattern) {
    return @([regex]::Matches($text, $pattern) | ForEach-Object { $_.Groups[1].Value })
}

foreach ($required in @($sceneCsv, $assetCatalogCsv, $assetComponentsCsv, $towerDeathCsv, $builder, $layoutTemplate, $manifest, $panoramaScript, $panoramaStyle, $runtimeAddonInfo, $runtimeGameMode, $readme)) {
    Check (Test-Path -LiteralPath $required -PathType Leaf) "SOURCE_REQUIRED_FILE_MISSING: $required"
}

$sceneRows = @(Import-Csv -LiteralPath $sceneCsv)
Check ($sceneRows.Count -eq 1) 'SCENE_ROW_COUNT_INVALID'
$scene = $sceneRows[0]
Check ((Get-RowValue $scene 'probe_id') -eq 'ta_death_tower') 'SCENE_PROBE_ID_INVALID'
Check ((Get-RowValue $scene 'addon_name') -eq 'survival_ta_portrait_probe') 'SCENE_ADDON_INVALID'
Check ((Get-RowValue $scene 'asset_id') -eq 'tower_death_templar_assassin') 'SCENE_ASSET_INVALID'
Check ((Get-RowValue $scene 'scene_map') -eq 'ta_portrait/templar_assassin') 'SCENE_MAP_INVALID'
Check ((Get-RowValue $scene 'playable_map') -eq 'ta_portrait_probe_lab') 'PLAYABLE_MAP_INVALID'
Check ((Get-RowValue $scene 'map_usage_type') -eq 'background') 'MAP_USAGE_TYPE_INVALID'
Check ((Get-RowValue $scene 'particle_only') -eq 'false') 'PARTICLE_ONLY_INVALID'
Check ((Get-RowValue $scene 'camera_name') -eq 'hero_camera') 'CAMERA_NAME_INVALID'
Check ((Get-RowValue $scene 'light_targetname') -eq 'ta_portrait_key_light') 'LIGHT_NAME_INVALID'

$assetId = Get-RowValue $scene 'asset_id'
$assets = @(Import-Csv -LiteralPath $assetCatalogCsv | Where-Object asset_id -eq $assetId)
Check ($assets.Count -eq 1) 'ASSET_ROW_COUNT_INVALID'
$asset = $assets[0]
Check ((Get-RowValue $asset 'primary_model') -eq 'models/heroes/lanaya/lanaya.vmdl') 'BODY_MODEL_INVALID'
Check ((Get-RowValue $asset 'portrait_unit_name') -eq 'npc_dota_hero_templar_assassin') 'PORTRAIT_UNIT_INVALID'
Check ((Get-RowValue $asset 'default_sequence') -eq 'idle') 'BODY_SEQUENCE_INVALID'
Check ((Get-RowValue $asset 'model_scale') -eq '1') 'BODY_SCALE_INVALID'

$towerRows = @(Import-Csv -LiteralPath $towerDeathCsv | Where-Object { $_.model_asset_id -eq $assetId -and $_.enabled -eq '1' })
Check ($towerRows.Count -eq 5) 'DEATH_TOWER_ASSET_ROWS_INVALID'
foreach ($tower in $towerRows) {
    Check ((Get-RowValue $tower 'model_name') -eq (Get-RowValue $asset 'primary_model')) "TOWER_MODEL_CROSSCHECK_INVALID: $($tower.record_id)"
}

$components = @(Import-Csv -LiteralPath $assetComponentsCsv | Where-Object { $_.asset_id -eq $assetId -and $_.enabled -eq '1' } | Sort-Object { [int]$_.sort_order })
Check ($components.Count -eq 3) 'WEARABLE_COUNT_INVALID'
Check (($components.component_id -join ',') -eq 'head,shoulder,armor') 'WEARABLE_IDS_INVALID'
$expectedModels = @(
    'models/heroes/lanaya/lanaya_hair.vmdl',
    'models/heroes/lanaya/lanaya_cowl_shoulder.vmdl',
    'models/heroes/lanaya/lanaya_bracers_skirt.vmdl'
)
for ($index = 0; $index -lt $components.Count; $index++) {
    $component = $components[$index]
    Check ((Get-RowValue $component 'entity_class') -eq 'prop_dynamic') "WEARABLE_CLASS_INVALID: $($component.component_id)"
    Check ((Get-RowValue $component 'attach_mode') -eq 'bone_merge') "WEARABLE_ATTACH_MODE_INVALID: $($component.component_id)"
    Check ([string]::IsNullOrEmpty((Get-RowValue $component 'parent_component_id'))) "WEARABLE_PARENT_COMPONENT_INVALID: $($component.component_id)"
    Check ((Get-RowValue $component 'model_path') -eq $expectedModels[$index]) "WEARABLE_MODEL_INVALID: $($component.component_id)"
    Check ((Get-RowValue $component 'default_sequence') -eq 'idle') "WEARABLE_SEQUENCE_INVALID: $($component.component_id)"
    Check ((Get-RowValue $component 'model_scale') -eq '1') "WEARABLE_SCALE_INVALID: $($component.component_id)"
}

$builderText = Text $builder
foreach ($requiredBuilderReference in @(
    'asset_catalog.csv',
    'asset_components.csv',
    'tower_class_death.csv',
    'Import-Csv'
)) {
    Check ($builderText.Contains($requiredBuilderReference)) "BUILDER_CSV_OR_RUNTIME_REFERENCE_MISSING: $requiredBuilderReference"
}
Check (-not $builderText.Contains('survival_phase2a')) 'BUILDER_LEGACY_ADDON_REFERENCE_FORBIDDEN'
Check ($builderText.Contains("'updatechildren'")) 'BUILDER_UPDATE_CHILDREN_REFERENCE_MISSING'
Check ((Text $readme).Contains('SetOwner')) 'README_PRODUCTION_SET_OWNER_BOUNDARY_MISSING'
Check ((Text $readme).Contains('FollowEntity(body, true)')) 'README_PRODUCTION_FOLLOW_ENTITY_BOUNDARY_MISSING'

Check (-not (Text $manifest).Contains('survival_phase2a')) 'MANIFEST_LEGACY_ADDON_FORBIDDEN'
Check ((Text $runtimeAddonInfo).Contains('ta_portrait_probe_lab')) 'RUNTIME_PLAYABLE_MAP_MISSING'
$runtimeText = Text $runtimeGameMode
Check ($runtimeText.Contains('[TA_PORTRAIT_PROBE]')) 'RUNTIME_BOOTSTRAP_MARKER_MISSING'
Check ($runtimeText.Contains('require("ta_portrait_probe_runtime_config")')) 'RUNTIME_GENERATED_CONFIG_REQUIRE_MISSING'
Check ($runtimeText.Contains('SpawnEntityFromTableSynchronous')) 'RUNTIME_SYNCHRONOUS_SPAWN_MISSING'
$wearableFunction = [regex]::Match($runtimeText, '(?s)function TAPortraitProbe:_SpawnWearable\(.*?\nend\s+\nfunction TAPortraitProbe:InitializeRuntimeScene').Value
Check ($wearableFunction -ne '') 'RUNTIME_WEARABLE_FUNCTION_MISSING'
$setOwnerIndex = $wearableFunction.IndexOf('"SetOwner", body', [StringComparison]::Ordinal)
$followEntityIndex = $wearableFunction.IndexOf('"FollowEntity", body, true', [StringComparison]::Ordinal)
Check ($setOwnerIndex -ge 0) 'RUNTIME_SET_OWNER_CALL_MISSING'
Check ($followEntityIndex -gt $setOwnerIndex) 'RUNTIME_FOLLOW_ENTITY_ORDER_INVALID'
Check (-not $wearableFunction.Contains('DefaultAnim')) 'RUNTIME_WEARABLE_DEFAULT_ANIM_FORBIDDEN'
Check (-not $wearableFunction.Contains('ResetSequence')) 'RUNTIME_WEARABLE_RESET_SEQUENCE_FORBIDDEN'
Check (-not $wearableFunction.Contains('SetPlaybackRate')) 'RUNTIME_WEARABLE_PLAYBACK_COMMAND_FORBIDDEN'
Check ([regex]::Matches($runtimeText, 'DefaultAnim\s*=').Count -eq 1) 'RUNTIME_DEFAULT_ANIM_COUNT_INVALID'
Check ([regex]::Matches($runtimeText, '"ResetSequence"').Count -eq 1) 'RUNTIME_RESET_SEQUENCE_COUNT_INVALID'
Check ($runtimeText.Contains('CustomNetTables:SetTableValue')) 'RUNTIME_STATE_PUBLICATION_MISSING'
Check ($runtimeText.Contains('body_entindex')) 'RUNTIME_BODY_ENTINDEX_PUBLICATION_MISSING'
Check ($runtimeText.Contains('visual_verdict = "pending"')) 'RUNTIME_AUTOMATIC_VISUAL_PASS_FORBIDDEN'
Check ($runtimeText.Contains('ClearRuntimeScene')) 'RUNTIME_CLEANUP_MISSING'
foreach ($modelPath in @((Get-RowValue $asset 'primary_model')) + $expectedModels) {
    Check (-not $runtimeText.Contains($modelPath)) "RUNTIME_HARDCODED_MODEL_FORBIDDEN: $modelPath"
}

$panoramaText = Text $panoramaScript
Check ($panoramaText.Contains('TAPortraitProbeData')) 'PANORAMA_DATA_CONSUMER_MISSING'
Check ($panoramaText.Contains('CustomNetTables.SubscribeNetTableListener')) 'PANORAMA_RUNTIME_STATE_LISTENER_MISSING'
Check ($panoramaText.Contains('GameUI.SetCameraTarget(target)')) 'PANORAMA_RUNTIME_CAMERA_TARGET_MISSING'
Check ($panoramaText.Contains('manual_multi_frame_runtime_observation')) 'PANORAMA_MANUAL_EVIDENCE_MARKER_MISSING'
Check ($panoramaText.Contains('GameEvents.SendCustomGameEventToServer')) 'PANORAMA_RESULT_EVENT_MISSING'
Check ((Text $layoutTemplate).Contains('Static body-only rendering baseline')) 'PANORAMA_STATIC_BASELINE_LABEL_MISSING'
Check ((Text $layoutTemplate).Contains('Not bone-merge evidence')) 'PANORAMA_STATIC_EVIDENCE_WARNING_MISSING'
Check ((Text $panoramaStyle).Contains('.TAPortraitScene')) 'PANORAMA_SCENE_STYLE_MISSING'

if ($GeneratedContentRoot -ne '') {
    Check (Test-Path -LiteralPath $GeneratedContentRoot -PathType Container) 'GENERATED_CONTENT_ROOT_MISSING'
    $generatedScene = Join-Path $GeneratedContentRoot 'maps\ta_portrait\templar_assassin.vmap'
    $generatedLayout = Join-Path $GeneratedContentRoot 'panorama\layout\custom_game\ta_portrait_probe.xml'
    $generatedData = Join-Path $GeneratedContentRoot 'panorama\scripts\custom_game\ta_portrait_probe_data.js'
    $generatedResolved = Join-Path $GeneratedContentRoot 'data\ta_portrait_resolved.csv'
    foreach ($generatedFile in @($generatedScene, $generatedLayout, $generatedData, $generatedResolved)) {
        Check (Test-Path -LiteralPath $generatedFile -PathType Leaf) "GENERATED_FILE_MISSING: $generatedFile"
    }

    $map = Text $generatedScene
    $classNames = Get-LinesWith $map '"classname" "string" "([^"]+)"'
    Check (($classNames | Where-Object { $_ -eq 'worldspawn' }).Count -eq 1) 'GENERATED_WORLDSPAWN_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -eq 'prop_dynamic' }).Count -eq 1) 'GENERATED_STATIC_BASELINE_PROP_DYNAMIC_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -eq 'env_global_light' }).Count -eq 1) 'GENERATED_LIGHT_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -eq 'point_camera' }).Count -eq 1) 'GENERATED_CAMERA_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -notin @('worldspawn', 'prop_dynamic', 'env_global_light', 'point_camera') }).Count -eq 0) 'GENERATED_UNEXPECTED_ENTITY_CLASS'
    Check (-not $map.Contains('portrait_world_unit')) 'GENERATED_PORTRAIT_WORLD_UNIT_FORBIDDEN'
    Check (-not $map.Contains('loadout_camera_model')) 'GENERATED_LOADOUT_CAMERA_FORBIDDEN'
    Check (-not $map.Contains('herocamera')) 'GENERATED_LEGACY_CAMERA_FORBIDDEN'
    Check (-not $map.Contains('!bonemerge')) 'GENERATED_BONEMERGE_KEY_FORBIDDEN'
    Check (-not $map.Contains('BoneMerge')) 'GENERATED_BONEMERGE_FIELD_FORBIDDEN'
    Check (-not $map.Contains('DisableBoneMerge')) 'GENERATED_DISABLE_BONEMERGE_FIELD_FORBIDDEN'
    Check ($map.Contains('"mapUsageType" "string" "background"')) 'GENERATED_MAP_USAGE_TYPE_INVALID'

    $bodyTargetname = Get-RowValue $scene 'body_targetname'
    $bodyBlock = Get-EntityBlockByTargetname $map $bodyTargetname
    Check ((Get-PropertyValue $bodyBlock 'classname' 'string') -eq 'prop_dynamic') 'GENERATED_BODY_CLASS_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'model' 'string') -eq (Get-RowValue $asset 'primary_model')) 'GENERATED_BODY_MODEL_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'parentname' 'string') -eq '') 'GENERATED_BODY_PARENT_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'StartingAnim' 'string') -eq 'idle') 'GENERATED_BODY_STARTING_ANIM_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'IdleAnim' 'string') -eq 'idle') 'GENERATED_BODY_IDLE_ANIM_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'updatechildren' 'string') -eq '1') 'GENERATED_BODY_UPDATE_CHILDREN_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'force_hidden' 'bool') -eq '0') 'GENERATED_BODY_FORCE_HIDDEN_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'editorOnly' 'bool') -eq '0') 'GENERATED_BODY_EDITOR_ONLY_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'origin' 'vector3') -eq (Get-RowValue $scene 'body_origin')) 'GENERATED_BODY_ORIGIN_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'angles' 'qangle') -eq (Get-RowValue $scene 'body_angles')) 'GENERATED_BODY_ANGLES_INVALID'
    Check ((Get-PropertyValue $bodyBlock 'scales' 'vector3') -eq '1 1 1') 'GENERATED_BODY_SCALES_INVALID'

    foreach ($component in $components) {
        $componentId = Get-RowValue $component 'component_id'
        Check (-not $map.Contains('ta_portrait_wearable_' + $componentId)) "GENERATED_STATIC_WEARABLE_ENTITY_FORBIDDEN: $componentId"
        Check (-not $map.Contains((Get-RowValue $component 'model_path'))) "GENERATED_STATIC_WEARABLE_MODEL_FORBIDDEN: $componentId"
    }

    $lightBlock = Get-EntityBlockByTargetname $map (Get-RowValue $scene 'light_targetname')
    Check ((Get-PropertyValue $lightBlock 'classname' 'string') -eq 'env_global_light') 'GENERATED_LIGHT_CLASS_INVALID'
    Check ((Get-PropertyValue $lightBlock 'StartDisabled' 'string') -eq '0') 'GENERATED_LIGHT_START_DISABLED_INVALID'
    $cameraBlock = Get-EntityBlockByTargetname $map (Get-RowValue $scene 'camera_name')
    Check ((Get-PropertyValue $cameraBlock 'classname' 'string') -eq 'point_camera') 'GENERATED_CAMERA_CLASS_INVALID'
    Check ((Get-PropertyValue $cameraBlock 'parentname' 'string') -eq '') 'GENERATED_CAMERA_PARENT_INVALID'
    Check ((Get-PropertyValue $cameraBlock 'parentAttachmentName' 'string') -eq '') 'GENERATED_CAMERA_ATTACHMENT_INVALID'
    Check ((Get-PropertyValue $cameraBlock 'FOV' 'string') -eq (Get-RowValue $scene 'camera_fov')) 'GENERATED_CAMERA_FOV_INVALID'

    $elementIds = Get-LinesWith $map '"id" "elementid" "([^"]+)"'
    Check (($elementIds | Select-Object -Unique).Count -eq $elementIds.Count) 'GENERATED_ELEMENT_IDS_NOT_UNIQUE'
    $referenceIds = @(Get-LinesWith $map '"referenceID" "uint64" "([^"]+)"' | Where-Object { $_ -ne '0x0' })
    Check (($referenceIds | Select-Object -Unique).Count -eq $referenceIds.Count) 'GENERATED_REFERENCE_IDS_NOT_UNIQUE'

    [xml]$layoutXml = Text $generatedLayout
    $scenePanel = $layoutXml.SelectSingleNode('//DOTAScenePanel[@id="TAPortraitScene"]')
    Check ($null -ne $scenePanel) 'GENERATED_SCENE_PANEL_MISSING'
    Check ($scenePanel.GetAttribute('map') -eq (Get-RowValue $scene 'scene_map')) 'GENERATED_SCENE_PANEL_MAP_INVALID'
    Check ($scenePanel.GetAttribute('camera') -eq (Get-RowValue $scene 'camera_name')) 'GENERATED_SCENE_PANEL_CAMERA_INVALID'
    Check ($scenePanel.GetAttribute('light') -eq (Get-RowValue $scene 'light_targetname')) 'GENERATED_SCENE_PANEL_LIGHT_INVALID'
    Check ($scenePanel.GetAttribute('particleonly') -eq (Get-RowValue $scene 'particle_only')) 'GENERATED_SCENE_PANEL_PARTICLE_ONLY_INVALID'
    Check (-not (Text $generatedLayout).Contains('__')) 'GENERATED_LAYOUT_PLACEHOLDER_REMAINS'

    $dataMatch = [regex]::Match((Text $generatedData), 'TAPortraitProbeData\s*=\s*(\{.*\});')
    Check ($dataMatch.Success) 'GENERATED_DATA_OBJECT_MISSING'
    $data = ConvertFrom-Json -InputObject $dataMatch.Groups[1].Value
    Check ($data.addonName -eq 'survival_ta_portrait_probe') 'GENERATED_DATA_ADDON_INVALID'
    Check ($data.assetId -eq $assetId) 'GENERATED_DATA_ASSET_INVALID'
    Check ($data.runtimeTable.name -eq 'ta_portrait_probe') 'GENERATED_DATA_RUNTIME_TABLE_INVALID'
    Check ($data.runtimeTable.key -eq 'runtime') 'GENERATED_DATA_RUNTIME_KEY_INVALID'
    Check ($data.body.model -eq (Get-RowValue $asset 'primary_model')) 'GENERATED_DATA_BODY_INVALID'
    Check ($data.wearables.Count -eq 3) 'GENERATED_DATA_WEARABLE_COUNT_INVALID'
    for ($index = 0; $index -lt 3; $index++) {
        Check ($data.wearables[$index].model -eq $expectedModels[$index]) "GENERATED_DATA_WEARABLE_MODEL_INVALID: $index"
        Check ($data.wearables[$index].attachMode -eq 'bone_merge') "GENERATED_DATA_WEARABLE_ATTACH_MODE_INVALID: $index"
    }
    $resolved = @(Import-Csv -LiteralPath $generatedResolved)
    Check ($resolved.Count -eq 4) 'GENERATED_RESOLVED_ROW_COUNT_INVALID'
    Check (($resolved | Where-Object kind -eq 'body').Count -eq 1) 'GENERATED_RESOLVED_BODY_COUNT_INVALID'
    Check (($resolved | Where-Object kind -eq 'wearable').Count -eq 3) 'GENERATED_RESOLVED_WEARABLE_COUNT_INVALID'
    Check (($resolved | Where-Object { $_.attach_mode -eq 'bone_merge' }).Count -eq 3) 'GENERATED_RESOLVED_BONE_MERGE_COUNT_INVALID'
    Check (($resolved | Where-Object { -not [string]::IsNullOrEmpty($_.parentname) }).Count -eq 0) 'GENERATED_RESOLVED_STATIC_PARENT_FORBIDDEN'
}

if ($GeneratedGameRoot -ne '') {
    Check (Test-Path -LiteralPath $GeneratedGameRoot -PathType Container) 'GENERATED_GAME_ROOT_MISSING'
    foreach ($runtimeFile in @('addoninfo.txt', 'scripts\vscripts\addon_game_mode.lua', 'scripts\vscripts\ta_portrait_probe_runtime_config.lua', 'data\scene.csv', 'data\ta_portrait_resolved.csv')) {
        Check (Test-Path -LiteralPath (Join-Path $GeneratedGameRoot $runtimeFile) -PathType Leaf) "GENERATED_GAME_FILE_MISSING: $runtimeFile"
    }
    $generatedRuntime = Text (Join-Path $GeneratedGameRoot 'scripts\vscripts\addon_game_mode.lua')
    Check ($generatedRuntime -eq $runtimeText) 'GENERATED_RUNTIME_SOURCE_MISMATCH'
    $generatedConfig = Text (Join-Path $GeneratedGameRoot 'scripts\vscripts\ta_portrait_probe_runtime_config.lua')
    Check ($generatedConfig.Contains('source = "generated_from_csv"')) 'GENERATED_RUNTIME_CONFIG_SOURCE_MISSING'
    Check ($generatedConfig.Contains('model = "' + (Get-RowValue $asset 'primary_model') + '"')) 'GENERATED_RUNTIME_BODY_MODEL_INVALID'
    Check ($generatedConfig.Contains('sequence = "' + (Get-RowValue $asset 'default_sequence') + '"')) 'GENERATED_RUNTIME_BODY_SEQUENCE_INVALID'
    Check ([regex]::Matches($generatedConfig, 'entity_class = "prop_dynamic"').Count -eq 3) 'GENERATED_RUNTIME_ENTITY_CLASS_COUNT_INVALID'
    Check ([regex]::Matches($generatedConfig, 'attach_mode = "bone_merge"').Count -eq 3) 'GENERATED_RUNTIME_ATTACH_MODE_COUNT_INVALID'
    foreach ($component in $components) {
        $componentId = Get-RowValue $component 'component_id'
        Check ($generatedConfig.Contains('id = "' + $componentId + '"')) "GENERATED_RUNTIME_COMPONENT_ID_MISSING: $componentId"
        Check ($generatedConfig.Contains('model = "' + (Get-RowValue $component 'model_path') + '"')) "GENERATED_RUNTIME_COMPONENT_MODEL_MISSING: $componentId"
    }
    $generatedWearables = [regex]::Match($generatedConfig, '(?s)wearables\s*=\s*\{(.*)\}\s*,?\s*\}\s*$').Groups[1].Value
    Check ($generatedWearables -ne '') 'GENERATED_RUNTIME_WEARABLE_CONFIG_MISSING'
    Check (-not $generatedWearables.Contains('sequence')) 'GENERATED_RUNTIME_WEARABLE_SEQUENCE_FORBIDDEN'
}

Write-Host 'TA_PORTRAIT_PROBE_CONTRACT_PASS' -ForegroundColor Green
