$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$definitionPath = Join-Path $root "scripts\vscripts\config\hero_passive_skill_definitions.lua"
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$service = [System.IO.File]::ReadAllText($servicePath, $strictUtf8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, $strictUtf8)
$definitions = [System.IO.File]::ReadAllText($definitionPath, $strictUtf8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$mysticFlare =
    "particles/units/heroes/hero_skywrath_mage/skywrath_mage_mystic_flare.vpcf"
$mysticFlareAmbient =
    "particles/units/heroes/hero_skywrath_mage/skywrath_mage_mystic_flare_ambient.vpcf"
$oldExplosion = "particles/basic_explosion/basic_explosion.vpcf"

$particlePattern = '(?s)local ARCANE_MYSTIC_FLARE_PARTICLE\s*=\s*"' +
    [regex]::Escape($mysticFlare) + '"'
Check ([regex]::IsMatch($service, $particlePattern)) `
    "ARCANE_BARRAGE_MYSTIC_FLARE_PARTICLE_MISSING"
Check ($gameMode.Contains($mysticFlare)) `
    "ARCANE_BARRAGE_MYSTIC_FLARE_PRECACHE_MISSING"
Check (-not $service.Contains($mysticFlareAmbient)) `
    "ARCANE_BARRAGE_AMBIENT_RANDOM_PARENT_MUST_NOT_BE_USED"
Check (-not $gameMode.Contains($mysticFlareAmbient)) `
    "ARCANE_BARRAGE_AMBIENT_RANDOM_PARENT_MUST_NOT_BE_PRECACHED"

$impactPattern = '(?s)local function impact\(landing_position\).*?' +
    'ParticleManager:CreateParticle\(\s*' +
    'ARCANE_MYSTIC_FLARE_PARTICLE,\s*' +
    'PATTACH_WORLDORIGIN,\s*context\.attacker\s*' +
    '\).*?' +
    'ParticleManager:SetParticleControl\(flare, 0, landing_position\).*?' +
    'ParticleManager:ReleaseParticleIndex\(flare\).*?' +
    'enemies_touching_radius\(\s*' +
    'context\.attacker,\s*landing_position,\s*explosion_radius\s*' +
    '\)'
Check ([regex]::IsMatch($service, $impactPattern)) `
    "ARCANE_BARRAGE_MYSTIC_FLARE_IMPACT_CONTRACT_MISSING"

$runStart = $service.IndexOf('local function run_arcane(context, definition)')
$runEnd = $service.IndexOf('local function create_magic_slingshot_rubble', $runStart)
Check ($runStart -ge 0 -and $runEnd -gt $runStart) `
    "ARCANE_BARRAGE_RUNTIME_BOUNDARY_MISSING"
$arcaneRuntime = $service.Substring($runStart, $runEnd - $runStart)
Check (-not $arcaneRuntime.Contains($oldExplosion)) `
    "ARCANE_BARRAGE_OLD_EXPLOSION_REMAINS"
Check (-not $arcaneRuntime.Contains('SetParticleControl(flare, 1,')) `
    "ARCANE_BARRAGE_OLD_EXPLOSION_RADIUS_CONTROL_REMAINS"
Check ($arcaneRuntime.Contains('local total_missiles = missile_count * barrage_count')) `
    "ARCANE_BARRAGE_MISSILE_COUNT_CONTRACT_CHANGED"
Check ($arcaneRuntime.Contains('scheduler.after(impacts[1].delay, run_next_impact)')) `
    "ARCANE_BARRAGE_SEQUENTIAL_SCHEDULER_CHANGED"

$skillStart = $definitions.IndexOf('skill_id = "proto_arcane_barrage"')
$skillEnd = $definitions.IndexOf('skill_id = "proto_magic_slingshot"', $skillStart)
Check ($skillStart -ge 0 -and $skillEnd -gt $skillStart) `
    "ARCANE_BARRAGE_DEFINITION_BOUNDARY_MISSING"
$skill = $definitions.Substring($skillStart, $skillEnd - $skillStart)
Check ([regex]::IsMatch(
    $skill,
    'missile_count\s*=\s*\{\s*5,\s*5,\s*7,\s*7,\s*7\s*\}'
)) "ARCANE_BARRAGE_MISSILE_COUNTS_CHANGED"
Check ([regex]::IsMatch(
    $skill,
    'barrage_count\s*=\s*\{\s*1,\s*1,\s*1,\s*1,\s*3\s*\}'
)) "ARCANE_BARRAGE_BARRAGE_COUNTS_CHANGED"
Check ([regex]::IsMatch(
    $skill,
    'explosion_radius\s*=\s*\{\s*150,\s*150,\s*150,\s*150,\s*150\s*\}'
)) "ARCANE_BARRAGE_EXPLOSION_RADIUS_CHANGED"

Write-Host "ARCANE_BARRAGE_VISUAL_CONTRACT_PASS"