$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$worker = Get-Content -Raw -Encoding UTF8 (Join-Path $root "scripts/vscripts/systems/worker_system.lua")
$personality = Get-Content -Raw -Encoding UTF8 (Join-Path $root "scripts/vscripts/config/generated/lumberjack_personality_definitions.lua")

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Check ($personality.Contains('skill_id = "lumberjack_personality_self_pua"') -and
    $personality.Contains('effect_type = "attack_growth"') -and
    $personality.Contains('effect_value = 5')) `
    "SELF_PUA_CONFIG_MISSING"
Check ($worker.Contains('personality_value(') -and
    $worker.Contains('worker, "attack_growth"')) `
    "SELF_PUA_FUSION_PROJECTION_MISSING"
Check ($worker.Contains('attacker_state = workers[attacker_entindex]')) `
    "SELF_PUA_ATTACKER_NOT_RESOLVED_BY_ENTINDEX"
Check ($worker.Contains('attacker_state.personality_attack_growth_per_hit')) `
    "SELF_PUA_GROWTH_INCREMENT_MISSING"
Check ($worker.Contains('apply_lumberjack_attack(attacker_state, lumberjack.attack_flat)')) `
    "SELF_PUA_ATTACK_NOT_REPROJECTED"
Check ($worker.Contains('reason = "lumberjack_self_pua_growth"') -and
    $worker.IndexOf('reason = "lumberjack_self_pua_growth"') -gt
        $worker.IndexOf('apply_lumberjack_attack(attacker_state, lumberjack.attack_flat)')) `
    "SELF_PUA_UI_REFRESH_EVENT_MISSING"
Check ($worker.Contains('state.unit:CalculateStatBonus(true)')) `
    "SELF_PUA_ENGINE_STATS_NOT_REFRESHED"

Write-Output "LUMBERJACK_SELF_PUA_CONTRACT_PASS"