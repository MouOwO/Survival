$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root `
    "scripts\vscripts\systems\monkey_king_exclusive_service.lua"
$runtimePath = Join-Path $root `
    "scripts\vscripts\config\generated\monkey_king_exclusive_runtime.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $root))
$particleSourcePath = Join-Path $dotaRoot `
    "content\dota_addons\survival\particles\survival_monkey_king\survival_monkey_king_staff_drop.vpcf"
$particleOutputPath = Join-Path $root `
    "particles\survival_monkey_king\survival_monkey_king_staff_drop.vpcf_c"
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$service = [System.IO.File]::ReadAllText($servicePath, $strictUtf8)
$runtime = [System.IO.File]::ReadAllText($runtimePath, $strictUtf8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, $strictUtf8)
$particleSource = [System.IO.File]::ReadAllText(
    $particleSourcePath,
    $strictUtf8
)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$groundParticle =
    "particles/units/heroes/hero_monkey_king/monkey_king_strike.vpcf"
$dropParticle =
    "particles/survival_monkey_king/survival_monkey_king_staff_drop.vpcf"
Check ($service.Contains($groundParticle) -and $gameMode.Contains($groundParticle)) `
    "MONKEY_KING_BOUNDLESS_PARTICLE_OR_PRECACHE_CHANGED"
Check ($service.Contains($dropParticle) -and $gameMode.Contains($dropParticle)) `
    "MONKEY_KING_STAFF_DROP_PARTICLE_OR_PRECACHE_MISSING"
Check (Test-Path -LiteralPath $particleOutputPath) `
    "MONKEY_KING_STAFF_DROP_COMPILED_PARTICLE_MISSING"

Check ($particleSource.Contains(
    'm_model = resource:"models/props_items/monkey_king_bar01.vmdl"'
)) "MONKEY_KING_STAFF_DROP_VALVE_MODEL_MISSING"
Check ($particleSource.Contains(
    'm_hOverrideMaterial = resource:"materials/models/heroes/monkey_king/monkey_king_weapon_fx.vmat"'
)) "MONKEY_KING_STAFF_DROP_VALVE_MATERIAL_MISSING"
foreach ($operator in @(
    'C_OP_InstantaneousEmitter',
    'C_INIT_VelocityFromCP',
    'C_OP_BasicMovement',
    'C_OP_Orient2DRelToCP',
    'C_OP_RenderModels',
    'C_OP_Decay'
)) {
    Check ($particleSource.Contains($operator)) `
        ("MONKEY_KING_STAFF_DROP_OPERATOR_MISSING: " + $operator)
}
Check ($particleSource.Contains('m_nControlPoint = 2')) `
    "MONKEY_KING_STAFF_DROP_CP2_VELOCITY_MISSING"
Check ($particleSource.Contains('m_fLifetimeMin = 0.28') `
        -and $particleSource.Contains('m_fLifetimeMax = 0.28')) `
    "MONKEY_KING_STAFF_DROP_LIFETIME_CHANGED"
Check ($particleSource.Contains('m_Gravity = [ 0.0, 0.0, -23010.0 ]')) `
    "MONKEY_KING_STAFF_DROP_ACCELERATION_CHANGED"
Check (-not $particleSource.Contains('m_Children')) `
    "MONKEY_KING_STAFF_DROP_MUST_NOT_HAVE_CHILD_EFFECTS"
Check (-not [regex]::IsMatch(
    $particleSource,
    '(?i)(ground|impact|shake|damage|collision)'
)) "MONKEY_KING_STAFF_DROP_INTRODUCED_IMPACT_OR_COMBAT_EFFECT"

$visualStart = $service.IndexOf(
    "local function play_boundless_visual(attacker, origin, endpoint, direction)"
)
$visualEnd = $service.IndexOf(
    "local function destroy_particle(particle)",
    $visualStart
)
Check ($visualStart -ge 0 -and $visualEnd -gt $visualStart) `
    "MONKEY_KING_BOUNDLESS_VISUAL_HELPER_MISSING"
$visual = $service.Substring($visualStart, $visualEnd - $visualStart)
Check ($visual.Contains("GetGroundPosition(origin, attacker)")) `
    "MONKEY_KING_BOUNDLESS_ORIGIN_GROUND_SNAP_MISSING"
Check ($visual.Contains("GetGroundPosition(endpoint, attacker)")) `
    "MONKEY_KING_BOUNDLESS_ENDPOINT_GROUND_SNAP_MISSING"
Check ($visual.Contains(
    "SetParticleControlForward(particle, 0, direction)"
)) "MONKEY_KING_BOUNDLESS_CP0_FORWARD_MISSING"
Check ($visual.Contains("SetParticleControl(particle, 0, visual_origin)")) `
    "MONKEY_KING_BOUNDLESS_CP0_MISSING"
Check ($visual.Contains("SetParticleControl(particle, 1, visual_endpoint)")) `
    "MONKEY_KING_BOUNDLESS_CP1_MISSING"
Check ($visual.Contains("SetParticleControl(particle, 2, visual_endpoint)")) `
    "MONKEY_KING_BOUNDLESS_CP2_MISSING"

Check ($service.Contains("local STAFF_DROP_HEIGHT = 1000")) `
    "MONKEY_KING_STAFF_DROP_HEIGHT_CHANGED"
Check ($service.Contains("local STAFF_DROP_DURATION = 0.28")) `
    "MONKEY_KING_STAFF_DROP_DURATION_CHANGED"
Check ($service.Contains("local STAFF_DROP_INITIAL_SPEED = 350")) `
    "MONKEY_KING_STAFF_DROP_INITIAL_SPEED_CHANGED"
Check ([regex]::IsMatch(
    $service,
    '(?s)local function play_staff_drop\(attacker, origin, direction, length\).*?' +
        'center = origin \+ direction \* \(length \* 0\.5\).*?' +
        'GetGroundPosition\(center, attacker\).*?' +
        'start_position = ground_center \+ Vector\(0, 0, STAFF_DROP_HEIGHT\).*?' +
        'SetParticleControlForward\(particle, 0, direction\).*?' +
        'particle, 1, start_position \+ direction \* length.*?' +
        'Vector\(0, 0, -STAFF_DROP_INITIAL_SPEED\)'
)) "MONKEY_KING_STAFF_DROP_CONTROL_CONTRACT_MISSING"
$fallDistance = 350.0 * 0.28 + 0.5 * 23010.0 * 0.28 * 0.28
$terminalSpeed = 350.0 + 23010.0 * 0.28
Check ([math]::Abs($fallDistance - 1000.0) -lt 0.02) `
    "MONKEY_KING_STAFF_DROP_MOTION_DOES_NOT_REACH_GROUND"
Check ($terminalSpeed -gt 6700.0) `
    "MONKEY_KING_STAFF_DROP_TERMINAL_SPEED_TOO_LOW"

Check ([regex]::IsMatch(
    $service,
    '(?s)local function trigger_q\(player_id, attacker, target\).*?' +
        'local origin = attacker:GetAbsOrigin\(\).*?' +
        'local direction = normalized_direction\(.*?' +
        'local attribute_damage = all_attributes\(player_id\).*?' +
        'drop_particle = play_staff_drop\(attacker, origin, direction, length\).*?' +
        'scheduler\.after\(STAFF_DROP_DURATION, function\(\).*?' +
        'resolve_q_impact\(impact_id\)'
)) "MONKEY_KING_Q_TRIGGER_SNAPSHOT_OR_DELAY_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)local function resolve_q_impact\(impact_id\).*?' +
        'q_impacts\[impact_id\] = nil.*?' +
        'destroy_particle\(impact\.drop_particle\).*?' +
        'if not valid\(impact\.attacker\) then return false end.*?' +
        'play_boundless_visual\(.*?' +
        'line_targets\(.*?impact\.origin.*?impact\.direction.*?' +
        'impact\.length, impact\.total_width.*?' +
        'impact\.attribute_damage \+ health_damage'
)) "MONKEY_KING_Q_IMPACT_RESCAN_OR_DAMAGE_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)local function clear_q_impacts\(\).*?' +
        'scheduler\.cancel\(impact\.task\).*?' +
        'destroy_particle\(impact\.drop_particle\).*?' +
        'function M\.init\(\).*?clear_q_impacts\(\)'
)) "MONKEY_KING_Q_PENDING_IMPACT_RESET_CLEANUP_MISSING"
Check ([regex]::IsMatch(
    $service,
    '(?s)function M\.trigger_clone_q\(player_id, attacker, target\).*?' +
        'return trigger_q\(player_id, attacker, target\)'
)) "MONKEY_KING_CLONE_Q_NO_LONGER_REUSES_DELAYED_PATH"

foreach ($contract in @(
    'q_proc_chance_pct = 10',
    'q_length = 1200',
    'q_total_width = 200',
    'q_attribute_multiplier = 30',
    'q_max_health_pct = 10',
    'q_max_health_hit_limit = 3'
)) {
    Check ($runtime.Contains($contract)) `
        ("MONKEY_KING_Q_RUNTIME_CHANGED: " + $contract)
}
Check ($service.Contains("local function line_targets(")) `
    "MONKEY_KING_Q_LUA_RECTANGLE_REMOVED"
Check (-not [regex]::IsMatch(
    $service,
    'ProjectileManager\s*:\s*CreateLinearProjectile'
)) "MONKEY_KING_Q_PARTICLE_REPLACED_LUA_RECTANGLE"

Write-Host "MONKEY_KING_BOUNDLESS_VISUAL_CONTRACT_PASS"
