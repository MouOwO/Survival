$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$csv = Get-ChildItem -LiteralPath (Join-Path $root "data/csv") `
    -Filter "training_definitions.csv" -File -Recurse |
    Select-Object -First 1
$rows = Import-Csv -LiteralPath $csv.FullName |
    Where-Object { $_.training_id -in @("train_repairer_01", "train_repairer_02") }
Check ($rows.Count -eq 2) "REPAIRER_ROWS_MISSING"
foreach ($row in $rows) {
    Check ($row.active_skill_ids -eq "ability_repairer_suicide") `
        "REPAIRER_SUICIDE_SKILL_NOT_IN_CSV_$($row.training_id)"
    Check ([int]$row.population_cost -eq 1) `
        "REPAIRER_POPULATION_COST_CHANGED_$($row.training_id)"
}

$worker = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/systems/worker_system.lua") -Raw
$ability = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/abilities/ability_repairer_suicide.lua") -Raw
$kv = Get-Content -LiteralPath (Join-Path $root `
    "scripts/npc/npc_abilities_custom.txt") -Raw
$tooltipBuilder = Get-Content -LiteralPath (Join-Path $root `
    "tools/build_tooltip_definitions.py") -Raw
$tooltip = Get-Content -LiteralPath (Join-Path $root `
    "scripts/vscripts/config/generated/tooltip_definitions.lua") -Raw

Check ($worker.Contains("training.active_skill_ids")) "WORKER_CSV_SKILL_MOUNT_MISSING"
Check ($worker.Contains("worker:AddAbility(ability_name)")) "WORKER_SKILL_ADD_MISSING"
Check ($ability.Contains("events.WORKER_DISMISS_REQUEST")) "SUICIDE_DISMISS_REQUEST_MISSING"
Check ($worker.Contains("worker:ForceKill(false)")) "SUICIDE_FORCE_KILL_MISSING"
Check ($worker.Contains("victim_entindex")) "WORKER_DEATH_ENTINDEX_FALLBACK_MISSING"
Check ($worker.Contains("active_worker_count")) "REPAIRER_LIVING_LIMIT_MISSING"
Check (-not $ability.Contains("RESOURCE_ADD_REQUEST")) "SUICIDE_RESOURCE_REFUND_ADDED"
Check (-not $ability.Contains("RESOURCE_RELEASE_POP_REQUEST")) "SUICIDE_DIRECT_POP_MUTATION_ADDED"
Check ($kv.Contains('"ability_repairer_suicide"')) "SUICIDE_ABILITY_KV_MISSING"
Check ($tooltipBuilder.Contains("worker_skill_definitions.csv")) "WORKER_TOOLTIP_SOURCE_MISSING"
Check ($tooltip.Contains("ability_repairer_suicide")) "SUICIDE_TOOLTIP_GENERATED_MISSING"

Write-Host "REPAIRER_SUICIDE_CONTRACT_OK"