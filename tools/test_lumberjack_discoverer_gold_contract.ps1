$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$tree = Get-Content -Raw -Encoding UTF8 (Join-Path $root "scripts/vscripts/systems/tree_system.lua")
$particles = Get-Content -Raw -Encoding UTF8 (Join-Path $root "scripts/vscripts/core/particle_manager.lua")
$personality = Get-Content -Raw -Encoding UTF8 (Join-Path $root "scripts/vscripts/config/generated/lumberjack_personality_definitions.lua")
$modifier = Get-Content -Raw -Encoding UTF8 (Join-Path $root "scripts/vscripts/modifiers/modifier_lumberjack_ai.lua")
$dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $root))
$content = Join-Path $dotaRoot "content\dota_addons\survival"
$goldNumbers = Get-Content -Raw -Encoding UTF8 (Join-Path $content `
    "panorama\scripts\custom_game\gold_mine_income_numbers.js")

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Check ($personality.Contains('skill_id = "lumberjack_personality_discoverer"') -and
    $personality.Contains('effect_type = "gold_per_hit_flat"') -and
    $personality.Contains('effect_value = 10')) `
    "DISCOVERER_CONFIG_MISSING"
Check ($tree.Contains('gold = tonumber(payload.gold_per_hit_flat) or 0')) `
    "DISCOVERER_GOLD_REWARD_MISSING"
Check ($tree.Contains('"survival_gold_mine_income_number"') -and
    $tree.Contains('target_entindex = attacker:entindex()') -and
    $tree.Contains('critical = 0')) `
    "DISCOVERER_GOLD_MINE_VISUAL_EVENT_MISSING"
Check ($tree.IndexOf('"survival_gold_mine_income_number"') -gt
    $tree.IndexOf('if not result or result.ok ~= true then return end')) `
    "DISCOVERER_NUMBER_SHOWN_BEFORE_RESOURCE_SUCCESS"
Check (-not $tree.Contains('particle_manager.show_gold_number(') -and
    -not $particles.Contains('OVERHEAD_ALERT_GOLD')) `
    "DISCOVERER_NATIVE_GOLD_OVERHEAD_RESTORED"
Check ($goldNumbers.Contains(
    'GameEvents.Subscribe("survival_gold_mine_income_number", show)'
)) "DISCOVERER_GOLD_MINE_VISUAL_SUBSCRIPTION_MISSING"
Check (-not $tree.Contains('sound_service') -and
    -not $tree.Contains('EmitSound') -and
    -not $tree.Contains('StartSoundEvent')) `
    "DISCOVERER_GOLD_VISUAL_PLAYS_SOUND"
Check ($modifier.Contains('function M:OnRefresh(params)') -and
    $modifier.Contains('apply_runtime_params(self, params)')) `
    "DISCOVERER_FUSION_MODIFIER_REFRESH_MISSING"

Write-Output "LUMBERJACK_DISCOVERER_GOLD_CONTRACT_PASS"