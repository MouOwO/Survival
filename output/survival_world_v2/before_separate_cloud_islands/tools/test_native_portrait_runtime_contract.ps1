param(
    [string]$ContentRoot = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ContentRoot)) {
    $dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $repo))
    $ContentRoot = Join-Path $dotaRoot 'content\dota_addons\survival'
}

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function ReadText([string]$path) {
    Check (Test-Path -LiteralPath $path -PathType Leaf) "MISSING_FILE: $path"
    return [IO.File]::ReadAllText($path)
}

$script = ReadText (Join-Path $ContentRoot 'panorama\scripts\custom_game\combat_stats.js')
$layout = ReadText (Join-Path $ContentRoot 'panorama\layout\custom_game\survival_hud.xml')
$style = ReadText (Join-Path $ContentRoot 'panorama\styles\custom_game\survival_hud.css')

Check ($layout.Contains('id="SurvivalTowerPortraitOverlay"')) 'TOWER_OVERLAY_MISSING'
Check ($layout.Contains('id="SurvivalTowerPortraitScene"')) 'SCENE_PANEL_MISSING'
Check (([regex]::Matches($layout, '<DOTAScenePanel\b')).Count -eq 1) 'NON_TOWER_SCENE_PANEL_REMAINED'
Check (-not $layout.Contains('SurvivalNativePortraitVideoOverlay')) 'LEGACY_PORTRAIT_OVERLAY_REMAINED'
Check (-not $layout.Contains('SurvivalHeroPortraitMovie')) 'VIDEO_PORTRAIT_REMAINED'
Check (-not $layout.Contains('SurvivalHeroPortraitImage')) 'IMAGE_PORTRAIT_REMAINED'
Check ($style.Contains('overflow: clip;')) 'PORTRAIT_CLIP_MISSING'
Check ($style.Contains('.SurvivalTowerPortraitOverlay')) 'TOWER_OVERLAY_STYLE_MISSING'
Check ($style.Contains('.SurvivalTowerPortraitOverlay .SurvivalTowerPortraitScene')) 'TOWER_SCENE_STYLE_MISSING'
$overlayStyle = [regex]::Match(
    $style,
    '(?s)\.SurvivalTowerPortraitOverlay\s*\{(?<body>.*?)\}'
)
Check ($overlayStyle.Success) 'TOWER_OVERLAY_STYLE_BLOCK_MISSING'
Check (-not $overlayStyle.Groups['body'].Value.Contains('transform:')) 'TOWER_OVERLAY_SCALE_REMAINED'
Check ($overlayStyle.Groups['body'].Value.Contains('z-index: 0;')) 'TOWER_OVERLAY_DEFAULT_LAYER_MISSING'
Check ($overlayStyle.Groups['body'].Value.Contains('background-color: #10151aff;')) 'TOWER_TRANSITION_MASK_BACKGROUND_MISSING'
Check ($script.Contains('function portraitRect(target)')) 'PORTRAIT_RECT_HELPER_MISSING'
Check ($script.Contains('anchor_id=')) 'ANCHOR_ID_DIAGNOSTIC_MISSING'
Check ($script.Contains('layer=')) 'LAYER_RECT_DIAGNOSTIC_MISSING'
Check ($script.Contains('anchor=')) 'ANCHOR_RECT_DIAGNOSTIC_MISSING'
Check ($script.Contains('overlay_actual=')) 'OVERLAY_RECT_DIAGNOSTIC_MISSING'
Check ($script.Contains('scene_rect=')) 'SCENE_RECT_DIAGNOSTIC_MISSING'
Check ($script.Contains('scale=')) 'UI_SCALE_DIAGNOSTIC_MISSING'
Check (-not $script.Contains('NATIVE_PORTRAIT_SCENE_SCALE')) 'SCENE_SCALE_CONSTANT_REMAINED'
Check (-not $style.Contains('scale3d(0.8, 0.8, 1.0)')) 'SCENE_SCALE_STYLE_REMAINED'
Check ($script.Contains('var TOWER_PORTRAIT_CONTENT_SCALE = 0.90;')) 'TOWER_CONTENT_SCALE_MISSING'
Check ($script.Contains('function applyTowerPortraitContentScale(scene)')) 'TOWER_CONTENT_SCALE_APPLY_MISSING'
Check ($script.Contains('function resetTowerPortraitContentScale(scene)')) 'TOWER_CONTENT_SCALE_RESET_MISSING'
Check ($script.Contains('scene.style.transformOrigin = "50% 50%"')) 'TOWER_CONTENT_SCALE_ORIGIN_CHANGED'
Check ($script.Contains('applyTowerPortraitContentScale(scene);')) 'TOWER_CONTENT_SCALE_NOT_APPLIED'
Check ($script.Contains('resetTowerPortraitContentScale(scene);')) 'TOWER_CONTENT_SCALE_NOT_RESET'
Check ($script.Contains('hideCosmeticPortrait("context_shutdown")')) 'TOWER_CONTENT_SCALE_SHUTDOWN_RESET_MISSING'
Check ($script.Contains('function dimNativePortraitOpacity(anchor)')) 'NATIVE_PORTRAIT_DIM_MISSING'
Check ($script.Contains('function restoreNativePortraitOpacity()')) 'NATIVE_PORTRAIT_RESTORE_MISSING'
Check ($script.Contains('function restoreNativePortraitsExcept(anchor)')) 'NATIVE_PORTRAIT_ANCHOR_RESTORE_MISSING'
Check ($script.Contains('function nativePortraitScenePanel(container, root, depth)')) 'NATIVE_SCENE_PANEL_LOOKUP_MISSING'
Check ($script.Contains('function mountTowerPortraitAtNativeLayer(overlay, anchor)')) 'NATIVE_LAYER_MOUNT_MISSING'
Check ($script.Contains('overlay.SetParent(host)')) 'NATIVE_LAYER_REPARENT_MISSING'
Check ($script.Contains('host.MoveChildAfter(overlay, anchor)')) 'NATIVE_LAYER_ORDER_MISSING'
Check ($script.Contains('function restoreTowerPortraitHome(overlay)')) 'TOWER_LAYER_HOME_RESTORE_MISSING'
Check ($script.Contains('anchor.style.opacity = "0"')) 'NATIVE_PORTRAIT_TRANSPARENCY_MISSING'
Check ($script.Contains('function unitUsesTowerPortrait(unit)')) 'TOWER_TRANSITION_IDENTITY_MISSING'
Check ($script.Contains('=== "ability_destroy_arrow_tower"')) 'TOWER_TRANSITION_ABILITY_IDENTITY_MISSING'
Check ($script.Contains('function holdTowerPortraitTransition(reason)')) 'TOWER_TRANSITION_MASK_MISSING'
Check ($script.Contains('scene.style.visibility = "collapse"')) 'TOWER_TRANSITION_SCENE_HIDE_MISSING'
Check ($script.Contains('transitionCosmeticPortrait("selection_transition")')) 'TOWER_SELECTION_TRANSITION_MASK_UNUSED'
Check ($script.Contains('transitionCosmeticPortrait("snapshot_pending")')) 'TOWER_SNAPSHOT_TRANSITION_MASK_UNUSED'
Check ($script.Contains('var activePortraitEntity = -1;')) 'ACTIVE_PORTRAIT_ENTITY_MISSING'
Check ($script.Contains('function towerPortraitEntityUnchanged(unit)')) 'SAME_ENTITY_PORTRAIT_GUARD_MISSING'
Check ($script.Contains('if (towerPortraitEntityUnchanged(Number(displayUnit()))) return;')) 'SAME_ENTITY_PORTRAIT_GUARD_UNUSED'
Check ($script.Contains('activePortraitEntity = Number(snapshot.entindex);')) 'ACTIVE_PORTRAIT_ENTITY_NOT_RECORDED'
Check ($script.Contains('scene.SetUnit(portraitUnit, "default", false)')) 'SCENE_SET_UNIT_CONTRACT_CHANGED'
Check ($script.Contains('var portraitMode = "tower_scene"')) 'TOWER_PORTRAIT_MODE_MISSING'
Check ($script.Contains('|| !isTowerPortrait')) 'NON_TOWER_PORTRAIT_GUARD_MISSING'
Check (-not $script.Contains('isVideoPortrait')) 'VIDEO_PORTRAIT_RUNTIME_REMAINED'
Check (-not $script.Contains('isImagePortrait')) 'IMAGE_PORTRAIT_RUNTIME_REMAINED'
Check (-not $script.Contains('SetPlaybackVolume')) 'VIDEO_PLAYBACK_RUNTIME_REMAINED'
Check (-not $script.Contains('candidate)) return candidate')) 'SHARED_PORTRAIT_FALLBACK_REMAINED'

Write-Output 'NATIVE_PORTRAIT_RUNTIME_CONTRACT_PASS'
