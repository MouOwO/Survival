$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$acornShot = "particles/units/heroes/hero_hoodwink/hoodwink_acorn_shot_tracking.vpcf"
$tinyAttack = "particles/units/heroes/hero_tiny/tiny_base_attack.vpcf"

$particlePattern = '(?s)local MAGIC_SLINGSHOT_PROJECTILE_PARTICLE\s*=\s*"' +
    [regex]::Escape($acornShot) + '"'
Check ([regex]::IsMatch($service, $particlePattern)) "MAGIC_SLINGSHOT_PARTICLE_NOT_HOODWINK_ACORN_SHOT"
Check (-not $service.Contains($tinyAttack)) "MAGIC_SLINGSHOT_TINY_ATTACK_PARTICLE_REMAINS"
Check ($gameMode.Contains($acornShot)) "MAGIC_SLINGSHOT_ACORN_SHOT_PRECACHE_MISSING"
Check (-not $gameMode.Contains($tinyAttack)) "MAGIC_SLINGSHOT_TINY_ATTACK_PRECACHE_REMAINS"

$projectilePattern = '(?s)local function run_magic_slingshot\(context, definition\).*?' +
    'ProjectileManager:CreateTrackingProjectile\(\{\s*' +
    'Target = target,\s*' +
    'Source = context\.attacker,\s*' +
    'Ability = ability,\s*' +
    'EffectName = MAGIC_SLINGSHOT_PROJECTILE_PARTICLE,\s*' +
    'iMoveSpeed = level_value\(definition, "projectile_speed", context\.level\),\s*' +
    'bDodgeable = false,\s*' +
    'bProvidesVision = false,\s*' +
    'ExtraData = \{ magic_slingshot_projectile_id = projectile_id \},\s*' +
    '\}\)'
Check ([regex]::IsMatch($service, $projectilePattern)) "MAGIC_SLINGSHOT_TRACKING_PROJECTILE_CONTRACT_MISSING"

$createCount = ([regex]::Matches($service,
    'EffectName = MAGIC_SLINGSHOT_PROJECTILE_PARTICLE')).Count
Check ($createCount -eq 1) "MAGIC_SLINGSHOT_MUST_USE_ONE_TRACKING_PARTICLE_PATH"

Write-Host "MAGIC_SLINGSHOT_VISUAL_CONTRACT_PASS"
