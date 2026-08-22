$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$definitionPath = Join-Path $root "scripts\vscripts\config\hero_passive_skill_definitions.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$dotaRoot = Split-Path -Parent `
    (Split-Path -Parent (Split-Path -Parent $root))
$contentRoot = Join-Path $dotaRoot `
    "content\dota_addons\survival"
$particleSourcePath = Join-Path $contentRoot `
    "particles\survival_earth_line\survival_earth_line_chaos_meteor.vpcf"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$definitions = [System.IO.File]::ReadAllText($definitionPath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

Check (Test-Path -LiteralPath $particleSourcePath) `
    "EARTH_LINE_CHAOS_METEOR_PARTICLE_SOURCE_MISSING"
$particleSource = [System.IO.File]::ReadAllText(
    $particleSourcePath,
    [System.Text.Encoding]::UTF8
)

$rolling = "particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf"
$falling = "particles/units/heroes/hero_invoker/invoker_chaos_meteor_fly.vpcf"
$tiny = "particles/units/heroes/hero_tiny/tiny_base_attack.vpcf"
$terminal = "particles/basic_projectile/basic_projectile_explosion.vpcf"

$rollingPattern = '(?s)earth_rock\.visual_particle\s*=\s*"' +
    [regex]::Escape($rolling) + '"'
Check ([regex]::IsMatch($service, $rollingPattern)) `
    "EARTH_LINE_GROUNDED_CHAOS_METEOR_PARTICLE_MISSING"
Check ($gameMode.Contains($rolling)) "EARTH_LINE_GROUNDED_CHAOS_METEOR_PRECACHE_MISSING"
Check (-not $service.Contains($tiny)) "EARTH_LINE_TINY_MOVING_VISUAL_REMAINS"
Check (-not $gameMode.Contains($tiny)) "EARTH_LINE_TINY_MOVING_PRECACHE_REMAINS"
Check ($service.Contains($terminal) -and $gameMode.Contains($terminal)) `
    "EARTH_LINE_TERMINAL_EXPLOSION_CHANGED"
Check ($particleSource.Contains('m_model = resource:"models/particle/meteor.vmdl"')) `
    "EARTH_LINE_VALVE_METEOR_MODEL_MISSING"
Check ($particleSource.Contains('_class = "C_INIT_VelocityFromCP"') `
        -and $particleSource.Contains('m_nControlPoint = 1')) `
    "EARTH_LINE_CHAOS_METEOR_CP1_VELOCITY_SOURCE_MISSING"
Check ($particleSource.Contains('_class = "C_OP_MovementPlaceOnGround"')) `
    "EARTH_LINE_CHAOS_METEOR_GROUND_PLACEMENT_MISSING"
Check ($particleSource.Contains('_class = "C_OP_SpinUpdate"')) `
    "EARTH_LINE_CHAOS_METEOR_ROLLING_SPIN_MISSING"
$durationPattern = '(?s)_class = "C_INIT_InitFloat"\s*' +
    'm_InputValue =\s*\{\s*' +
    'm_nType = "PF_TYPE_CONTROL_POINT_COMPONENT"\s*' +
    'm_nControlPoint = 2\s*' +
    'm_nVectorComponent = 0\s*\}\s*' +
    'm_nOutputField = 1'
Check ([regex]::IsMatch($particleSource, $durationPattern)) `
    "EARTH_LINE_CHAOS_METEOR_CP2_LIFETIME_SOURCE_MISSING"
foreach ($rollingChild in @(
    "invoker_chaos_meteor_fire.vpcf",
    "invoker_chaos_meteor_glow.vpcf",
    "invoker_chaos_meteor_fire_trail.vpcf",
    "invoker_chaos_meteor_smoke.vpcf",
    "invoker_chaos_meteor_smoke_b.vpcf",
    "invoker_chaos_meteor_burnt.vpcf"
)) {
    Check ($particleSource.Contains($rollingChild)) `
        ("EARTH_LINE_CHAOS_METEOR_ROLLING_CHILD_MISSING: " + $rollingChild)
}
Check (-not $particleSource.Contains("invoker_chaos_meteor_land_")) `
    "EARTH_LINE_CHAOS_METEOR_LANDING_IMPACT_CHILD_REMAINS"
Check (-not $particleSource.Contains("C_OP_RenderScreenShake")) `
    "EARTH_LINE_CHAOS_METEOR_SCREEN_SHAKE_REMAINS"

$runStart = $service.IndexOf('local function run_earth(context, definition)')
$runEnd = $service.IndexOf('local function meteor_destroy_particle', $runStart)
Check ($runStart -ge 0 -and $runEnd -gt $runStart) "EARTH_LINE_RUNNER_BOUNDARY_MISSING"
$runEarth = $service.Substring($runStart, $runEnd - $runStart)
Check (-not $runEarth.Contains('EffectName')) `
    "EARTH_LINE_COLLISION_PROJECTILE_MUST_BE_VISUALLY_EMPTY"
Check ($runEarth.Contains('vVelocity = direction * speed')) `
    "EARTH_LINE_AUTHORITATIVE_PROJECTILE_VELOCITY_CHANGED"
Check ($runEarth.Contains('fStartRadius = half_width') `
        -and $runEarth.Contains('fEndRadius = half_width')) `
    "EARTH_LINE_COLLISION_WIDTH_CHANGED"
Check ($runEarth.Contains('bDeleteOnHit = false')) `
    "EARTH_LINE_PENETRATION_CHANGED"
Check ($runEarth.Contains('ExtraData = { earth_rock_projectile_id = projectile_id }')) `
    "EARTH_LINE_UNIQUE_PROJECTILE_ID_MISSING"
Check ($runEarth.Contains('earth_rock.create_visual(earth_rock.projectiles[projectile_id])')) `
    "EARTH_LINE_INDEPENDENT_VISUAL_NOT_CREATED"

$createStart = $service.IndexOf('function earth_rock.create_visual(state)')
$createEnd = $service.IndexOf('function earth_rock.release(projectile_id, show_visual)', $createStart)
Check ($createStart -ge 0 -and $createEnd -gt $createStart) `
    "EARTH_LINE_VISUAL_HELPER_BOUNDARY_MISSING"
$createVisual = $service.Substring($createStart, $createEnd - $createStart)
Check ($createVisual.Contains('earth_rock.visual_particle')) `
    "EARTH_LINE_VISUAL_RESOURCE_NOT_USED"
Check ($createVisual.Contains('SetParticleControl(state.visual_particle, 0, state.origin)')) `
    "EARTH_LINE_CHAOS_METEOR_CP0_MISSING"
Check ($createVisual.Contains('SetParticleControl(state.visual_particle, 1, state.velocity)')) `
    "EARTH_LINE_CHAOS_METEOR_CP1_VELOCITY_MISSING"
Check ($createVisual.Contains('state.visual_particle, 2, Vector(state.duration, 0, 0)')) `
    "EARTH_LINE_CHAOS_METEOR_CP2_DURATION_MISSING"
Check ($createVisual.Contains('pcall(function()')) `
    "EARTH_LINE_VISUAL_FAILURE_ISOLATION_MISSING"

$destroyStart = $service.IndexOf('function earth_rock.destroy_visual(state)')
$destroyEnd = $service.IndexOf('function earth_rock.create_visual(state)', $destroyStart)
Check ($destroyStart -ge 0 -and $destroyEnd -gt $destroyStart) `
    "EARTH_LINE_DESTROY_HELPER_BOUNDARY_MISSING"
$destroyVisual = $service.Substring($destroyStart, $destroyEnd - $destroyStart)
Check ($destroyVisual.Contains('ParticleManager:DestroyParticle(particle, true)')) `
    "EARTH_LINE_MOVING_PARENT_MUST_DESTROY_IMMEDIATELY"
Check ($destroyVisual.Contains('ParticleManager:ReleaseParticleIndex(particle)')) `
    "EARTH_LINE_MOVING_PARENT_RELEASE_MISSING"
Check ($destroyVisual.Contains('state.visual_particle = nil')) `
    "EARTH_LINE_VISUAL_CLEANUP_NOT_IDEMPOTENT"

$releasePattern = '(?s)function earth_rock\.release\(projectile_id, show_visual\).*?' +
    'earth_rock\.projectiles\[projectile_id\] = nil.*?' +
    'earth_rock\.destroy_visual\(state\).*?' +
    'if show_visual then.*?' +
    'earth_rock\.explosion_visual\(state\.context, state\.destination\)'
Check ([regex]::IsMatch($service, $releasePattern)) `
    "EARTH_LINE_IDEMPOTENT_RELEASE_CONTRACT_MISSING"
Check ($service.Contains('earth_rock.clear()')) "EARTH_LINE_RESET_CLEANUP_MISSING"

$hitPattern = '(?s)function earth_rock\.projectile_hit\(ability, target, location, projectile_id\).*?' +
    'state\.hit\[target_key\] = true.*?' +
    'deal\(state\.context, target, earth_rock\.damage_multiplier\(state, target\), false\).*?' +
    'earth_rock\.first_hit_explosion\(state, copy_position\(hit_position\)\).*?' +
    'stun\(state\.context\.attacker, target, state\.stun_duration\).*?' +
    'return false\s*end'
Check ([regex]::IsMatch($service, $hitPattern)) `
    "EARTH_LINE_DAMAGE_STUN_ORDER_OR_PENETRATION_CHANGED"

Check ([regex]::IsMatch($definitions,
    'trigger_chance\s*=\s*\{\s*0\.12,\s*0\.12,\s*0\.12,\s*0\.12,\s*0\.12\s*\}')) `
    "EARTH_LINE_TRIGGER_CHANCE_CHANGED"
Check ([regex]::IsMatch($definitions,
    'damage_multiplier\s*=\s*\{\s*3\.00,\s*3\.00,\s*3\.00,\s*3\.00,\s*3\.00\s*\}')) `
    "EARTH_LINE_DAMAGE_MULTIPLIER_CHANGED"
Check ([regex]::IsMatch($definitions,
    'stunned_damage_multiplier\s*=\s*\{\s*6\.00,\s*6\.00,\s*6\.00,\s*6\.00,\s*6\.00\s*\}')) `
    "EARTH_LINE_STUNNED_DAMAGE_MULTIPLIER_CHANGED"
Check ([regex]::IsMatch($definitions,
    'move_speed\s*=\s*\{\s*500,\s*500,\s*500,\s*500,\s*500\s*\}')) `
    "EARTH_LINE_MOVE_SPEED_CHANGED"
Check ([regex]::IsMatch($definitions,
    'rock_width\s*=\s*\{\s*150,\s*250,\s*250,\s*250,\s*250\s*\}')) `
    "EARTH_LINE_WIDTH_CHANGED"
Check ([regex]::IsMatch($definitions,
    'stun_chance\s*=\s*\{\s*0,\s*0,\s*0\.30,\s*0\.30,\s*0\.30\s*\}')) `
    "EARTH_LINE_STUN_CHANCE_CHANGED"
Check ([regex]::IsMatch($definitions,
    'first_hit_explosion_radius\s*=\s*\{\s*0,\s*0,\s*0,\s*0,\s*300\s*\}')) `
    "EARTH_LINE_LEVEL_FIVE_RADIUS_CHANGED"
Check (-not $runEarth.Contains($falling)) "EARTH_LINE_MUST_NOT_USE_CHAOS_METEOR_FALLING_SEGMENT"

Write-Host "EARTH_LINE_VISUAL_CONTRACT_PASS"