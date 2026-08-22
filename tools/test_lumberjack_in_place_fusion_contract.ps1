$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$fusionPath = Join-Path $root "scripts/vscripts/systems/lumberjack_fusion_service.lua"
$workerPath = Join-Path $root "scripts/vscripts/systems/worker_system.lua"
$fusion = Get-Content -Raw -Encoding UTF8 $fusionPath
$worker = Get-Content -Raw -Encoding UTF8 $workerPath
$commitStart = $worker.IndexOf("function M.commit_lumberjack_fusion")
$commitEnd = $worker.IndexOf("function M.rollback_fused_lumberjack", $commitStart)
$commit = if ($commitStart -ge 0 -and $commitEnd -gt $commitStart) {
    $worker.Substring($commitStart, $commitEnd - $commitStart)
} else {
    ""
}

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Check ($fusion.Contains('local result = { caster }')) `
    "FUSION_CASTER_NOT_FIXED_AS_FIRST_MATERIAL"
Check ($fusion.Contains('local target = caster')) `
    "FUSION_TARGET_IS_NOT_CASTER"
Check (-not $fusion.Contains('CreateUnitByName(')) `
    "FUSION_STILL_CREATES_A_NEW_TARGET"
Check ($fusion.Contains('model_scale = 1.5')) `
    "FUSION_MODEL_SCALE_NOT_1_5"
Check ($worker.Contains('data.population = preserved_population')) `
    "FUSION_POPULATION_NOT_PRESERVED"
Check ($worker.Contains('population_released = 0')) `
    "FUSION_REPORTS_POPULATION_RELEASE"
Check ($commit.Length -gt 0) "FUSION_COMMIT_FUNCTION_MISSING"
Check (-not $commit.Contains('RESOURCE_RELEASE_POP_REQUEST')) `
    "FUSION_COMMIT_RELEASES_POPULATION"
Check ($commit.Contains('if state.unit:entindex() ~= target_entindex then')) `
    "FUSION_TARGET_KILL_GUARD_MISSING"
Check ($commit.Contains('workers[state.unit:entindex()] = nil') -and
    $commit.IndexOf('workers[state.unit:entindex()] = nil') -lt
    $commit.IndexOf('state.unit:ForceKill(false)')) `
    "FUSION_MATERIAL_NOT_UNREGISTERED_BEFORE_KILL"
Check ($worker.Contains('worker:RemoveAbility(data.fusion_ability_name)')) `
    "FUSION_ABILITY_NOT_REMOVED_FROM_TARGET"
Check ($commit.Contains('target.survival_lumberjack_fusion_pending = nil')) `
    "FUSION_TARGET_PENDING_NOT_CLEARED"

Write-Output "LUMBERJACK_IN_PLACE_FUSION_CONTRACT_PASS"