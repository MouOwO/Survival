$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $root))
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$definitionsPath = Join-Path $root "scripts\vscripts\config\generated\hero_skill_definitions.lua"
$particleSourcePath = Join-Path $dotaRoot "content\dota_addons\survival\particles\survival_tornado\survival_tornado_follow.vpcf"
$particleOutputPath = Join-Path $root "particles\survival_tornado\survival_tornado_follow.vpcf_c"

$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)
$definitions = [System.IO.File]::ReadAllText($definitionsPath, [System.Text.Encoding]::UTF8)
$particleSource = [System.IO.File]::ReadAllText($particleSourcePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$projectParticle = "particles/survival_tornado/survival_tornado_follow.vpcf"
$invokerChild = "particles/units/heroes/hero_invoker/invoker_tornado_child.vpcf"
$invokerFull = "particles/units/heroes/hero_invoker/invoker_tornado.vpcf"
$completeChildren = @(
    "particles/units/heroes/hero_invoker/invoker_tornado_funnel.vpcf",
    "particles/units/heroes/hero_invoker/invoker_tornado_base.vpcf",
    "particles/units/heroes/hero_invoker/invoker_tornado_dust_trail.vpcf",
    "particles/units/heroes/hero_invoker/invoker_tornado_dust_trail_b.vpcf"
)

$skillPattern = '(?s)skill_id = "proto_void_pulse".*?' +
    'ability_name = "ability_survival_void_pulse".*?' +
    'effect_type = "passive_proc".*?' +
    'icon_name = "invoker_tornado"'
Check ([regex]::IsMatch($definitions, $skillPattern)) "TORNADO_THREE_CHOICE_IDENTITY_MISSING"
Check ($service.Contains('proto_void_pulse = run_void')) "TORNADO_RUNTIME_RUNNER_MISSING"

$particlePattern = '(?s)local TORNADO_PARTICLE\s*=\s*"' +
    [regex]::Escape($projectParticle) + '"'
Check ([regex]::IsMatch($service, $particlePattern)) "TORNADO_PROJECT_PARTICLE_MISSING"
Check ($gameMode.Contains($projectParticle)) "TORNADO_PROJECT_PARTICLE_PRECACHE_MISSING"
Check (-not $service.Contains($invokerFull)) "TORNADO_FULL_INVOKER_PARENT_MUST_NOT_BE_DRIVEN_BY_LUA"
Check (-not $gameMode.Contains($invokerFull)) "TORNADO_FULL_INVOKER_PARENT_MUST_NOT_BE_PRECached"

foreach ($child in $completeChildren) {
    Check ($particleSource.Contains('m_ChildRef = resource:"' + $child + '"')) `
        ("TORNADO_COMPLETE_CHILD_MISSING: " + $child)
}
Check (-not $particleSource.Contains($invokerChild)) "TORNADO_DEBRIS_ONLY_CHILD_REMAINS"
Check (-not $particleSource.Contains($invokerFull)) "TORNADO_SOURCE_MUST_NOT_REFERENCE_FULL_INVOKER_PARENT"
Check (-not $particleSource.Contains('C_OP_BasicMovement')) "TORNADO_SOURCE_MUST_NOT_MOVE_INTERNALLY"
Check (-not $particleSource.Contains('m_Operators')) "TORNADO_SOURCE_MUST_BE_LUA_POSITIONED"
Check (Test-Path -LiteralPath $particleOutputPath) "TORNADO_COMPILED_PARTICLE_MISSING"

$smallCreatePattern = '(?s)local function tornado_spawn_small\(parent, target\).*?' +
    'ParticleManager:CreateParticle\(\s*' +
    'TORNADO_PARTICLE, PATTACH_WORLDORIGIN, state\.context\.attacker\s*' +
    '\).*?' +
    'ParticleManager:SetParticleControl\(state\.particle, 0, state\.position\).*?' +
    'ParticleManager:SetParticleControl\(state\.particle, 3, state\.position\)'
Check ([regex]::IsMatch($service, $smallCreatePattern)) "TORNADO_SMALL_VISUAL_CREATION_MISSING"

$mainCreatePattern = '(?s)local function run_void\(context, definition\).*?' +
    'ParticleManager:CreateParticle\(\s*' +
    'TORNADO_PARTICLE, PATTACH_WORLDORIGIN, context\.attacker\s*' +
    '\).*?' +
    'ParticleManager:SetParticleControl\(state\.particle, 0, state\.position\).*?' +
    'ParticleManager:SetParticleControl\(state\.particle, 3, state\.position\)'
Check ([regex]::IsMatch($service, $mainCreatePattern)) "TORNADO_MAIN_VISUAL_CREATION_MISSING"

$syncPattern = '(?s)local function sync_tornadoes\(\).*?' +
    'if state\.particle then\s*' +
    'ParticleManager:SetParticleControl\(state\.particle, 0, state\.position\).*?' +
    'ParticleManager:SetParticleControl\(state\.particle, 3, state\.position\)'
Check ([regex]::IsMatch($service, $syncPattern)) "TORNADO_LUA_CP0_SYNC_MISSING"
Check ($service.Contains('local TORNADO_THINK_INTERVAL = 0.05')) "TORNADO_VISUAL_SYNC_INTERVAL_CHANGED"
$tornadoStart = $service.IndexOf('local function tornado_spawn_small(parent, target)')
$tornadoEnd = $service.IndexOf('local runners = {', $tornadoStart)
Check ($tornadoStart -ge 0 -and $tornadoEnd -gt $tornadoStart) "TORNADO_RUNTIME_BOUNDARY_MISSING"
$tornadoRuntime = $service.Substring($tornadoStart, $tornadoEnd - $tornadoStart)
Check (-not $tornadoRuntime.Contains('SetParticleControl(state.particle, 1,')) "TORNADO_INTERNAL_VELOCITY_CP_MUST_NOT_RETURN"

$releasePattern = '(?s)local function tornado_release\(state\).*?' +
    'ParticleManager:DestroyParticle\(state\.particle, false\).*?' +
    'ParticleManager:ReleaseParticleIndex\(state\.particle\).*?' +
    'active_tornadoes\[state\.id\] = nil'
Check ([regex]::IsMatch($service, $releasePattern)) "TORNADO_VISUAL_RELEASE_MISSING"
Check ($service.Contains('for id, state in pairs(active_tornadoes) do tornado_release(state) end')) "TORNADO_RESET_VISUAL_RELEASE_MISSING"

$createCount = ([regex]::Matches($service,
    'TORNADO_PARTICLE,\s*PATTACH_WORLDORIGIN')).Count
Check ($createCount -eq 2) "TORNADO_MAIN_AND_SMALL_MUST_SHARE_PROJECT_PARTICLE"

Write-Host "TORNADO_VISUAL_CONTRACT_PASS"