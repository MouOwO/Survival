$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $root))
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$particleSourcePath = Join-Path $dotaRoot "content\dota_addons\survival\particles\survival_echo_slash\survival_echo_slash_follow.vpcf"
$particleOutputPath = Join-Path $root "particles\survival_echo_slash\survival_echo_slash_follow.vpcf_c"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)
$particleSource = [System.IO.File]::ReadAllText($particleSourcePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$kezSlash = "particles/units/heroes/hero_kez/kez_katana_echo_strike_slash.vpcf"
$kezSwoosh = "particles/units/heroes/hero_kez/kez_katana_echo_strike_swoosh.vpcf"
$kezFullEcho = "particles/units/heroes/hero_kez/kez_katana_echo_strike.vpcf"
$projectEcho = "particles/survival_echo_slash/survival_echo_slash_follow.vpcf"
$magnataurShockwave = "particles/units/heroes/hero_magnataur/magnataur_shockwave.vpcf"

$echoParticlePattern = '(?s)echo_slash\.particle\s*=\s*"' +
    [regex]::Escape($projectEcho) + '"'
Check ([regex]::IsMatch($service, $echoParticlePattern)) "ECHO_SLASH_PROJECT_PARENT_MISSING"
Check ($gameMode.Contains($projectEcho)) "ECHO_SLASH_PROJECT_PARENT_PRECACHE_MISSING"
Check (-not $service.Contains($kezFullEcho)) "ECHO_SLASH_VALVE_PARENT_MUST_NOT_BE_DRIVEN_DIRECTLY"
Check (-not $gameMode.Contains($kezFullEcho)) "ECHO_SLASH_VALVE_PARENT_MUST_NOT_BE_PRECached"
Check (-not $service.Contains($kezSlash)) "ECHO_SLASH_INTERNAL_CHILD_MUST_NOT_BE_DRIVEN_DIRECTLY"
Check (-not $gameMode.Contains($kezSlash)) "ECHO_SLASH_INTERNAL_CHILD_MUST_NOT_BE_PRECached"
Check (-not $service.Contains($kezSwoosh)) "ECHO_SLASH_SWOOSH_MUST_BE_PARENT_OWNED"
Check (Test-Path -LiteralPath $particleOutputPath) "ECHO_SLASH_COMPILED_PARTICLE_MISSING"

$completeChildren = @(
    "kez_katana_echo_strike_thickness_indicator.vpcf",
    "kez_katana_echo_strike_wind_warp.vpcf",
    "kez_katana_echo_strike_ground.vpcf",
    "kez_katana_echo_strike_streaks.vpcf",
    "kez_katana_echo_strike_movement.vpcf",
    "kez_katana_echo_strike_hero.vpcf",
    "kez_katana_echo_strike_swoosh.vpcf"
)
foreach ($child in $completeChildren) {
    Check ($particleSource.Contains($child)) ("ECHO_SLASH_COMPLETE_CHILD_MISSING: " + $child)
}
Check ($particleSource.Contains('C_OP_BasicMovement')) "ECHO_SLASH_PROJECT_CARRIER_MOVEMENT_MISSING"
Check ($particleSource.Contains('C_OP_SetChildControlPoints')) "ECHO_SLASH_CHILD_CONTROL_PROPAGATION_MISSING"
$durationPattern = '(?s)m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT".*?' +
    'm_nControlPoint = 9.*?m_nVectorComponent = 0.*?m_nOutputField = 1'
Check ([regex]::IsMatch($particleSource, $durationPattern)) "ECHO_SLASH_CP9_CARRIER_DURATION_MISSING"
Check (-not $particleSource.Contains('m_flLiteralValue = 0.5')) "ECHO_SLASH_FIXED_HALF_SECOND_CARRIER_REMAINS"

$bladeParticlePattern = '(?s)local BLADE_PULSE_PARTICLE\s*=\s*"' +
    [regex]::Escape($magnataurShockwave) + '"'
Check ([regex]::IsMatch($service, $bladeParticlePattern)) "BLADE_PULSE_MAGNATAUR_PARTICLE_CHANGED"
Check ($gameMode.Contains($magnataurShockwave)) "BLADE_PULSE_MAGNATAUR_PRECACHE_MISSING"

$projectilePattern = '(?s)function echo_slash\.run\(context, definition\).*?' +
    'ProjectileManager:CreateLinearProjectile\(\{\s*' +
    'Ability = ability,\s*' +
    'Source = context\.attacker,\s*' +
    'vSpawnOrigin = origin,\s*' +
    'vVelocity = direction \* speed,\s*' +
    'fDistance = distance,\s*' +
    'fStartRadius = half_width,\s*' +
    'fEndRadius = half_width,.*?' +
    'bDeleteOnHit = false,.*?' +
    'ExtraData = \{ echo_slash_projectile_id = projectile_id \},\s*' +
    '\}\)'
Check ([regex]::IsMatch($service, $projectilePattern)) "ECHO_SLASH_LINEAR_PROJECTILE_CONTRACT_MISSING"
Check (-not $service.Contains('EffectName = echo_slash.particle')) "ECHO_SLASH_INTERNAL_CHILD_MUST_NOT_BE_LINEAR_EFFECT"

$particleCreatePattern = '(?s)function echo_slash\.create_visual_particle\(state\).*?' +
    'ParticleManager:CreateParticle\(\s*' +
    'echo_slash\.particle, PATTACH_WORLDORIGIN, state\.context\.attacker\s*' +
    '\).*?echo_slash\.sync_visual\(state\)'
Check ([regex]::IsMatch($service, $particleCreatePattern)) "ECHO_SLASH_PARTICLE_CREATION_DRIVER_MISSING"
$visualPattern = '(?s)function echo_slash\.create_visual\(projectile_id\).*?' +
    'echo_slash\.create_visual_particle\(state\).*?' +
    'scheduler\.every\(echo_slash\.visual_interval'
Check ([regex]::IsMatch($service, $visualPattern)) "ECHO_SLASH_INDEPENDENT_VISUAL_DRIVER_MISSING"
Check (-not $service.Contains('echo_slash.visual_phase_duration')) "ECHO_SLASH_HALF_SECOND_PHASE_REMAINS"
Check (-not $service.Contains('visual_phase')) "ECHO_SLASH_EXTRA_VISUAL_PHASE_REMAINS"
$destroyVisualStart = $service.IndexOf('function echo_slash.destroy_visual_particle(state)')
$destroyVisualEnd = $service.IndexOf('function echo_slash.release_visual(state, immediate)', $destroyVisualStart)
Check ($destroyVisualStart -ge 0 -and $destroyVisualEnd -gt $destroyVisualStart) "ECHO_SLASH_DESTROY_HELPER_BOUNDARY_MISSING"
$destroyVisual = $service.Substring($destroyVisualStart, $destroyVisualEnd - $destroyVisualStart)
Check ($destroyVisual.Contains('ParticleManager:DestroyParticle(particle, true)')) "ECHO_SLASH_MOVING_PARENT_MUST_DESTROY_IMMEDIATELY"
Check (-not $destroyVisual.Contains('immediate')) "ECHO_SLASH_PARENT_DESTROY_MUST_NOT_DEPEND_ON_CALLER_FLAG"

Check ($service.Contains('echo_slash.visual_width = 200')) "ECHO_SLASH_VISUAL_WIDTH_MISSING"
Check ($service.Contains('echo_slash.visual_scale = 1.5')) "ECHO_SLASH_VISUAL_SCALE_MISSING"
$syncVisualStart = $service.IndexOf('function echo_slash.sync_visual(state)')
$syncVisualEnd = $service.IndexOf('function echo_slash.create_visual_particle(state)', $syncVisualStart)
Check ($syncVisualStart -ge 0 -and $syncVisualEnd -gt $syncVisualStart) "ECHO_SLASH_VISUAL_SYNC_BOUNDARY_MISSING"
$syncVisual = $service.Substring($syncVisualStart, $syncVisualEnd - $syncVisualStart)
Check ($syncVisual.Contains('state.origin + state.direction * (state.speed * state.duration)')) "ECHO_SLASH_FULL_PATH_ENDPOINT_MISSING"
Check ($syncVisual.Contains('ParticleManager:SetParticleControl(state.particle, 0, state.origin)')) "ECHO_SLASH_PARENT_CP0_MISSING"
Check ($syncVisual.Contains('ParticleManager:SetParticleControl(state.particle, 1, finish)')) "ECHO_SLASH_PARENT_CP1_MISSING"
Check ($syncVisual.Contains('Vector(state.speed, echo_slash.visual_width, echo_slash.visual_scale)')) "ECHO_SLASH_PARENT_CP2_MISSING"
Check ($syncVisual.Contains('state.particle, 6, Vector(-9.61916, 0, 0)')) "ECHO_SLASH_PARENT_CP6_MISSING"
Check ($syncVisual.Contains('ParticleManager:SetParticleControl(state.particle, 7, echo_slash.color)')) "ECHO_SLASH_PARENT_CP7_MISSING"
Check ($syncVisual.Contains('state.particle, 8, Vector(echo_slash.emit_rate, 0, 0)')) "ECHO_SLASH_PARENT_CP8_MISSING"
Check ($syncVisual.Contains('state.particle, 9, Vector(state.duration, 0, 0)')) "ECHO_SLASH_PARENT_CP9_MISSING"
Check (-not $syncVisual.Contains('state.half_width')) "ECHO_SLASH_COLLISION_WIDTH_MUST_NOT_DRIVE_VISUAL_ENDPOINTS"

$cleanupPattern = '(?s)function echo_slash\.release_visual\(state, immediate\).*?' +
    'scheduler\.cancel\(state\.visual_task\).*?' +
    'echo_slash\.destroy_visual_particle\(state\)'
Check ([regex]::IsMatch($service, $cleanupPattern)) "ECHO_SLASH_VISUAL_CLEANUP_MISSING"
Check ($service.Contains('echo_slash.clear()')) "ECHO_SLASH_RESET_CLEANUP_MISSING"
Check ($service.Contains('state.started_at = math.min(state.started_at, game_time() - state.duration)')) "ECHO_SLASH_TERMINAL_VISUAL_SYNC_MISSING"

$hitPattern = '(?s)function echo_slash\.projectile_hit\(ability, target, projectile_id\).*?' +
    'state\.hit\[target_key\] = true.*?' +
    'deal\(state\.context, target, state\.damage_multiplier, false\).*?' +
    'return false\s*end'
Check ([regex]::IsMatch($service, $hitPattern)) "ECHO_SLASH_PENETRATING_HIT_CONTRACT_MISSING"

Check (-not $service.Contains('kez_echo_slash')) "KEZ_NATIVE_ECHO_SLASH_ABILITY_MUST_NOT_BE_CALLED"
Check (-not $service.Contains('modifier_kez_echo_slash')) "KEZ_NATIVE_ECHO_SLASH_MODIFIER_MUST_NOT_BE_USED"

$createCount = ([regex]::Matches($service,
    'echo_slash\.particle, PATTACH_WORLDORIGIN')).Count
Check ($createCount -eq 1) "ECHO_SLASH_MUST_USE_ONE_INDEPENDENT_VISUAL_PATH"

Write-Host "ECHO_SLASH_VISUAL_CONTRACT_PASS"