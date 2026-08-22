$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root "scripts/vscripts/addon_game_mode.lua"
$source = [System.IO.File]::ReadAllText($path)

function Assert-Contains([string]$Pattern, [string]$Message) {
    if ($source -notmatch $Pattern) {
        throw $Message
    }
}

Assert-Contains `
    'local tower_magic_supreme_system = require\("systems/tower_magic_supreme_system"\)' `
    "tower_magic_supreme_system must be required before precache"
Assert-Contains `
    'tower_magic_supreme_system\.precache\(context\)' `
    "tower_magic_supreme_system precache call is missing"
Assert-Contains `
    'tower_magic_supreme_system\.init\(\)' `
    "tower_magic_supreme_system init call is missing"
Assert-Contains `
    '"building_main_city"' `
    "Main City must remain in the synchronous unit precache list"

$synchronousHeroUnits = @(
    "npc_dota_hero_doom_bringer", "npc_dota_hero_nevermore",
    "npc_dota_hero_axe", "npc_dota_hero_drow_ranger",
    "npc_dota_hero_monkey_king", "npc_dota_hero_sven"
)
$unitList = [regex]::Match(
    $source,
    'local units = \{(?<body>[\s\S]*?)\n    \}'
).Groups['body'].Value
foreach ($unitName in $synchronousHeroUnits) {
    if ($unitList -match [regex]::Escape('"' + $unitName + '"')) {
        throw "$unitName must use the gradual hero_permanent preload"
    }
}
Assert-Contains `
    'require\("systems/hero_asset_preload_service"\)\.init\(\)' `
    "gradual hero preload service is not initialized"

Write-Output "ADDON_PRECACHE_CONTRACT_PASS"