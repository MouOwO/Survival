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
    Check ([double]$row.repair_max_health_pct_per_second -eq 2) `
        "REPAIR_PERCENTAGE_NOT_TWO_FOR_$($row.training_id)"
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

Write-Host "REPAIR_WORKER_PERCENTAGE_CONTRACT_OK"