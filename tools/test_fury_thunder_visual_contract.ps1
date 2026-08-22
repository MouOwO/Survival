$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $root "scripts\vscripts\systems\hero_passive_skill_service.lua"
$gameModePath = Join-Path $root "scripts\vscripts\addon_game_mode.lua"
$service = [System.IO.File]::ReadAllText($servicePath, [System.Text.Encoding]::UTF8)
$gameMode = [System.IO.File]::ReadAllText($gameModePath, [System.Text.Encoding]::UTF8)

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

$leshracLightning = "particles/units/heroes/hero_leshrac/leshrac_lightning_bolt.vpcf"
$zuusLightning = "particles/units/heroes/hero_zuus/zuus_lightning_bolt.vpcf"

$particlePattern = '(?s)local FURY_THUNDER_PARTICLE\s*=\s*"' +
    [regex]::Escape($leshracLightning) + '"'
Check ([regex]::IsMatch($service, $particlePattern)) "FURY_THUNDER_PARTICLE_NOT_LESHRAC_LIGHTNING"
Check (-not $service.Contains($zuusLightning)) "FURY_THUNDER_ZUUS_PARTICLE_REMAINS"
Check ($service.Contains("FURY_THUNDER_PARTICLE,")) "FURY_THUNDER_PARTICLE_NOT_USED"
Check ($service.Contains("PATTACH_WORLDORIGIN, context.attacker")) "FURY_THUNDER_WORLD_ATTACHMENT_MISSING"
Check ($service.Contains("position + Vector(0, 0, 900)")) "FURY_THUNDER_SOURCE_CONTROL_MISSING"
Check ($service.Contains("ParticleManager:SetParticleControl(particle, 1, position)")) "FURY_THUNDER_TARGET_CONTROL_MISSING"
Check ($service.Contains("ParticleManager:ReleaseParticleIndex(particle)")) "FURY_THUNDER_PARTICLE_RELEASE_MISSING"
Check ($gameMode.Contains($leshracLightning)) "FURY_THUNDER_LESHRAC_PRECACHE_MISSING"

$createCount = ([regex]::Matches($service,
    'FURY_THUNDER_PARTICLE,\s*PATTACH_WORLDORIGIN')).Count
Check ($createCount -eq 1) "FURY_THUNDER_MUST_USE_ONE_STRIKE_PARTICLE_PATH"

Write-Host "FURY_THUNDER_VISUAL_CONTRACT_PASS"