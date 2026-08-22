$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $PSScriptRoot
$WaveSystemPath = Join-Path $Root 'scripts\vscripts\systems\wave_system.lua'
$PreloadPath = Join-Path $Root 'scripts\vscripts\systems\asset_preload_service.lua'
$CsvPath = Join-Path $Root 'data\csv\资源系统\asset_catalog.csv'
$GeneratedPath = Join-Path $Root 'scripts\vscripts\config\generated\asset_catalog.lua'

$WaveSystem = Get-Content -LiteralPath $WaveSystemPath -Raw -Encoding utf8
$Preload = Get-Content -LiteralPath $PreloadPath -Raw -Encoding utf8
$Csv = Get-Content -LiteralPath $CsvPath -Raw -Encoding utf8
$Generated = Get-Content -LiteralPath $GeneratedPath -Raw -Encoding utf8

if ($WaveSystem -notmatch 'local function wave_model_paths\(wave\)') {
    throw 'UNIFIED_WAVE_MODEL_COLLECTOR_MISSING'
}
if ($WaveSystem -notmatch 'debug_wave_model_asset_ids[\s\S]*model_path_for\(row, definition\)') {
    throw 'DEV_PRELOAD_MODEL_RESOLUTION_MISMATCH'
}
if ($WaveSystem -notmatch 'apply_stats[\s\S]*model_path_for\(row, definition\)') {
    throw 'SPAWN_MODEL_RESOLUTION_MISMATCH'
}
if (($WaveSystem -notmatch 'queue_target_wave\("countdown_start"\)') -or
        ($WaveSystem -notmatch 'queue_target_wave\("lead_review"\)')) {
    throw 'FORMAL_PRELOAD_TWO_PHASE_REQUEST_MISSING'
}
if (($WaveSystem -notmatch 'TODO\(FINAL_WAVE_MODELS\)') -or
        ($WaveSystem -notmatch 'TODO\(SOURCE2_MODEL_UNLOAD\)')) {
    throw 'MODEL_LIFECYCLE_TODO_MISSING'
}
if ($WaveSystem -match 'asset_preload\.retire\s*\(') {
    throw 'WAVE_SYSTEM_MUST_NOT_RETIRE_MODEL_ASSETS'
}
if ($Preload -notmatch 'begin_async_request\(asset_id, "urgent"\)') {
    throw 'URGENT_PRELOAD_PARALLEL_START_MISSING'
}
if ($Csv -notmatch '(?m)^monster_visage,[^\r\n]*,770,8,streamed,') {
    throw 'VISAGE_CSV_FIRST_USE_WAVE_INVALID'
}
if ($Generated -notmatch 'asset_id = "monster_visage"[^\r\n]*first_use_wave = 8') {
    throw 'VISAGE_GENERATED_FIRST_USE_WAVE_INVALID'
}

Write-Output 'WAVE_MODEL_RESOURCE_LIFECYCLE_CONTRACT_PASS'