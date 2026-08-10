$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$csvMatches = @(
    Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
        -Filter "training_definitions.csv" `
        -File `
        -Recurse
)
if ($csvMatches.Count -ne 1) {
    throw (
        "Expected exactly one training_definitions.csv, found {0}" -f `
            $csvMatches.Count
    )
}
$csvPath = $csvMatches[0].FullName
$generatedPath = Join-Path $root "scripts\vscripts\config\generated\training_definitions.lua"
$modifierPath = Join-Path $root "scripts\vscripts\modifiers\modifier_repair_worker_ai.lua"
$workerPath = Join-Path $root "scripts\vscripts\systems\worker_system.lua"
$builderPath = Join-Path $root "scripts\vscripts\systems\builder_progression_system.lua"

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$rows = Import-Csv -LiteralPath $csvPath | Where-Object {
    $_.training_id -like "train_repairer_*"
}
Check ($rows.Count -gt 0) "REPAIR_PERCENTAGE_ROWS_MISSING"
foreach ($row in $rows) {
    $expected = if ($row.training_id -eq "train_repairer_01") { 1.4 } else { 2.0 }
    Check ([double]$row.repair_max_health_pct_per_second -eq $expected) `
        "REPAIR_PERCENTAGE_TIER_MISMATCH_$($row.training_id)"
}

$generated = Get-Content -LiteralPath $generatedPath -Raw
$modifier = Get-Content -LiteralPath $modifierPath -Raw
$worker = Get-Content -LiteralPath $workerPath -Raw
$builder = Get-Content -LiteralPath $builderPath -Raw

Check (-not $generated.Contains("repair_per_second")) `
    "REPAIR_FIXED_VALUE_REMAINS_IN_GENERATED_CONFIG"
Check (-not $modifier.Contains("repair_per_second")) `
    "REPAIR_FIXED_VALUE_REMAINS_IN_MODIFIER"
Check (-not $worker.Contains("repair_per_second")) `
    "REPAIR_FIXED_VALUE_REMAINS_IN_WORKER_SYSTEM"
Check (-not $builder.Contains("repair_per_second")) `
    "REPAIR_FIXED_VALUE_REMAINS_IN_BUILDER_SYSTEM"
Check ($modifier.Contains("building:GetMaxHealth()")) `
    "REPAIR_MAX_HEALTH_CALCULATION_MISSING"
Check ($modifier.Contains("repair_math.whole_amount_for_interval")) `
    "REPAIR_PERCENTAGE_MATH_CALL_MISSING"
Check ($modifier.Contains("repair_fractional_remainder")) `
    "REPAIR_FRACTIONAL_REMAINDER_MISSING"
Check ($worker.Contains('worker_training_progress.create(')) `
    "REPAIR_TRAINING_TRACKER_MISSING"
Check ($worker.Contains('"train_repairer_"')) `
    "REPAIR_TRAINING_PREFIX_MISSING"
Check ($worker.Contains('training_id == "train_repairer_auto"')) `
    "REPAIR_AUTO_TRAINING_REQUEST_MISSING"
Check ($worker.Contains('repairer_training:record_explicit(')) `
    "REPAIR_SUCCESS_PROGRESSION_MISSING"
Check ($worker.Contains('if progress.completed == 1 then')) `
    "REPAIR_FINAL_TIER_REJECTION_MISSING"
Check ($worker.Contains('repairer_training:reset()')) `
    "REPAIR_TRAINING_RESET_MISSING"
Check ($worker.Contains('event_bus.handle_request(events.WORKER_TRAIN_REQUEST')) `
    "WORKER_TRAINING_NOT_SYNCHRONOUS"

Write-Host "REPAIR_WORKER_PERCENTAGE_CONTRACT_OK"