$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$projectile = "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate.vpcf"
$impact = "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_impact.vpcf"
$dragonSlave = "particles/units/heroes/hero_lina/lina_spell_dragon_slave.vpcf"
$linger = "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_linger.vpcf"
$calldown = "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_calldown.vpcf"

$projectilePattern = '(?s)local FLAME_SMALL_FIREBALL_PARTICLE\s*=\s*"' +
    [regex]::Escape($projectile) + '"'
$impactPattern = '(?s)local FLAME_SMALL_FIREBALL_IMPACT_PARTICLE\s*=\s*"' +
    [regex]::Escape($impact) + '"'
Check ([regex]::IsMatch($service, $projectilePattern)) "FLAME_FIREBALL_NOT_MORTIMER_KISSES"
Check ([regex]::IsMatch($service, $impactPattern)) "FLAME_IMPACT_NOT_MORTIMER_KISSES"
Check (-not $service.Contains($dragonSlave)) "FLAME_DRAGON_SLAVE_REMAINS"
Check (-not $gameMode.Contains($dragonSlave)) "FLAME_DRAGON_SLAVE_PRECACHE_REMAINS"
Check ($gameMode.Contains($projectile)) "FLAME_MORTIMER_PROJECTILE_PRECACHE_MISSING"
Check ($gameMode.Contains($impact)) "FLAME_MORTIMER_IMPACT_PRECACHE_MISSING"
Check (-not $service.Contains($linger)) "FLAME_MORTIMER_LINGER_MUST_NOT_BE_USED"
Check (-not $service.Contains($calldown)) "FLAME_MORTIMER_CALLDOWN_MUST_NOT_BE_USED"

Check ($service.Contains("local function flame_small_fireball_velocity(")) "FLAME_FIREBALL_VELOCITY_HELPER_MISSING"
Check ($service.Contains("return (landing_position - center) * (1 / duration)")) "FLAME_FIREBALL_VELOCITY_CALCULATION_MISSING"
Check ($service.Contains("ParticleManager:SetParticleControl(particle, 0, center)")) "FLAME_FIREBALL_CP0_MISSING"
Check ($service.Contains("flame_small_fireball_velocity(center, landing_position, flight_time)")) "FLAME_FIREBALL_CP1_VELOCITY_MISSING"
Check ($service.Contains("ParticleManager:SetParticleControl(particle, 3, position)")) "FLAME_IMPACT_CP3_MISSING"
Check ($service.Contains("scheduler.after(flight_time, function()")) "FLAME_SYNCHRONIZED_LANDING_TASK_MISSING"
Check ($service.Contains("local function release_flame_small_fireball_particle(")) "FLAME_PROJECTILE_CLEANUP_HELPER_MISSING"
Check ($service.Contains("release_flame_small_fireball_particle(fireball.particle, false)")) "FLAME_PROJECTILE_LANDING_CLEANUP_MISSING"
Check ($service.Contains("ParticleManager:DestroyParticle(particle, immediate == true)")) "FLAME_PROJECTILE_DESTROY_MISSING"
Check ($service.Contains("ParticleManager:ReleaseParticleIndex(particle)")) "FLAME_PROJECTILE_RELEASE_MISSING"
Check ($service.Contains("flame_small_fireball_impact_visual(context, fireball.position)")) "FLAME_MORTIMER_IMPACT_CALL_MISSING"

$projectileCreateCount = ([regex]::Matches($service,
    'FLAME_SMALL_FIREBALL_PARTICLE,\s*PATTACH_WORLDORIGIN')).Count
$impactCreateCount = ([regex]::Matches($service,
    'FLAME_SMALL_FIREBALL_IMPACT_PARTICLE,\s*PATTACH_WORLDORIGIN')).Count
Check ($projectileCreateCount -eq 1) "FLAME_PROJECTILE_MUST_HAVE_ONE_CREATION_PATH"
Check ($impactCreateCount -eq 1) "FLAME_IMPACT_MUST_HAVE_ONE_CREATION_PATH"

Write-Host "FLAME_BURST_VISUAL_CONTRACT_PASS"