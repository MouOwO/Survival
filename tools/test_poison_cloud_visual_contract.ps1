$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$definitionsPath = Join-Path $root "scripts\vscripts\config\generated\hero_skill_definitions.lua"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)
$definitions = [System.IO.File]::ReadAllText($definitionsPath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$nethertoxin = "particles/units/heroes/hero_viper/viper_nethertoxin.vpcf"

$skillPattern = '(?s)skill_id = "proto_poison_cloud".*?' +
    'ability_name = "ability_survival_poison_cloud".*?' +
    'effect_type = "passive_proc".*?' +
    'icon_name = "viper_nethertoxin"'
Check ([regex]::IsMatch($definitions, $skillPattern)) "POISON_CLOUD_THREE_CHOICE_IDENTITY_MISSING"
Check ($service.Contains('proto_poison_cloud = run_poison')) "POISON_CLOUD_RUNTIME_RUNNER_MISSING"
Check ($service.Contains('return create_poison_cloud(context, position, definition)')) "POISON_CLOUD_RUNNER_CREATION_MISSING"

$particlePattern = '(?s)local POISON_CLOUD_PARTICLE\s*=\s*"' +
    [regex]::Escape($nethertoxin) + '"'
Check ([regex]::IsMatch($service, $particlePattern)) "POISON_CLOUD_PARTICLE_NOT_VIPER_NETHERTOXIN"
Check ($gameMode.Contains($nethertoxin)) "POISON_CLOUD_NETHERTOXIN_PRECACHE_MISSING"

$createPattern = '(?s)local function create_poison_cloud\(context, position, definition\).*?' +
    'release_poison_cloud\(attacker_key\).*?' +
    'ParticleManager:CreateParticle\(\s*POISON_CLOUD_PARTICLE, PATTACH_WORLDORIGIN, context\.attacker\s*\).*?' +
    'ParticleManager:SetParticleControl\(particle, 0, position\).*?' +
    'ParticleManager:SetParticleControl\(particle, 1, Vector\(radius, 0, 0\)\).*?' +
    'particle = particle,'
Check ([regex]::IsMatch($service, $createPattern)) "POISON_CLOUD_PERSISTENT_VISUAL_CREATION_MISSING"

$releasePattern = '(?s)local function release_poison_cloud\(attacker_key\).*?' +
    'ParticleManager:DestroyParticle\(cloud\.particle, false\).*?' +
    'ParticleManager:ReleaseParticleIndex\(cloud\.particle\).*?' +
    'active_poison_clouds\[attacker_key\] = nil'
Check ([regex]::IsMatch($service, $releasePattern)) "POISON_CLOUD_VISUAL_RELEASE_MISSING"

$syncReleasePattern = '(?s)local function sync_poison_clouds\(\).*?' +
    'if not valid\(cloud\.context\.attacker\) then\s*' +
    'release_poison_cloud\(attacker_key\).*?' +
    'now \+ 0\.0001 >= cloud\.expires_at then\s*' +
    'release_poison_cloud\(attacker_key\)'
Check ([regex]::IsMatch($service, $syncReleasePattern)) "POISON_CLOUD_INVALID_OR_EXPIRED_RELEASE_MISSING"

$resetReleasePattern = '(?s)local function clear_poison_clouds\(\).*?' +
    'for _, attacker_key in ipairs\(keys\) do release_poison_cloud\(attacker_key\) end'
Check ([regex]::IsMatch($service, $resetReleasePattern)) "POISON_CLOUD_SERVICE_RESET_RELEASE_MISSING"

$createCount = ([regex]::Matches($service,
    'POISON_CLOUD_PARTICLE,\s*PATTACH_WORLDORIGIN')).Count
Check ($createCount -eq 1) "POISON_CLOUD_MUST_CREATE_ONE_PERSISTENT_PARTICLE"

Write-Host "POISON_CLOUD_VISUAL_CONTRACT_PASS"
