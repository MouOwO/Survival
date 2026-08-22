$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$magnataurShockwave = "particles/units/heroes/hero_magnataur/magnataur_shockwave.vpcf"
$vengefulWave = "particles/econ/items/vengeful/vengeful_arcana/vengeful_arcana_wave_of_terror_v2.vpcf"

$particlePattern = '(?s)local BLADE_PULSE_PARTICLE\s*=\s*"' +
    [regex]::Escape($magnataurShockwave) + '"'
Check ([regex]::IsMatch($service, $particlePattern)) "BLADE_PULSE_PARTICLE_NOT_MAGNATAUR_SHOCKWAVE"
Check (-not $service.Contains($vengefulWave)) "BLADE_PULSE_VENGEFUL_WAVE_REMAINS"
Check ($gameMode.Contains($magnataurShockwave)) "BLADE_PULSE_MAGNATAUR_SHOCKWAVE_PRECACHE_MISSING"
Check (-not $gameMode.Contains($vengefulWave)) "BLADE_PULSE_VENGEFUL_WAVE_PRECACHE_REMAINS"

$projectilePattern = '(?s)local function run_blade\(context, definition\).*?' +
    'ProjectileManager:CreateLinearProjectile\(\{\s*' +
    'Ability = ability,\s*' +
    'EffectName = BLADE_PULSE_PARTICLE,\s*' +
    'Source = context\.attacker,\s*' +
    'vSpawnOrigin = origin,\s*' +
    'vVelocity = direction \* speed,\s*' +
    'fDistance = distance,\s*' +
    'fStartRadius = half_width,\s*' +
    'fEndRadius = half_width,.*?' +
    'bDeleteOnHit = false,.*?' +
    'ExtraData = \{ blade_pulse_projectile_id = projectile_id \},\s*' +
    '\}\)'
Check ([regex]::IsMatch($service, $projectilePattern)) "BLADE_PULSE_LINEAR_PROJECTILE_CONTRACT_MISSING"

$hitPattern = '(?s)local function blade_pulse_projectile_hit\(ability, target, projectile_id\).*?' +
    'state\.hit\[target_key\] = true.*?' +
    'deal\(state\.context, target, multiplier, false\).*?' +
    'return false\s*end'
Check ([regex]::IsMatch($service, $hitPattern)) "BLADE_PULSE_PENETRATING_HIT_CONTRACT_MISSING"

$effectCount = ([regex]::Matches($service,
    'EffectName = BLADE_PULSE_PARTICLE')).Count
Check ($effectCount -eq 1) "BLADE_PULSE_MUST_USE_ONE_LINEAR_PARTICLE_PATH"

Write-Host "BLADE_PULSE_VISUAL_CONTRACT_PASS"