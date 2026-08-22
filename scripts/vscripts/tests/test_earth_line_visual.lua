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
GameRules = { GetGameTime = function() return now end }

local delayed_tasks = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, task_id)
        delayed_tasks[#delayed_tasks + 1] = {
            delay = delay,
            callback = callback,
            task_id = task_id,
            cancelled = false,
        }
        return task_id or ("earth_line_after_" .. tostring(#delayed_tasks))
    end,
    every = function() return "earth_line_repeat" end,
    cancel = function(task_id)
        for _, task in ipairs(delayed_tasks) do
            if task.task_id == task_id then task.cancelled = true end
        end
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
package.loaded["systems/buff_manager"] = {
    apply = function() return true end,
    remove = function() end,
}
package.loaded["systems/hero_exclusive_passive_service"] = {
    runners = {},
    init = function() end,
    summon_locked = function() return false end,
    on_drow_companion_attack_landed = function() return false end,
}

local ability = { IsNull = function() return false end }
local attacker = {
    IsNull = function() return false end,
    IsAlive = function() return true end,
    entindex = function() return 801 end,
    GetAbsOrigin = function() return Vector(100, 200, 30) end,
    GetTeamNumber = function() return 2 end,
    FindAbilityByName = function() return ability end,
}

local function enemy(index, position, stunned)
    local unit = {
        modifiers = {},
        position = position,
        stunned = stunned == true,
    }
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:entindex() return index end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetTeamNumber() return 3 end
    function unit:GetHullRadius() return 0 end
    function unit:FindAllModifiersByName() return {} end
    function unit:IsStunned() return self.stunned end
    function unit:HasModifier(name)
        return name == "modifier_stunned" and self.stunned
    end
    function unit:AddNewModifier(_, _, name, options)
        self.modifiers[#self.modifiers + 1] = { name = name, options = options }
        if name == "modifier_stunned" then self.stunned = true end
        return self.modifiers[#self.modifiers]
    end
    return unit
end

local target = enemy(802, Vector(400, 600, 50), false)
local secondary = enemy(803, Vector(450, 600, 50), true)
FindUnitsInRadius = function() return { target, secondary } end
RandomFloat = function() return 0 end

package.loaded["systems/hero_passive_skill_service"] = nil
local service = require("systems/hero_passive_skill_service")
local definition = require("config/hero_passive_skill_definitions")
    .by_id.proto_earth_line
local context = {
    player_id = 0,
    attacker = attacker,
    target = target,
    target_position = Vector(400, 600, 50),
    attack_id = "earth_line_visual_test",
    skill_id = "proto_earth_line",
    level = 5,
    attributes = { all_attributes = 100 },
}

local function assert_vector(actual, x, y, z, message)
    assert(actual and math.abs(actual.x - x) < 0.000001
            and math.abs(actual.y - y) < 0.000001
            and math.abs(actual.z - z) < 0.000001,
        message .. ": got " .. tostring(actual and actual.x) .. ","
            .. tostring(actual and actual.y) .. ","
            .. tostring(actual and actual.z))
end

assert(service._test.runners.proto_earth_line(context, definition) == true,
    "earth line runner did not launch")
assert(#linear_projectiles == 1,
    "earth line did not create exactly one collision projectile")
local projectile = linear_projectiles[1]
local projectile_id = projectile.ExtraData.earth_rock_projectile_id
assert(projectile.Ability == ability and projectile.Source == attacker,
    "earth line collision projectile lost its ability or source")
assert(projectile.EffectName == nil,
    "earth line collision projectile retained a visual EffectName")
assert(projectile.fDistance == 500 and projectile.fStartRadius == 125
        and projectile.fEndRadius == 125,
    "earth line level-five distance or total width 250 changed")
assert_vector(projectile.vVelocity, 300, 400, 0,
    "earth line collision velocity changed from speed 500")
assert(projectile.bDeleteOnHit == false and projectile_id ~= nil,
    "earth line penetration or unique state ID changed")

assert(#particles == 1,
    "earth line did not create exactly one independent rolling visual")
local rolling = particles[1]
assert(rolling.path ==
        "particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf",
    "earth line visual is not the extended Chaos Meteor rolling parent")
assert(rolling.attach == PATTACH_WORLDORIGIN and rolling.owner == attacker,
    "earth line rolling visual did not use attacker world attachment")
assert_vector(rolling.controls[0], 100, 200, 30,
    "earth line Chaos Meteor CP0 did not use the snapshotted origin")
assert_vector(rolling.controls[1], 300, 400, 0,
    "earth line Chaos Meteor CP1 did not receive authoritative velocity")
assert_vector(rolling.controls[2], 1, 0, 0,
    "earth line Chaos Meteor CP2 did not receive the full travel duration")
assert(#delayed_tasks == 1 and math.abs(delayed_tasks[1].delay - 1.25) < 0.000001,
    "earth line cleanup did not preserve travel time plus grace")

assert(service._test.earth_rock_projectile_hit(
        ability, target, target:GetAbsOrigin(), projectile_id) == false,
    "earth line first path hit no longer penetrates")
assert(#damage_requests == 3,
    "earth line level-five first hit did not retain path plus area damage")
assert(damage_requests[1].victim == target
        and damage_requests[1].base_damage == 300,
    "earth line normal path damage changed from all-attributes x3")
assert(damage_requests[2].victim == target
        and damage_requests[2].base_damage == 300,
    "earth line first target no longer receives level-five area damage")
assert(damage_requests[3].victim == secondary
        and damage_requests[3].base_damage == 600,
    "earth line old-stun area multiplier changed from x6")
assert(#target.modifiers == 1 and target.modifiers[1].name == "modifier_stunned",
    "earth line path target did not receive post-damage level-five stun")
assert(#secondary.modifiers == 0,
    "earth line area target incorrectly received a path stun")

assert(service._test.earth_rock_projectile_hit(
        ability, target, target:GetAbsOrigin(), projectile_id) == false,
    "earth line duplicate hit no longer penetrates")
assert(#damage_requests == 3 and #target.modifiers == 1,
    "earth line duplicate path hit repeated damage or stun")
assert(service._test.earth_rock_projectile_hit(
        ability, secondary, secondary:GetAbsOrigin(), projectile_id) == false,
    "earth line second unit hit no longer penetrates")
assert(#damage_requests == 4 and damage_requests[4].victim == secondary
        and damage_requests[4].base_damage == 600,
    "earth line old-stun path multiplier changed from x6")

assert(service._test.earth_rock_projectile_hit(
        ability, nil, context.target_position, projectile_id) == false,
    "earth line terminal callback no longer returns false")
assert(service._test.earth_rock_projectiles()[projectile_id] == nil,
    "earth line terminal callback retained projectile state")
assert(rolling.destroy_count == 1 and rolling.release_count == 1
        and rolling.destroy_immediate,
    "earth line terminal callback did not immediately clean rolling parent")
assert(#particles == 2
        and particles[2].path ==
            "particles/basic_projectile/basic_projectile_explosion.vpcf"
        and particles[2].release_count == 1,
    "earth line terminal callback changed the existing harmless explosion")
delayed_tasks[1].callback()
assert(rolling.destroy_count == 1 and rolling.release_count == 1
        and #particles == 2,
    "earth line late failsafe repeated cleanup or terminal explosion")

now = 20
context.attack_id = "earth_line_failsafe_test"
assert(service._test.runners.proto_earth_line(context, definition) == true,
    "earth line failsafe case did not launch")
local failsafe_projectile = linear_projectiles[2]
local failsafe_id = failsafe_projectile.ExtraData.earth_rock_projectile_id
local failsafe_rolling = particles[3]
delayed_tasks[2].callback()
assert(service._test.earth_rock_projectiles()[failsafe_id] == nil,
    "earth line failsafe retained projectile state")
assert(failsafe_rolling.destroy_count == 1
        and failsafe_rolling.release_count == 1
        and failsafe_rolling.destroy_immediate,
    "earth line failsafe did not immediately clean rolling parent")
assert(#particles == 4,
    "earth line failsafe did not create exactly one terminal explosion")

now = 30
context.attack_id = "earth_line_reset_test"
assert(service._test.runners.proto_earth_line(context, definition) == true,
    "earth line reset case did not launch")
local reset_projectile = linear_projectiles[3]
local reset_id = reset_projectile.ExtraData.earth_rock_projectile_id
local reset_rolling = particles[5]
service._test.earth_rock_clear()
assert(service._test.earth_rock_projectiles()[reset_id] == nil,
    "earth line reset retained projectile state")
assert(reset_rolling.destroy_count == 1 and reset_rolling.release_count == 1
        and reset_rolling.destroy_immediate and #particles == 5,
    "earth line reset was not immediate or incorrectly played terminal explosion")

local original_set_control = ParticleManager.SetParticleControl
ParticleManager.SetParticleControl = function()
    error("simulated earth line control point failure")
end
context.attack_id = "earth_line_visual_failure_test"
local projectile_count_before_failure = #linear_projectiles
local failure_isolated = pcall(function()
    assert(service._test.runners.proto_earth_line(context, definition) == true)
end)
ParticleManager.SetParticleControl = original_set_control
assert(failure_isolated,
    "earth line visual control failure escaped the combat runner")
assert(#linear_projectiles == projectile_count_before_failure + 1,
    "earth line visual control failure blocked collision projectile creation")
local failed_projectile = linear_projectiles[#linear_projectiles]
local failed_id = failed_projectile.ExtraData.earth_rock_projectile_id
local failed_visual = particles[6]
assert(service._test.earth_rock_projectiles()[failed_id]
        and service._test.earth_rock_projectiles()[failed_id].visual_particle == nil,
    "earth line visual failure removed collision state or retained particle handle")
assert(failed_visual.destroy_count == 1 and failed_visual.release_count == 1
        and failed_visual.destroy_immediate,
    "earth line visual failure did not clean its partial parent")
service._test.earth_rock_release(failed_id, false)

context.attack_id = "earth_line_parallel_a"
assert(service._test.runners.proto_earth_line(context, definition) == true,
    "earth line first parallel case did not launch")
local parallel_a_projectile = linear_projectiles[#linear_projectiles]
local parallel_a_id = parallel_a_projectile.ExtraData.earth_rock_projectile_id
local parallel_a_visual = particles[#particles]
context.attack_id = "earth_line_parallel_b"
assert(service._test.runners.proto_earth_line(context, definition) == true,
    "earth line second parallel case did not launch")
local parallel_b_projectile = linear_projectiles[#linear_projectiles]
local parallel_b_id = parallel_b_projectile.ExtraData.earth_rock_projectile_id
local parallel_b_visual = particles[#particles]
assert(parallel_a_id ~= parallel_b_id
        and parallel_a_visual ~= parallel_b_visual
        and service._test.earth_rock_projectiles()[parallel_a_id]
        and service._test.earth_rock_projectiles()[parallel_b_id],
    "earth line parallel instances did not retain independent state and visuals")
service._test.earth_rock_release(parallel_a_id, false)
assert(parallel_a_visual.destroy_count == 1
        and parallel_a_visual.release_count == 1
        and parallel_b_visual.destroy_count == 0
        and parallel_b_visual.release_count == 0
        and service._test.earth_rock_projectiles()[parallel_b_id],
    "earth line first parallel cleanup affected the second visual")
service._test.earth_rock_clear()
assert(parallel_b_visual.destroy_count == 1
        and parallel_b_visual.release_count == 1
        and service._test.earth_rock_projectiles()[parallel_b_id] == nil,
    "earth line reset did not independently clean the remaining parallel visual")

print("EARTH_LINE_VISUAL_STATE_PASS")