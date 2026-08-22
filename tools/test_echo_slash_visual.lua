package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

local vector_methods = {}
local vector_mt = {
    __index = vector_methods,
    __add = function(left, right)
        return Vector(left.x + right.x, left.y + right.y, left.z + right.z)
    end,
    __sub = function(left, right)
        return Vector(left.x - right.x, left.y - right.y, left.z - right.z)
    end,
    __mul = function(left, right)
        if type(left) == "number" then left, right = right, left end
        return Vector(left.x * right, left.y * right, left.z * right)
    end,
}

function vector_methods:Length2D()
    return math.sqrt(self.x * self.x + self.y * self.y)
end

function vector_methods:Normalized()
    local length = self:Length2D()
    if length <= 0.000001 then return Vector(0, 0, 0) end
    return Vector(self.x / length, self.y / length, self.z / length)
end

Vector = function(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vector_mt)
end

PATTACH_WORLDORIGIN = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
DOTA_UNIT_TARGET_HERO = 4
DOTA_UNIT_TARGET_BASIC = 8
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 16
FIND_CLOSEST = 32
FIND_ANY_ORDER = 64
DAMAGE_TYPE_PURE = 128

local now = 10
GameRules = {
    GetGameTime = function() return now end,
}

local repeat_tasks = {}
local cancelled_tasks = {}
local delayed_tasks = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, task_id)
        delayed_tasks[#delayed_tasks + 1] = {
            delay = delay,
            callback = callback,
            task_id = task_id,
        }
        return task_id or ("echo_slash_after_" .. tostring(#delayed_tasks))
    end,
    every = function(interval, callback, task_id)
        repeat_tasks[task_id] = {
            interval = interval,
            callback = callback,
        }
        return task_id
    end,
    cancel = function(task_id)
        cancelled_tasks[task_id] = true
    end,
}

local particles = {}
local linear_projectiles = {}
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        local id = #particles + 1
        particles[id] = {
            path = path,
            attach = attach,
            owner = owner,
            controls = {},
            destroy_count = 0,
            release_count = 0,
        }
        return id
    end,
    SetParticleControl = function(_, id, control_point, value)
        particles[id].controls[control_point] = Vector(value.x, value.y, value.z)
    end,
    DestroyParticle = function(_, id, immediate)
        particles[id].destroy_count = particles[id].destroy_count + 1
        particles[id].destroy_immediate = immediate == true
    end,
    ReleaseParticleIndex = function(_, id)
        particles[id].release_count = particles[id].release_count + 1
    end,
}
ProjectileManager = {
    CreateLinearProjectile = function(_, info)
        linear_projectiles[#linear_projectiles + 1] = info
        return #linear_projectiles
    end,
}

local damage_requests = {}
package.loaded["core/event_bus"] = {
    emit = function() end,
    request = function(_, payload)
        damage_requests[#damage_requests + 1] = payload
        return { damage = payload.base_damage }
    end,
    subscribe = function() return {} end,
}

local ability = { IsNull = function() return false end }
local attacker = {
    IsNull = function() return false end,
    IsAlive = function() return true end,
    GetAbsOrigin = function() return Vector(100, 200, 30) end,
    GetTeamNumber = function() return 2 end,
    Script_GetAttackRange = function() return 500 end,
    FindAbilityByName = function() return ability end,
}

local target = {
    IsNull = function() return false end,
    IsAlive = function() return true end,
    entindex = function() return 701 end,
    GetTeamNumber = function() return 3 end,
    FindAllModifiersByName = function() return {} end,
}

RandomFloat = function(minimum, maximum)
    return (minimum + maximum) * 0.5
end

package.loaded["systems/hero_passive_skill_service"] = nil
local service = require("systems/hero_passive_skill_service")
local projectiles = service._test.echo_slash_projectiles()

local function state(started_at)
    return {
        context = { attacker = attacker },
        origin = Vector(100, 200, 30),
        direction = Vector(1, 0, 0),
        speed = 500,
        duration = 1,
        half_width = 137,
        started_at = started_at,
        hit = {},
    }
end

local function assert_vector(actual, x, y, z, message)
    assert(actual and math.abs(actual.x - x) < 0.000001
            and math.abs(actual.y - y) < 0.000001
            and math.abs(actual.z - z) < 0.000001,
        message .. ": got " .. tostring(actual and actual.x) .. ","
            .. tostring(actual and actual.y) .. ","
            .. tostring(actual and actual.z))
end

projectiles[91] = state(now)
service._test.echo_slash_create_visual(91)

assert(#particles == 1, "echo slash did not create exactly one explicit visual")
local visual = particles[1]
assert(visual.path ==
        "particles/survival_echo_slash/survival_echo_slash_follow.vpcf",
    "echo slash did not use the project single-carrier parent")
assert(visual.attach == PATTACH_WORLDORIGIN and visual.owner == attacker,
    "echo slash visual did not use the attacker world attachment")
assert_vector(visual.controls[0], 100, 200, 30,
    "echo slash CP0 did not start at the cast origin")
assert_vector(visual.controls[1], 600, 200, 30,
    "echo slash CP1 did not end at the attack-range destination")
assert_vector(visual.controls[2], 500, 200, 1.5,
    "echo slash CP2 speed and width changed")
assert_vector(visual.controls[6], -9.61916, 0, 0,
    "echo slash CP6 changed")
assert_vector(visual.controls[7], 0.231373, 0.407843, 0.607843,
    "echo slash CP7 color changed")
assert_vector(visual.controls[8], 200, 0, 0,
    "echo slash CP8 emission rate changed")
assert_vector(visual.controls[9], 1, 0, 0,
    "echo slash CP9 did not receive the authoritative duration")

local visual_task = repeat_tasks.echo_slash_visual_91
assert(visual_task and visual_task.interval == 0.05,
    "echo slash did not schedule its 0.05-second visual synchronization")
now = 10.5
assert(visual_task.callback() == true,
    "echo slash visual synchronization stopped before its duration")
assert(visual.destroy_count == 0 and visual.release_count == 0,
    "echo slash single visual was replaced before its duration")
assert(#particles == 1,
    "echo slash created an extra visual phase after the midpoint")

now = 11
assert(visual_task.callback() == false,
    "echo slash visual synchronization did not stop at its duration")
assert_vector(visual.controls[0], 100, 200, 30,
    "echo slash CP0 changed at the attack-range endpoint")
assert_vector(visual.controls[1], 600, 200, 30,
    "echo slash CP1 did not remain at the attack-range endpoint")
assert_vector(visual.controls[2], 500, 200, 1.5,
    "echo slash terminal CP2 speed and width changed")
assert_vector(visual.controls[9], 1, 0, 0,
    "echo slash terminal CP9 duration changed")
assert(visual.destroy_count == 1 and visual.release_count == 1,
    "echo slash duration cleanup did not destroy and release exactly once")
assert(visual.destroy_immediate,
    "normal echo slash completion did not immediately stop the moving parent")
assert(cancelled_tasks.echo_slash_visual_91,
    "echo slash duration cleanup did not cancel its visual task")
assert(projectiles[91] and projectiles[91].particle == nil,
    "visual completion incorrectly removed collision state or retained particle")

service._test.echo_slash_release(91, false)
assert(projectiles[91] == nil,
    "echo slash collision release left projectile state registered")
assert(visual.destroy_count == 1 and visual.release_count == 1,
    "late collision release repeated single-carrier cleanup")

now = 20
projectiles[92] = state(now)
service._test.echo_slash_create_visual(92)
local reset_visual = particles[2]
service._test.echo_slash_clear()
assert(projectiles[92] == nil,
    "echo slash reset cleanup left projectile state registered")
assert(reset_visual.destroy_count == 1 and reset_visual.release_count == 1
        and reset_visual.destroy_immediate,
    "echo slash reset cleanup was not immediate and idempotent")

local original_set_control = ParticleManager.SetParticleControl
ParticleManager.SetParticleControl = function()
    error("simulated echo slash control point failure")
end
projectiles[93] = state(now)
local visual_ok = pcall(function()
    service._test.echo_slash_create_visual(93)
end)
ParticleManager.SetParticleControl = original_set_control

assert(visual_ok, "echo slash visual failure escaped into collision execution")
local failed_visual = particles[3]
assert(projectiles[93] and projectiles[93].particle == nil,
    "echo slash visual failure removed collision state or retained particle")
assert(failed_visual.destroy_count == 1 and failed_visual.release_count == 1
        and failed_visual.destroy_immediate,
    "echo slash visual failure did not clean its partial particle")
service._test.echo_slash_release(93, true)

for key, _ in pairs(projectiles) do projectiles[key] = nil end
delayed_tasks = {}
now = 30
local combat_context = {
    player_id = 0,
    attacker = attacker,
    target = target,
    target_position = Vector(600, 200, 30),
    attack_id = "echo_slash_combat_test",
    skill_id = "proto_echo_slash",
    level = 5,
    attributes = { all_attributes = 100 },
}
local combat_definition = {
    damage_multiplier = { 1, 1, 1, 1, 1 },
    slash_width = { 200, 200, 200, 200, 200 },
    slash_count = { 1, 2, 3, 3, 4 },
    slash_interval = { 0, 0.1, 0.1, 0.1, 0.1 },
    slash_duration = { 1, 1, 1, 1, 1 },
    random_damage_min_pct = { 0, 0, 0, 0, 5 },
    random_damage_max_pct = { 0, 0, 0, 0, 20 },
}

assert(service._test.runners.proto_echo_slash(
        combat_context, combat_definition) == true,
    "echo slash combat runner did not launch")
assert(#linear_projectiles == 1 and #delayed_tasks == 2,
    "echo slash first wave did not schedule one cleanup and one following wave")
for wave = 2, 4 do
    now = 30 + (wave - 1) * 0.1
    local following_task = delayed_tasks[(wave - 1) * 2]
    assert(following_task and math.abs(following_task.delay - 0.1) < 0.000001,
        "echo slash wave " .. wave .. " lost its absolute 0.1-second timing")
    following_task.callback()
    assert(#linear_projectiles == wave,
        "echo slash wave " .. wave .. " did not launch exactly once")
end
assert(#delayed_tasks == 7,
    "echo slash four waves scheduled unexpected combat callbacks")

for index, projectile in ipairs(linear_projectiles) do
    assert(projectile.Ability == ability and projectile.Source == attacker,
        "echo slash projectile source or ability changed at wave " .. index)
    assert(projectile.EffectName == nil,
        "echo slash collision projectile regained a visual EffectName")
    assert(projectile.fDistance == 500 and projectile.fStartRadius == 100
            and projectile.fEndRadius == 100,
        "echo slash distance or 200 total width changed at wave " .. index)
    assert(projectile.bDeleteOnHit == false
            and projectile.ExtraData.echo_slash_projectile_id == index,
        "echo slash penetration or state ID changed at wave " .. index)
end

assert(service._test.echo_slash_projectile_hit(ability, target, 1) == false,
    "echo slash first hit no longer penetrates")
assert(service._test.echo_slash_projectile_hit(ability, target, 1) == false,
    "echo slash duplicate hit no longer penetrates")
assert(#damage_requests == 1,
    "echo slash damaged the same target more than once in one wave")
assert(service._test.echo_slash_projectile_hit(ability, target, 2) == false,
    "echo slash second wave no longer penetrates")
assert(#damage_requests == 2,
    "echo slash did not let a separate wave damage the same target")
for _, request in ipairs(damage_requests) do
    assert(request.victim == target and request.damage_type == DAMAGE_TYPE_PURE,
        "echo slash authoritative victim or damage type changed")
    assert(math.abs(request.base_damage - 112.5) < 0.000001,
        "echo slash level-five per-wave random damage changed")
end

local original_create_particle = ParticleManager.CreateParticle
ParticleManager.CreateParticle = function()
    error("simulated echo slash particle creation failure")
end
local projectile_count_before_failure = #linear_projectiles
combat_context.level = 1
combat_context.attack_id = "echo_slash_visual_failure_combat_test"
local failure_isolated = pcall(function()
    assert(service._test.runners.proto_echo_slash(
            combat_context, combat_definition) == true)
end)
ParticleManager.CreateParticle = original_create_particle
assert(failure_isolated,
    "echo slash visual creation failure escaped the combat runner")
assert(#linear_projectiles == projectile_count_before_failure + 1,
    "echo slash visual creation failure blocked the collision projectile")

print("ECHO_SLASH_VISUAL_STATE_PASS")