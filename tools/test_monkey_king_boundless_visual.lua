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
FIND_ANY_ORDER = 32
DAMAGE_TYPE_PURE = 64

local scheduled = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, task_id)
        scheduled[task_id] = {
            delay = delay,
            callback = callback,
            cancelled = false,
        }
        return task_id
    end,
    every = function() return "monkey_visual_every" end,
    cancel = function(task_id)
        if scheduled[task_id] then scheduled[task_id].cancelled = true end
    end,
}

local function run_task(task_id)
    local task = assert(scheduled[task_id], "missing task " .. tostring(task_id))
    if task.cancelled then return false end
    return task.callback()
end

local events = require("core/events")
local combat_events = require("combat/combat_events")
local damage_requests = {}
local sound_calls = {}
local sound_should_fail = false
package.loaded["core/sound_service"] = {
    play = function(cue_id, options)
        sound_calls[#sound_calls + 1] = {
            cue_id = cue_id,
            options = options,
        }
        return not sound_should_fail
    end,
}
local stats = { strength = 10, agility = 20, intellect = 30 }
package.loaded["core/event_bus"] = {
    emit = function() end,
    handle_request = function() end,
    subscribe = function() return {} end,
    request = function(name, payload)
        if name == events.HERO_COMBAT_STATS_GET_REQUEST then
            return { snapshot = stats }
        end
        if name == events.HERO_SKILL_STATE_GET_REQUEST then
            return {
                snapshot = {
                    skills = {
                        {
                            skill_id = "skill_monkey_king_exclusive",
                            level = 1,
                            locked = 0,
                        },
                    },
                },
            }
        end
        if name == combat_events.DEAL_REQUEST then
            damage_requests[#damage_requests + 1] = payload
            return { success = true, damage = payload.base_damage }
        end
        return nil
    end,
}

local particles = {}
local fail_forward = false
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        local id = #particles + 1
        particles[id] = {
            path = path,
            attach = attach,
            owner = owner,
            controls = {},
            forwards = {},
            destroy_count = 0,
            release_count = 0,
        }
        return id
    end,
    SetParticleControl = function(_, id, control_point, value)
        particles[id].controls[control_point] =
            Vector(value.x, value.y, value.z)
    end,
    SetParticleControlForward = function(_, id, control_point, value)
        if fail_forward then error("simulated forward failure") end
        particles[id].forwards[control_point] =
            Vector(value.x, value.y, value.z)
    end,
    DestroyParticle = function(_, id, immediate)
        particles[id].destroy_count = particles[id].destroy_count + 1
        particles[id].destroy_immediate = immediate == true
    end,
    ReleaseParticleIndex = function(_, id)
        particles[id].release_count = particles[id].release_count + 1
    end,
}

GetGroundPosition = function(position)
    local ground_z = position.x < 500 and 7 or 19
    return Vector(position.x, position.y, ground_z)
end
local roll_result = true
RollPercentage = function(chance)
    assert(chance == 10, "Monkey King Q proc chance changed")
    return roll_result
end

local ability = { IsNull = function() return false end }
local origin = Vector(100, 200, 50)
local attacker_null = false
local attacker = {
    IsNull = function() return attacker_null end,
    IsAlive = function() return true end,
    GetAbsOrigin = function() return origin end,
    GetForwardVector = function() return Vector(0, -1, 0) end,
    GetTeamNumber = function() return 2 end,
    FindAbilityByName = function(_, name)
        assert(name == "ability_survival_monkey_king_exclusive",
            "Monkey King Q damage used another ability")
        return ability
    end,
}

local function enemy(entindex, position, max_health)
    local current = position
    local current_max_health = max_health
    return {
        IsNull = function() return false end,
        IsAlive = function() return true end,
        GetAbsOrigin = function() return current end,
        SetAbsOrigin = function(_, value) current = value end,
        GetHullRadius = function() return 24 end,
        GetMaxHealth = function() return current_max_health end,
        SetMaxHealth = function(_, value) current_max_health = value end,
        entindex = function() return entindex end,
    }
end

local target = enemy(901, Vector(400, 600, 80), 1000)
local entrant = enemy(902, Vector(2000, 2000, 80), 1000)
local candidates = { target, entrant }
FindUnitsInRadius = function() return candidates end

package.loaded["systems/monkey_king_exclusive_service"] = nil
local service = require("systems/monkey_king_exclusive_service")

local function assert_vector(actual, x, y, z, message)
    assert(actual and math.abs(actual.x - x) < 0.000001
            and math.abs(actual.y - y) < 0.000001
            and math.abs(actual.z - z) < 0.000001,
        message .. ": got " .. tostring(actual and actual.x) .. ","
            .. tostring(actual and actual.y) .. ","
            .. tostring(actual and actual.z))
end

roll_result = false
assert(service._test.trigger_q(0, attacker, target) == false,
    "Monkey King Q triggered after a failed proc roll")
assert(#particles == 0 and #sound_calls == 0,
    "Failed Monkey King Q proc created visuals or sounds")
roll_result = true

assert(service._test.trigger_q(0, attacker, target) == true,
    "Monkey King Q did not trigger")
assert(#sound_calls == 1
        and sound_calls[1].cue_id == "hero_monkey_boundless_cast"
        and sound_calls[1].options.unit == attacker
        and sound_calls[1].options.source == attacker,
    "Monkey King Q cast sound did not start on the attacker")
assert(#particles == 1, "Monkey King Q did not start with one drop visual")
local drop = particles[1]
assert(drop.path ==
        "particles/survival_monkey_king/survival_monkey_king_staff_drop.vpcf",
    "Monkey King Q did not use the project staff-drop particle")
assert(drop.attach == PATTACH_WORLDORIGIN and drop.owner == attacker,
    "Monkey King Q staff-drop attachment changed")
assert_vector(drop.controls[0], 460, 680, 1007,
    "Monkey King Q staff drop did not start above the fixed line center")
assert_vector(drop.forwards[0], 0.6, 0.8, 0,
    "Monkey King Q staff drop did not follow the strike direction")
assert_vector(drop.controls[1], 1180, 1640, 1007,
    "Monkey King Q staff-drop orientation endpoint changed")
assert_vector(drop.controls[2], 0, 0, -350,
    "Monkey King Q staff-drop velocity changed")
assert(scheduled.monkey_q_impact_1.delay == 0.28,
    "Monkey King Q impact delay changed")
assert(#damage_requests == 0,
    "Monkey King Q dealt damage before the staff landed")
assert(#sound_calls == 1,
    "Monkey King Q impact sound played before the staff landed")

stats = { strength = 100, agility = 200, intellect = 300 }
target:SetAbsOrigin(Vector(2000, 2000, 80))
entrant:SetAbsOrigin(Vector(400, 600, 80))
entrant:SetMaxHealth(2000)
assert(run_task("monkey_q_impact_1") == false,
    "Monkey King Q impact callback did not terminate")
assert(#sound_calls == 2
        and sound_calls[2].cue_id == "hero_monkey_boundless_impact"
        and sound_calls[2].options.source == attacker,
    "Monkey King Q impact sound did not play on the landing frame")
assert_vector(sound_calls[2].options.position, 460, 680, 7,
    "Monkey King Q impact sound did not use the fixed path midpoint")
assert(drop.destroy_count == 1 and drop.destroy_immediate == true
        and drop.release_count == 1,
    "Monkey King Q staff drop was not cleaned on impact")
assert(#particles == 2, "Monkey King Q impact did not create the ground visual")
local ground = particles[2]
assert(ground.path ==
        "particles/units/heroes/hero_monkey_king/monkey_king_strike.vpcf",
    "Monkey King Q impact no longer uses the Boundless Strike parent")
assert_vector(ground.controls[0], 100, 200, 7,
    "Monkey King Q impact CP0 did not snap the cast origin to ground")
assert_vector(ground.forwards[0], 0.6, 0.8, 0,
    "Monkey King Q impact CP0 forward lost the fixed direction")
assert_vector(ground.controls[1], 820, 1160, 19,
    "Monkey King Q impact CP1 lost the fixed 1200 endpoint")
assert_vector(ground.controls[2], 820, 1160, 19,
    "Monkey King Q impact CP2 no longer matches the endpoint")
assert(ground.release_count == 1 and ground.destroy_count == 0,
    "Successful Monkey King Q ground visual cleanup changed")
assert(#damage_requests == 1
        and damage_requests[1].victim == entrant
        and damage_requests[1].base_damage == 2000,
    "Monkey King Q did not rescan at impact with trigger-time attributes")

target:SetAbsOrigin(Vector(100, 200, 80))
candidates = { target }
assert(service._test.trigger_q(0, attacker, target) == true,
    "Monkey King Q same-position fallback did not trigger")
assert_vector(particles[3].forwards[0], 0, -1, 0,
    "Monkey King Q same-position drop lost attacker forward")
assert_vector(particles[3].controls[0], 100, -400, 1007,
    "Monkey King Q fallback drop center changed")
assert(run_task("monkey_q_impact_2") == false,
    "Monkey King Q fallback impact did not finish")
assert_vector(particles[4].controls[1], 100, -1000, 7,
    "Monkey King Q fallback ground endpoint changed")

target:SetAbsOrigin(Vector(400, 600, 80))
assert(service.trigger_clone_q(0, attacker, target) == true,
    "Monkey King clone Q did not reuse the Q trigger path")
assert_vector(particles[5].forwards[0], 0.6, 0.8, 0,
    "Monkey King clone Q did not reuse the drop direction")
assert(run_task("monkey_q_impact_3") == false,
    "Monkey King clone Q impact did not finish")

local damage_count = #damage_requests
fail_forward = true
sound_should_fail = true
assert(service._test.trigger_q(0, attacker, target) == true,
    "Monkey King Q visual or sound failure blocked the trigger")
local failed_drop = particles[7]
assert(failed_drop.destroy_count == 1
        and failed_drop.destroy_immediate == true
        and failed_drop.release_count == 1,
    "Failed Monkey King Q drop visual was not cleaned immediately")
assert(#damage_requests == damage_count,
    "Monkey King Q visual failure bypassed the impact delay")
assert(run_task("monkey_q_impact_4") == false,
    "Monkey King Q impact failed after drop visual failure")
assert(#damage_requests == damage_count + 1,
    "Monkey King Q visual or sound failures blocked authoritative impact damage")
assert(service._test.health_hits()[0]["901"] == 3
        and service._test.health_hits()[0]["902"] == 1,
    "Monkey King Q shared max-health hit counts changed")
fail_forward = false
sound_should_fail = false

damage_count = #damage_requests
assert(service._test.trigger_q(0, attacker, target) == true,
    "Monkey King Q invalid-attacker case did not trigger")
attacker_null = true
assert(run_task("monkey_q_impact_5") == false,
    "Monkey King Q invalid-attacker impact did not terminate")
assert(#damage_requests == damage_count,
    "Monkey King Q damaged after its attacker entity was removed")
attacker_null = false

assert(service._test.trigger_q(0, attacker, target) == true,
    "First parallel Monkey King Q did not trigger")
assert(service._test.trigger_q(0, attacker, target) == true,
    "Second parallel Monkey King Q did not trigger")
assert(service._test.impacts()[6] and service._test.impacts()[7],
    "Parallel Monkey King Q impacts were not isolated")
local reset_drop_a = particles[#particles - 1]
local reset_drop_b = particles[#particles]
damage_count = #damage_requests
local sound_count = #sound_calls
service.init()
assert(reset_drop_a.destroy_count == 1 and reset_drop_a.release_count == 1
        and reset_drop_b.destroy_count == 1 and reset_drop_b.release_count == 1,
    "Monkey King Q reset did not clean all pending drops")
assert(scheduled.monkey_q_impact_6.cancelled
        and scheduled.monkey_q_impact_7.cancelled,
    "Monkey King Q reset did not cancel all impact tasks")
assert(service._test.resolve_q_impact(6) == false
        and service._test.resolve_q_impact(7) == false,
    "Late Monkey King Q callbacks were not idempotent")
assert(#damage_requests == damage_count,
    "Late Monkey King Q callbacks dealt duplicate damage")
assert(#sound_calls == sound_count,
    "Reset or late Monkey King Q callbacks played an impact sound")

candidates = {}
sound_count = #sound_calls
damage_count = #damage_requests
assert(service._test.trigger_q(0, attacker, target) == true,
    "Empty-path Monkey King Q did not trigger")
assert(#sound_calls == sound_count + 1
        and sound_calls[#sound_calls].cue_id == "hero_monkey_boundless_cast",
    "Empty-path Monkey King Q did not play its cast sound")
assert(run_task("monkey_q_impact_1") == false,
    "Empty-path Monkey King Q impact did not finish")
assert(#sound_calls == sound_count + 2
        and sound_calls[#sound_calls].cue_id == "hero_monkey_boundless_impact",
    "Empty-path Monkey King Q did not play its real ground impact")
assert(#damage_requests == damage_count,
    "Empty-path Monkey King Q dealt damage without a target")

print("MONKEY_KING_BOUNDLESS_VISUAL_STATE_PASS")
