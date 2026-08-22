$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$puckOrb = "particles/units/heroes/hero_puck/puck_illusory_orb_main.vpcf"
$dragonSlave = "particles/units/heroes/hero_lina/lina_spell_dragon_slave.vpcf"
$oldProjectile = "particles/basic_projectile/basic_projectile.vpcf"
$explosion = "particles/basic_projectile/basic_projectile_explosion.vpcf"

Check ($service.Contains($puckOrb)) "MOVING_ICE_BALL_PUCK_ORB_PATH_MISSING"
Check ($service.Contains('local MOVING_ICE_BALL_PARTICLE =')) "MOVING_ICE_BALL_PARTICLE_CONSTANT_MISSING"
Check (-not $service.Contains($oldProjectile)) "MOVING_ICE_BALL_OLD_PROJECTILE_REMAINS"
Check ($service.Contains($explosion)) "MOVING_ICE_BALL_EXPLOSION_WAS_REMOVED"
Check ($service.Contains("local function sync_moving_ice_ball_particle(state)")) "MOVING_ICE_BALL_VISUAL_SYNC_MISSING"
Check ($service.Contains("local MOVING_ICE_BALL_VISUAL_HEIGHT = 120")) "MOVING_ICE_BALL_VISUAL_HEIGHT_MISSING"
Check ($service.Contains("state.position + Vector(0, 0, MOVING_ICE_BALL_VISUAL_HEIGHT)")) "MOVING_ICE_BALL_CP3_POSITION_MISSING"
Check (-not $service.Contains("ParticleManager:SetParticleControl(state.particle, 0, state.position)")) "MOVING_ICE_BALL_OBSOLETE_CP0_REMAINS"
Check (-not $service.Contains("state.direction * state.move_speed")) "MOVING_ICE_BALL_OBSOLETE_CP1_REMAINS"
Check ($service.Contains("local initial_direction = normalized_direction(")) "MOVING_ICE_BALL_INITIAL_HOMING_DIRECTION_MISSING"
Check ($service.Contains("sync_moving_ice_ball_particle(state)")) "MOVING_ICE_BALL_RUNTIME_SYNC_CALL_MISSING"
Check ($service.Contains("ParticleManager:DestroyParticle(state.particle, false)")) "MOVING_ICE_BALL_DESTROY_MISSING"
Check ($service.Contains("ParticleManager:ReleaseParticleIndex(state.particle)")) "MOVING_ICE_BALL_RELEASE_MISSING"
Check ($gameMode.Contains($puckOrb)) "MOVING_ICE_BALL_PUCK_ORB_PRECACHE_MISSING"
Check (-not $gameMode.Contains($oldProjectile)) "MOVING_ICE_BALL_OLD_PROJECTILE_PRECACHE_REMAINS"
Check ($gameMode.Contains($explosion)) "MOVING_ICE_BALL_EXPLOSION_PRECACHE_WAS_REMOVED"

$movingParticlePattern = '(?s)local MOVING_ICE_BALL_PARTICLE\s*=\s*"' +
    [regex]::Escape($puckOrb) + '"'
Check ([regex]::IsMatch($service, $movingParticlePattern)) "MOVING_ICE_BALL_CONSTANT_NOT_PUCK_ORB"
$movingDragonPattern = '(?s)local MOVING_ICE_BALL_PARTICLE\s*=\s*"' +
    [regex]::Escape($dragonSlave) + '"'
Check (-not [regex]::IsMatch($service, $movingDragonPattern)) "MOVING_ICE_BALL_STILL_USES_DRAGON_SLAVE"

$createCount = ([regex]::Matches($service,
    'MOVING_ICE_BALL_PARTICLE, PATTACH_WORLDORIGIN')).Count
Check ($createCount -eq 1) "MOVING_ICE_BALL_MUST_CREATE_ONE_PERSISTENT_PARTICLE"

Write-Host "MOVING_ICE_BALL_VISUAL_CONTRACT_PASS"