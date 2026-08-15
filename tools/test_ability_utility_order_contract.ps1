$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText(
        $Path,
        [System.Text.UTF8Encoding]::new($false, $true)
    )
}

function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$contentRoot = Join-Path (Split-Path (Split-Path (Split-Path $root))) `
    "content\dota_addons\survival"
$takeover = Read-Utf8 (Join-Path $contentRoot `
    "panorama\scripts\custom_game\hud_takeover.js")
$combat = Read-Utf8 (Join-Path $contentRoot `
    "panorama\scripts\custom_game\combat_stats.js")
$heroSkills = Read-Utf8 (Join-Path $root `
    "scripts\vscripts\systems\hero_skill_system.lua")

foreach ($source in @($takeover, $combat)) {
    Check ($source.Contains('ability_survival_builder_blink: 10')) `
        "BUILDER_BLINK_TAIL_ORDER_MISSING"
    Check ($source.Contains('ability_survival_return_home: 20')) `
        "RETURN_HOME_TAIL_ORDER_MISSING"
    Check ($source.Contains('ability_survival_pickup_materials: 30')) `
        "PICKUP_FINAL_ORDER_MISSING"
    Check ($source.Contains('return standard.concat(utility)')) `
        "STANDARD_UTILITY_PARTITION_MISSING"
}

Check ($takeover.Contains('hotkeys[entry.standardHotkeyIndex]')) `
    "TAKEOVER_STANDARD_HOTKEY_INDEX_MISSING"
Check ($takeover.Contains('builderHotkeysBySlotOrder') -and `
    $takeover.Contains('builderRuntime.builder_slot_order')) `
    "TAKEOVER_BUILDER_CSV_SLOT_HOTKEY_MISSING"
Check ($combat.Contains('return !utilityHotkeys[entry.name]')) `
    "COMBAT_STANDARD_HOTKEY_FILTER_MISSING"
Check ($combat.Contains('standard[slot].ability')) `
    "COMBAT_STANDARD_HOTKEY_LOOKUP_MISSING"
Check ($combat.Contains('function builderDisplaySlotForKey(key)') -and `
    $combat.Contains('runtime.builder_slot_order')) `
    "COMBAT_BUILDER_CSV_SLOT_HOTKEY_MISSING"
Check ($heroSkills.IndexOf('state.unit:AddAbility(RETURN_HOME_ABILITY)') -lt `
    $heroSkills.IndexOf('state.unit:AddAbility(PICKUP_MATERIALS_ABILITY)')) `
    "SUMMONED_HERO_UTILITY_ORDER_INVALID"

Write-Output "ABILITY_UTILITY_ORDER_CONTRACT_PASS"