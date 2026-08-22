$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$contentRoot = Resolve-Path (Join-Path $root "../../../content/dota_addons/survival")
$sourcePath = Join-Path $contentRoot "panorama/scripts/custom_game/combat_stats.js"
$source = [System.IO.File]::ReadAllText($sourcePath)

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Check ($source.Contains('function isFarmUnit(unitName)')) `
    "FARM_UNIT_PREDICATE_MISSING"
Check ($source.Contains('String(unitName || "") === "building_farm"')) `
    "FARM_UNIT_IDENTITY_INVALID"
Check ($source.Contains('name === "building_gold_mine"')) `
    "GOLD_MINE_UNIT_IDENTITY_INVALID"
Check ($source.Contains('setOfficialPanelVisible(root, "Armor", !isArmorHiddenUnit(unitName));')) `
    "FARM_NATIVE_ARMOR_VISIBILITY_GUARD_MISSING"
Check ($source.Contains('armorPanel.style.visibility = "collapse";')) `
    "FARM_ARMOR_PANEL_COLLAPSE_MISSING"
Check ($source.Contains('authoritativeArmorLabel.style.visibility = "collapse";')) `
    "FARM_ARMOR_OVERLAY_COLLAPSE_MISSING"
Check ($source.Contains('authoritativeArmorLabel.style.visibility = isArmorHiddenUnit(unitName)')) `
    "FARM_ARMOR_OVERLAY_RUNTIME_GUARD_MISSING"
Check ($source.Contains('if (!isArmorHiddenUnit(unitName)) setNativeStatLabelsVisible(armorPanel, false);')) `
    "NON_FARM_ARMOR_DISPLAY_PATH_MISSING"
Check (-not (Select-String -InputObject $source -Pattern 'building_levels|SetPhysicalArmor|armor = 0' -Quiet)) `
    "FARM_ARMOR_VALUE_MUTATION_PRESENT"

Write-Output "FARM_ARMOR_DISPLAY_CONTRACT_PASS"