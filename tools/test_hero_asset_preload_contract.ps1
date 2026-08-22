$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$csvRoot = Join-Path $root "data/csv"
$catalogPath = [System.IO.Directory]::GetFiles(
    $csvRoot, "asset_catalog.csv", [System.IO.SearchOption]::AllDirectories
)
$componentsPath = [System.IO.Directory]::GetFiles(
    $csvRoot, "asset_components.csv", [System.IO.SearchOption]::AllDirectories
)
$effectsPath = [System.IO.Directory]::GetFiles(
    $csvRoot, "asset_effects.csv", [System.IO.SearchOption]::AllDirectories
)
if ($catalogPath.Count -ne 1 -or $componentsPath.Count -ne 1 -or
    $effectsPath.Count -ne 1) {
    throw "asset CSV files are missing or duplicated"
}
$catalog = Import-Csv -LiteralPath $catalogPath[0]
$components = Import-Csv -LiteralPath $componentsPath[0]
$effects = Import-Csv -LiteralPath $effectsPath[0]
$units = [System.IO.File]::ReadAllText((Join-Path $root "scripts/npc/npc_units_custom.txt"))
$abilityFactory = [System.IO.File]::ReadAllText((Join-Path $root "scripts/vscripts/abilities/hero_summon_ability_factory.lua"))
$uiRouter = [System.IO.File]::ReadAllText((Join-Path $root "scripts/vscripts/ui/ui_request_router.lua"))

$heroes = @(
    "hero_doom", "hero_shadow_fiend", "hero_axe",
    "hero_drow_ranger", "hero_monkey_king", "hero_blademaster"
)
$expectedComponents = @{
    hero_doom = 0; hero_shadow_fiend = 0; hero_axe = 5
    hero_drow_ranger = 0; hero_monkey_king = 4; hero_blademaster = 5
}

foreach ($hero in $heroes) {
    $assetId = "hero_permanent_$hero"
    $row = @($catalog | Where-Object asset_id -eq $assetId)
    if ($row.Count -ne 1) { throw "bundle missing or duplicated: $assetId" }
    if ($row[0].load_group -ne "hero_permanent" -or
        $row[0].resident_policy -ne "permanent" -or
        $row[0].async_unit_name -ne "asset_proxy_$hero") {
        throw "bundle policy mismatch: $assetId"
    }
    $componentRows = @($components | Where-Object asset_id -eq $assetId)
    if ($componentRows.Count -ne $expectedComponents[$hero]) {
        throw "component count mismatch: $assetId"
    }
    if ($units -notmatch ('"asset_proxy_' + [regex]::Escape($hero) + '"')) {
        throw "proxy missing: asset_proxy_$hero"
    }
    foreach ($component in $componentRows) {
        if ($units -notmatch [regex]::Escape($component.model_path)) {
            throw "proxy dependency missing: $($component.model_path)"
        }
    }
}

$monkeyEffects = @($effects | Where-Object asset_id -eq "hero_permanent_hero_monkey_king")
if ($monkeyEffects.Count -ne 4) { throw "Monkey King ambient effects incomplete" }
foreach ($effect in $monkeyEffects) {
    if ($effect.effect_role -ne "ambient" -or
        $units -notmatch [regex]::Escape($effect.particle_path)) {
        throw "Monkey King proxy particle dependency missing"
    }
}

foreach ($source in @($abilityFactory, $uiRouter)) {
    if ($source -notmatch 'on_completed\s*=\s*function' -or
        $source -notmatch 'ability:EndCooldown\(\)') {
        throw "altar summon entry does not release cooldown after final failure"
    }
}

Write-Output "HERO_ASSET_PRELOAD_CONTRACT_PASS"