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

$fly = "particles/units/heroes/hero_invoker/invoker_chaos_meteor_fly.vpcf"
$impact = "particles/units/heroes/hero_warlock/warlock_rain_of_chaos_explosion.vpcf"
$oldImpact = "particles/units/heroes/hero_invoker/invoker_chaos_meteor.vpcf"
$oldFall = "particles/basic_projectile/basic_projectile.vpcf"
$lava = "particles/units/heroes/hero_viper/viper_nethertoxin.vpcf"

$fallPattern = '(?s)local METEOR_FALL_PARTICLE\s*=\s*"' +
    [regex]::Escape($fly) + '"'
$impactPattern = '(?s)local METEOR_EXPLOSION_PARTICLE\s*=\s*"' +
    [regex]::Escape($impact) + '"'
$oldFallPattern = '(?s)local METEOR_FALL_PARTICLE\s*=\s*"' +
    [regex]::Escape($oldFall) + '"'
Check ([regex]::IsMatch($service, $fallPattern)) `
    "METEOR_FALL_PARTICLE_NOT_INVOKER_CHAOS_METEOR_FLY"
Check ([regex]::IsMatch($service, $impactPattern)) `
    "METEOR_IMPACT_PARTICLE_NOT_WARLOCK_RAIN_OF_CHAOS_EXPLOSION"
Check (-not [regex]::IsMatch($service, $oldFallPattern)) `
    "METEOR_OLD_BASIC_FALL_PARTICLE_REMAINS"
Check (-not $service.Contains($oldImpact)) `
    "METEOR_INVOKER_GROUND_PARTICLE_REMAINS_IN_SERVICE"
Check ($service.Contains($lava)) "METEOR_LAVA_PARTICLE_WAS_REMOVED"
Check ($gameMode.Contains($fly)) "METEOR_FALL_PRECACHE_MISSING"
Check ($gameMode.Contains($impact)) "METEOR_IMPACT_PRECACHE_MISSING"
Check (-not $gameMode.Contains($oldImpact)) `
    "METEOR_INVOKER_GROUND_PARTICLE_PRECACHE_REMAINS"
Check ($gameMode.Contains($lava)) "METEOR_LAVA_PRECACHE_WAS_REMOVED"

Check ($service.Contains("local METEOR_FLY_PARTICLE_TRAVEL_TIME = 1.3")) `
    "METEOR_VALVE_FLY_TRAVEL_TIME_MISSING"
Check ([regex]::IsMatch(
    $service,
    'local meteor_explosion_visuals = \{\s*' +
        'active = \{\}, cast_sequence = 0, sequence = 0, duration = 3\.1,\s*\}'
)) `
    "METEOR_WARLOCK_EXPLOSION_DURATION_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)local function meteor_create_fall_particle\(cast\).*?' +
        'start_position\.z = start_position\.z \+ METEOR_FALL_HEIGHT.*?' +
        'visual_end\.z = start_position\.z - METEOR_FALL_HEIGHT\s*' +
        '\* METEOR_FLY_PARTICLE_TRAVEL_TIME / cast\.fall_duration.*?' +
        'METEOR_FALL_PARTICLE, start_position, cast\.context\.attacker.*?' +
        'SetParticleControl\(particle, 1, visual_end\).*?' +
        'particle, 2, Vector\(cast\.fall_duration, 0, 0\)'
)) "METEOR_CHAOS_FLY_CONTROL_POINT_CONTRACT_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)local function meteor_explosion_visual\(cast\).*?' +
        'METEOR_EXPLOSION_PARTICLE, cast\.position, cast\.context\.attacker.*?' +
        'meteor_explosion_visuals\.sequence = meteor_explosion_visuals\.sequence \+ 1.*?' +
        'meteor_explosion_visuals\.active\[visual_id\] = visual.*?' +
        'scheduler\.after\(\s*meteor_explosion_visuals\.duration,.*?' +
        'meteor_explosion_visuals\.release\(visual_id\).*?' +
        '"hero_meteor_explosion_" .. tostring\(visual_id\)'
)) "METEOR_WARLOCK_EXPLOSION_REGISTRATION_CONTRACT_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)meteor_explosion_visuals\.release = function\(visual_id, immediate\).*?' +
        'local visual = meteor_explosion_visuals\.active\[visual_id\].*?' +
        'if not visual then return end.*?' +
        'meteor_explosion_visuals\.active\[visual_id\] = nil.*?' +
        'scheduler\.cancel\(visual\.task\).*?' +
        'meteor_destroy_particle\(visual\.particle, immediate == true\)'
)) "METEOR_WARLOCK_EXPLOSION_IDEMPOTENT_CLEANUP_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)local function clear_meteors\(\).*?' +
        'for visual_id, _ in pairs\(meteor_explosion_visuals\.active\).*?' +
        'meteor_explosion_visuals\.release\(visual_id, true\)'
)) "METEOR_WARLOCK_EXPLOSION_CLEAR_ALL_MISSING"
Check (-not [regex]::IsMatch(
    $service,
    '(?i)CreateUnitByName\s*\([^\r\n]*(warlock|golem|infernal)'
)) "METEOR_WARLOCK_EXPLOSION_SUMMONS_A_UNIT"
Check (-not [regex]::IsMatch(
    $service,
    '(?s)if meteor\.fall_started and not meteor\.landed then.*?' +
        'SetParticleControl\(\s*meteor\.fall_particle, 0'
)) "METEOR_OBSOLETE_LUA_CP0_FALL_SYNC_REMAINS"
Check ($service.Contains("meteor_destroy_particle(meteor.fall_particle, true)")) `
    "METEOR_FLY_IMMEDIATE_LANDING_CLEANUP_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)local function meteor_destroy_particle\(particle, immediate\).*?' +
        'pcall\(function\(\).*?DestroyParticle.*?' +
        'pcall\(function\(\).*?ReleaseParticleIndex'
)) "METEOR_PARTICLE_FAILURE_CLEANUP_MISSING"

Check ([regex]::IsMatch(
    $definitions,
    'trigger_chance\s*=\s*\{\s*0\.12,\s*0\.12,\s*0\.12,\s*0\.12,\s*0\.12\s*\}'
)) "METEOR_TRIGGER_CHANCE_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'damage_multiplier\s*=\s*\{\s*3\.00,\s*3\.00,\s*3\.00,\s*3\.00,\s*3\.00\s*\}'
)) "METEOR_DAMAGE_MULTIPLIER_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'radius\s*=\s*\{\s*500,\s*500,\s*500,\s*500,\s*500\s*\}'
)) "METEOR_RADIUS_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'fall_duration\s*=\s*\{\s*0\.8,\s*0\.8,\s*0\.8,\s*0\.8,\s*0\.8\s*\}'
)) "METEOR_FALL_DURATION_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'lava_duration\s*=\s*\{\s*0,\s*3\.0,\s*3\.0,\s*3\.0,\s*3\.0\s*\}'
)) "METEOR_LAVA_DURATION_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'lava_move_slow_pct\s*=\s*\{\s*0,\s*0,\s*30,\s*30,\s*30\s*\}'
)) "METEOR_LAVA_SLOW_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'meteor_count\s*=\s*\{\s*1,\s*1,\s*1,\s*1,\s*2\s*\}'
)) "METEOR_COUNT_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'second_meteor_delay\s*=\s*\{\s*0,\s*0,\s*0,\s*0,\s*0\.5\s*\}'
)) "METEOR_SECOND_DELAY_CHANGED"
Check ([regex]::IsMatch(
    $definitions,
    'second_meteor_damage_pct\s*=\s*\{\s*0,\s*0,\s*0,\s*0,\s*80\s*\}'
)) "METEOR_SECOND_DAMAGE_CHANGED"

Write-Host "METEOR_VISUAL_CONTRACT_PASS"