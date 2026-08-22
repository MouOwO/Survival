$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$definitionPath = Join-Path $root "scripts\vscripts\config\hero_passive_skill_definitions.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$definitions = [System.IO.File]::ReadAllText($definitionPath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$stormHammer = "particles/units/heroes/hero_sven/sven_spell_storm_bolt.vpcf"
$stormHammerExplosion =
    "particles/units/heroes/hero_sven/sven_storm_bolt_projectile_explosion.vpcf"
$oldProjectile = "particles/basic_projectile/basic_projectile.vpcf"

$projectileConstantPattern = '(?s)local SPIRIT_BOMB_PROJECTILE_PARTICLE\s*=\s*"' +
    [regex]::Escape($stormHammer) + '"'
$explosionConstantPattern = '(?s)local SPIRIT_BOMB_EXPLOSION_PARTICLE\s*=\s*"' +
    [regex]::Escape($stormHammerExplosion) + '"'
Check ([regex]::IsMatch($service, $projectileConstantPattern)) `
    "SPIRIT_BOMB_PROJECTILE_NOT_SVEN_STORM_HAMMER"
Check ([regex]::IsMatch($service, $explosionConstantPattern)) `
    "SPIRIT_BOMB_EXPLOSION_NOT_SVEN_STORM_HAMMER"
Check (-not [regex]::IsMatch(
    $service,
    '(?s)local SPIRIT_BOMB_PROJECTILE_PARTICLE\s*=\s*"' +
        [regex]::Escape($oldProjectile) + '"'
)) "SPIRIT_BOMB_OLD_PROJECTILE_REMAINS"
Check ($gameMode.Contains($stormHammer)) "SPIRIT_BOMB_PROJECTILE_PRECACHE_MISSING"
Check ($gameMode.Contains($stormHammerExplosion)) "SPIRIT_BOMB_EXPLOSION_PRECACHE_MISSING"

$trackingPattern = '(?s)local function run_holy\(context, definition\).*?' +
    'ProjectileManager:CreateTrackingProjectile\(\{\s*' +
    'Target = target,\s*' +
    'Source = context\.attacker,\s*' +
    'Ability = ability,\s*' +
    'EffectName = SPIRIT_BOMB_PROJECTILE_PARTICLE,\s*' +
    'iMoveSpeed = level_value\(\s*definition, "projectile_speed", context\.level\s*\),\s*' +
    'bDodgeable = false,\s*' +
    'bProvidesVision = false,\s*' +
    'ExtraData = \{ spirit_bomb_projectile_id = projectile_id \},\s*' +
    '\}\)'
Check ([regex]::IsMatch($service, $trackingPattern)) `
    "SPIRIT_BOMB_TRACKING_PROJECTILE_CONTRACT_MISSING"

$explosionPattern = '(?s)local function spirit_bomb_explosion\(state, target\).*?' +
    'ParticleManager:CreateParticle\(\s*SPIRIT_BOMB_EXPLOSION_PARTICLE,\s*' +
    'PATTACH_WORLDORIGIN,\s*state\.context\.attacker\s*\).*?' +
    'ParticleManager:SetParticleControl\(particle, 0, position\).*?' +
    'ParticleManager:SetParticleControl\(particle, 3, position\).*?' +
    'ParticleManager:ReleaseParticleIndex\(particle\).*?' +
    'enemies_touching_radius\(\s*state\.context\.attacker, position, ' +
    'state\.explosion_radius\s*\).*?' +
    'state\.damage_multiplier \* state\.explosion_damage_pct / 100'
Check ([regex]::IsMatch($service, $explosionPattern)) `
    "SPIRIT_BOMB_STORM_HAMMER_EXPLOSION_CONTRACT_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)local function spirit_bomb_explosion\(state, target\).*?' +
        'if not visual_ok then.*?' +
        'pcall\(function\(\)\s*' +
        'ParticleManager:DestroyParticle\(particle, true\)\s*end\).*?' +
        'pcall\(function\(\)\s*' +
        'ParticleManager:ReleaseParticleIndex\(particle\)\s*end\)'
)) "SPIRIT_BOMB_EXPLOSION_FAILURE_CLEANUP_MISSING"

Check ([regex]::IsMatch(
    $definitions,
    'explosion_chance\s*=\s*\{\s*0,\s*0,\s*0,\s*0,\s*0\.20\s*\}'
)) "SPIRIT_BOMB_LEVEL_FIVE_EXPLOSION_CHANCE_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'explosion_radius\s*=\s*\{\s*0,\s*0,\s*0,\s*0,\s*250\s*\}'
)) "SPIRIT_BOMB_LEVEL_FIVE_EXPLOSION_RADIUS_NOT_250"
Check ([regex]::IsMatch(
    $definitions,
    'explosion_damage_pct\s*=\s*\{\s*0,\s*0,\s*0,\s*0,\s*60\s*\}'
)) "SPIRIT_BOMB_LEVEL_FIVE_EXPLOSION_DAMAGE_CHANGED"

Write-Host "SPIRIT_BOMB_VISUAL_CONTRACT_PASS"