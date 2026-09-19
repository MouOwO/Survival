$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $root))
$contentRoot = Join-Path $dotaRoot 'content\dota_addons\survival'

function Read-Utf8($path) {
    return [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false))
}

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$input = Read-Utf8 (Join-Path $contentRoot 'panorama\scripts\custom_game\attack_range_input.js')
$layout = Read-Utf8 (Join-Path $contentRoot 'panorama\layout\custom_game\survival_hud.xml')
$service = Read-Utf8 (Join-Path $root 'scripts\vscripts\systems\attack_range_display_service.lua')
$mode = Read-Utf8 (Join-Path $root 'scripts\vscripts\addon_game_mode.lua')

Check ($input.Contains('SurvivalInputDispatcher')) 'ATTACK_RANGE_DISPATCHER_MISSING'
Check ($input.Contains('String(key).toUpperCase() !== "A"')) 'ATTACK_RANGE_A_BIND_MISSING'
Check ($input.Contains('return false;')) 'ATTACK_RANGE_NATIVE_INPUT_NOT_PASSED'
Check ($input.Contains('survival_attack_range_visibility')) 'ATTACK_RANGE_EVENT_MISSING'
Check ($layout.Contains('attack_range_input.js')) 'ATTACK_RANGE_LAYOUT_INCLUDE_MISSING'
Check ($service.Contains('survival_attack_range')) 'ATTACK_RANGE_HERO_RUNTIME_FALLBACK_MISSING'
Check ($service.Contains('Script_GetAttackRange') -and $service.Contains('GetAttackRange')) 'ATTACK_RANGE_ENGINE_FALLBACK_MISSING'
Check ($service.Contains('tower_attack_range')) 'ATTACK_RANGE_TOWER_CSV_MISSING'
Check ($service.Contains('ParticleManager:DestroyParticle')) 'ATTACK_RANGE_CLEANUP_MISSING'
Check ($mode.Contains('attack_range_display_service.init()')) 'ATTACK_RANGE_SERVICE_NOT_INITIALIZED'
Write-Output 'ATTACK_RANGE_DISPLAY_CONTRACT_PASS'