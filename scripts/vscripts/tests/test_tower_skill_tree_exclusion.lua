-- Run from the addon root with Lua 5.1+; no game process is required.
package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
math.pow = math.pow or function(a, b) return a ^ b end

local events = require("core/events")
local handlers, subscribers = {}, {}
local emitted, requested, damage, buffs, particles, destroyed = {}, {}, {}, {}, {}, {}
local tracking, linear, sounds, scheduled = {}, {}, {}, {}
local control_writes, control_entities, particle_releases = {}, {}, {}
local immediate_destroys = {}
local native_attacks = {}
local gestures = {}
local gold_numbers = {}
OVERHEAD_ALERT_GOLD = 0
PlayerResource = { GetPlayer = function(_, id) return id end }
SendOverheadEventMessage = function(player, style, owner, amount)
    assert(style == OVERHEAD_ALERT_GOLD)
    gold_numbers[#gold_numbers+1] = {player=player, owner=owner, amount=amount}
end
local candidates, last_radius = {}, nil
local now, next_task = 0, 0
local function vector(x, y, z)
    local mt = {}
    mt.__index = {
        Length2D = function(v) return math.sqrt(v.x * v.x + v.y * v.y) end,
        Normalized = function(v)
            local n = v:Length2D()
            return vector(v.x / n, v.y / n, 0)
        end,
    }
    mt.__add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    mt.__sub = function(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
    mt.__mul = function(a, b) return vector(a.x * b, a.y * b, a.z * b) end
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, mt)
end
Vector = vector
class = function(base) base.__index = base; return base end
LinkLuaModifier = function() end
IsServer = function() return true end
RollPercentage = function(chance) return chance > 0 end
RandomFloat = function() return 100 end
RandomInt = function() return 1 end
GameRules = { GetGameTime = function() return now end }
LUA_MODIFIER_MOTION_NONE = 0
DAMAGE_TYPE_PHYSICAL = 1
DOTA_DAMAGE_CATEGORY_ATTACK = 1
DOTA_DAMAGE_FLAG_NO_DAMAGE_MULTIPLIERS = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 1
DOTA_UNIT_TARGET_HERO = 2
DOTA_UNIT_TARGET_BASIC = 4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 8
DOTA_UNIT_CAP_MOVE_FLY = 16
ACT_DOTA_ATTACK = 17
FIND_ANY_ORDER = 0
FIND_CLOSEST = 1
PATTACH_ABSORIGIN_FOLLOW = 0
PATTACH_CUSTOMORIGIN = 1
PATTACH_WORLDORIGIN = 2
PATTACH_POINT_FOLLOW = 3
FindUnitsInRadius = function(_, _, _, radius)
    last_radius = radius
    return candidates
end
ParticleManager = {
    CreateParticle = function(_, path, _, owner)
        particles[#particles + 1] = { path = path, owner = owner }
        return #particles
    end,
    SetParticleControl = function(_, id, cp, position)
        control_writes[#control_writes + 1] = { id = id, cp = cp, position = position }
    end,
    SetParticleControlEnt = function(_, id, cp, owner, attach, point, fallback)
        control_entities[#control_entities + 1] = {
            id = id, cp = cp, owner = owner, attach = attach,
            point = point, fallback = fallback,
        }
    end,
    SetParticleControlOrientation = function(_, id, cp, forward, right, up)
        particles[id].orientations = particles[id].orientations or {}
        particles[id].orientations[cp] = { forward = forward, right = right, up = up }
    end,
    DestroyParticle = function(_, id, immediate)
        destroyed[#destroyed + 1] = id
        immediate_destroys[id] = immediate
    end,
    ReleaseParticleIndex = function(_, id)
        particle_releases[id] = (particle_releases[id] or 0) + 1
    end,
}
ProjectileManager = {
    CreateTrackingProjectile = function(_, info)
        tracking[#tracking + 1] = info
        return #tracking
    end,
    CreateLinearProjectile = function(_, info)
        linear[#linear + 1] = info
        return #linear
    end,
    DestroyLinearProjectile = function() end,
}
local bus = {
    subscribe = function(event, callback) subscribers[event] = callback end,
    handle_request = function(event, callback) handlers[event] = callback end,
    emit = function(event, payload)
        emitted[#emitted + 1] = { event = event, payload = payload }
        if subscribers[event] then subscribers[event](payload) end
    end,
    request = function(event, payload)
        requested[#requested + 1] = { event = event, payload = payload }
        if handlers[event] then return handlers[event](payload) end
        if event == events.RESOURCE_ADD_REQUEST then return { ok = true } end
    end,
}
package.loaded["core/event_bus"] = bus
package.loaded["core/scheduler"] = {
    after = function(delay, callback, id)
        next_task = next_task + 1
        id = id or ("test_task_" .. next_task)
        scheduled[#scheduled + 1] = { id = id, callback = callback, delay = delay }
        return id
    end,
    cancel = function(id)
        for _, task in ipairs(scheduled) do
            if task.id == id then task.cancelled = true end
        end
    end,
    every = function(delay, callback, id)
        scheduled[#scheduled + 1] = { id = id, callback = callback, delay = delay, repeating = true }
        return id
    end,
}
package.loaded["core/sound_service"] = {
    play = function(cue) sounds[#sounds + 1] = cue end,
}
local tree_rules = require("systems/tree_damage_rules")
package.loaded["combat/damage_service"] = {
    Deal = function(_, payload)
        assert(not tree_rules.is_tree(payload.victim), "tree reached damage service")
        damage[#damage + 1] = payload
        return { success = true, final_damage = payload.base_damage }
    end,
}
package.loaded["systems/buff_manager"] = {
    apply = function(caster, target, buff, options)
        assert(not tree_rules.is_tree(target), "tree reached buff application")
        buffs[#buffs + 1] = { caster = caster, target = target, buff = buff, options = options }
        return { GetStackCount = function() return 1 end }
    end,
    value = function() return 0 end,
    apply_aura = function() end,
    remove_aura = function() end,
}
package.loaded["systems/tower_skill_runtime"] = {
    get = function(unit) return unit.skills or {} end,
}
package.loaded["config/asset_catalog"] = { by_id = {}, get = function(asset_id)
    if asset_id == "test_native_stage" then return { native_wearable_stage = true } end
end }

local ability = { IsNull = function() return false end, GetLevel = function() return 1 end }
local function unit(id, name, x, team)
    return {
        id = id, name = name, position = vector(x, 0, 0), alive = true,
        team = team or 3, skills = {}, range = 600,
        IsNull = function() return false end,
        IsAlive = function(self) return self.alive end,
        GetUnitName = function(self) return self.name end,
        entindex = function(self) return self.id end,
        GetTeamNumber = function(self) return self.team end,
        GetAbsOrigin = function(self) return self.position end,
        GetHullRadius = function() return 0 end,
        GetAverageTrueAttackDamage = function() return 100 end,
        Script_GetAttackRange = function(self) return self.range end,
        GetAttackRange = function(self) return self.range end,
        GetAcquisitionRange = function() error("combat must not read acquisition range") end,
        GetAttackTarget = function(self) return self.attack_target end,
        StartGesture = function(_, activity)
            gestures[#gestures + 1] = { activity = activity }
        end,
        StartGestureWithPlaybackRate = function(_, activity, rate)
            gestures[#gestures + 1] = { activity = activity, rate = rate }
        end,
        SetRangedProjectileName = function() end,
        FindAbilityByName = function() return ability end,
        PerformAttack = function(_, target)
            assert(not tree_rules.is_tree(target), "tree reached delayed native attack")
            native_attacks[#native_attacks + 1] = target
        end,
        AddNewModifier = function(_, caster, source_ability, name, options)
            buffs[#buffs + 1] = {
                caster = caster, ability = source_ability, name = name, options = options,
            }
        end,
    }
end
local tower = unit(1, "building_arrow_tower", 0, 2)
tower.survival_building_id = "arrow_tower"
tower.survival_player_id = 0
local tree = unit(2, "enemy_tree", 50)
local dummy = unit(3, "npc_dota_training_dummy", 150)
local second = unit(4, "npc_survival_wave_monster", 200)
local third = unit(5, "npc_survival_wave_monster", 250)
local fourth = unit(6, "npc_survival_wave_monster", 300)
local geometry = require("systems/tower_skill_geometry")
local adapter = require("systems/tower_skill_effect_adapter")
local special = require("systems/tower_special_skill_system")
local effects = require("modifiers/modifier_tower_attack_effects")
adapter.init()
special.init()
local function modifier(skills)
    tower.skills = skills or {}
    local result = setmetatable({
        GetParent = function() return tower end,
        StartIntervalThink = function() end,
    }, { __index = effects })
    result:OnCreated()
    return result
end
local function clear()
    emitted, requested, damage, buffs, particles, destroyed = {}, {}, {}, {}, {}, {}
    tracking, linear, sounds, scheduled = {}, {}, {}, {}
    control_writes, control_entities, particle_releases, immediate_destroys = {}, {}, {}, {}
    native_attacks = {}
    gestures = {}
    gold_numbers = {}
    candidates = {}
end
local function drain()
    local steps = 0
    while #scheduled > 0 do
        local task = table.remove(scheduled, 1)
        if not task.cancelled then
            local again = task.callback()
            if task.repeating and again ~= false then scheduled[#scheduled + 1] = task end
        end
        steps = steps + 1
        assert(steps < 100, "unexpected unbounded scheduled callbacks")
    end
end
local function count_event(event)
    local count = 0
    for _, item in ipairs(emitted) do
        if item.event == event then count = count + 1 end
    end
    return count
end
local function count_request(event)
    local count = 0
    for _, item in ipairs(requested) do
        if item.event == event then count = count + 1 end
    end
    return count
end
local function no_effects(label)
    assert(#damage == 0 and #buffs == 0 and #particles == 0 and #sounds == 0
        and #tracking == 0 and #linear == 0 and #native_attacks == 0 and #gestures == 0,
        label .. ": gameplay or visual side effect")
end

-- Query results include trees before legitimate enemies. Both broad-phase and
-- path checks must retain training dummies without spending slots on trees.
candidates = { tree, dummy, second }
local circle = geometry.enemies_in_circle(tower, vector(0, 0, 0), 400)
assert(#circle == 2 and circle[1] == dummy and circle[2] == second)
local path = geometry.enemies_in_path(tower, vector(0, 0, 0), vector(400, 0, 0), 50)
assert(#path == 2 and path[1] == dummy and path[2] == second)

-- The adapter is a final guard even if an independent producer sends an
-- invalid target. Normal training dummies still support damage and debuffs.
clear()
assert(bus.request(events.TOWER_SKILL_DAMAGE_REQUEST,
    { attacker = tower, victim = tree, damage = 100 }).success == false)
assert(bus.request(events.TOWER_SKILL_BUFF_REQUEST,
    { caster = tower, target = tree, buff_id = "slow" }) == nil)
no_effects("adapter tree")
assert(bus.request(events.TOWER_SKILL_DAMAGE_REQUEST,
    { attacker = tower, victim = dummy, damage = 100 }).success == true)
assert(bus.request(events.TOWER_SKILL_BUFF_REQUEST,
    { caster = tower, target = dummy, buff_id = "slow" }))
assert(#damage == 1 and #buffs == 1)

-- Hero-shaped native tower stages explicitly play their body's attack gesture.
-- A resource-tree callback must never reach either gesture API; legal targets
-- still play both the normal and accelerated lightning-stage animations.
clear()
tower.survival_model_asset_id = "test_native_stage"
local gesture_modifier = modifier({})
gesture_modifier:OnAttackStart({ attacker = tower, target = tree })
assert(#gestures == 0 and #emitted == 0, "tree started a native-stage body gesture")
gesture_modifier:OnAttackStart({ attacker = tower, target = dummy })
assert(#gestures == 1 and gestures[1].activity == ACT_DOTA_ATTACK and gestures[1].rate == nil)
clear()
gesture_modifier = modifier({ { skill_id = "lightning_strike_lv01" } })
gesture_modifier:OnAttackStart({ attacker = tower, target = tree })
assert(#gestures == 0 and #emitted == 0, "tree started an accelerated body gesture")
gesture_modifier:OnAttackStart({ attacker = tower, target = dummy })
assert(#gestures == 1 and gestures[1].activity == ACT_DOTA_ATTACK and gestures[1].rate == 2)
tower.survival_model_asset_id = nil

local laser = { skill_id = "laser_lv01", damage_interval = 1, damage_multiplier = 1 }
local beam = require("config/generated/tower_laser_effects").by_id["laser_lv01:default"]
assert(beam.beam_mode == "native" and beam.particle_name == "particles/units/heroes/hero_tinker/tinker_laser.vpcf",
    "production laser CSV must select native Tinker")
local production_beam = {}
for key,value in pairs(beam) do production_beam[key] = value end
-- Retain the existing segmented-mode regressions as a supported fallback.
-- The production continuous contract is exercised separately below.
beam.beam_mode = "segmented"
beam.visual_refresh_interval, beam.visual_segment_duration = 0.12, 0.18
assert(beam.damage_tick_interval == nil, "damage must retain original one-second settlement")
-- Legacy body-binding and failure contracts below remain supported. The new
-- production surface/color/pose path is exercised separately after them.
beam.target_surface = false
beam.source_orb = false
local bounty = { skill_id = "bounty_machine_gun_lv01", damage_multiplier = 3 }
local gatling = { skill_id = "explosive_gatling_lv01", buff_id = "gatling", damage_multiplier = 0.2 }
local arcane = { skill_id = "arcane_cannon_lv01", buff_id = "arcane", damage_multiplier = 0.2 }
clear()
local m = modifier({ laser, bounty, gatling, arcane })
m:OnAttackStart({ attacker = tower, target = tree })
m:OnAttack({ attacker = tower, target = tree })
m:OnAttackLanded({ attacker = tower, target = tree })
m:OnAttackFail({ attacker = tower, target = tree })
m:OnDeath({ attacker = tower, unit = tree })
assert(effects._start_laser_for_test(m, tree, beam) == false)
assert(effects._deal_laser_tick_for_test(m, tower, tree, laser, beam) == false)
assert(effects._fire_machine_gun_hit_for_test(m, tower, tree, 1) == false)
m.pending_critical_multiplier = 10
m.current_attack_target = tree
assert(m:GetModifierPreAttack_CriticalStrike() == 0)
assert(m.pending_critical_multiplier == nil)
assert(m.attack_landed_diagnostic_count == 0 and m.attack_failed_diagnostic_count == 0)
assert(m.gatling_target_hits == 0 and m.laser_ticks == nil)
assert(#emitted == 0 and #requested == 0, "tree emitted attack, critical or gold requests")
no_effects("tree attack entry points")

-- A legal dummy starts and sustains the laser even with acquisition disabled.
-- A later invalid target or an out-of-range target tears down the old visual.
clear()
m = modifier({ laser })
tower.attack_target = dummy
m:OnAttackStart({ attacker = tower, target = dummy })
assert(#particles > 0 and #damage == 1 and count_event(events.TOWER_LASER_HIT) == 1)
now = now + 1
m:OnIntervalThink()
assert(#damage == 2 and m.laser_ticks == 2, "valid laser did not continue")
local before_particles, before_damage, before_events = #particles, #damage, #emitted
dummy.name = "enemy_tree"
now = now + 1
m:OnIntervalThink()
assert(m.laser_target == nil and #destroyed > 0)
assert(#particles == before_particles and #damage == before_damage and #emitted == before_events)
dummy.name = "npc_dota_training_dummy"
clear()
m = modifier({ laser })
dummy.position = vector(697, 0, 0)
m:OnAttackStart({ attacker = tower, target = dummy })
assert(#particles == 0 and #damage == 0 and count_event(events.TOWER_LASER_HIT) == 0)
dummy.position = vector(664, 0, 0)
m:OnAttackStart({ attacker = tower, target = dummy })
assert(#damage == 1 and #particles > 0, "legal hull-edge target lost its beam")
now = now + 1
m:OnIntervalThink()
assert(#damage == 2, "legal hull-edge target could not sustain its beam")
dummy.position = vector(697, 0, 0)
now = now + 1
m:OnIntervalThink()
assert(m.laser_target == nil and #damage == 2)
dummy.position = vector(150, 0, 0)

-- The engine owns both laser endpoints between server thinks. Movement must
-- not write world-space snapshots over an entity CP or advance damage ticks.
clear()
local function attachment_lookup(_, name)
    return name == "attach_hitloc" and 5 or name == "attach_attack1" and 10 or 0
end
tower.ScriptLookupAttachment = attachment_lookup
dummy.ScriptLookupAttachment = attachment_lookup
second.ScriptLookupAttachment = attachment_lookup
m = modifier({ laser })
tower.attack_target = dummy
m:OnAttackStart({ attacker = tower, target = dummy })
assert(#control_entities == 3 and #control_writes == 0)
assert(control_entities[1].cp == 9 and control_entities[1].owner == tower
    and control_entities[1].point == "attach_attack1")
assert(control_entities[2].cp == 0 and control_entities[2].owner == tower)
assert(control_entities[3].cp == 1 and control_entities[3].owner == dummy
    and control_entities[3].point == "attach_hitloc")
for _, cp in ipairs(control_entities) do assert(cp.attach == PATTACH_POINT_FOLLOW) end
local first_segment = m.laser_particles[1].index
tower.position = vector(20, 15, 10)
dummy.position = vector(260, 90, 40)
now = now + 0.06
m:OnIntervalThink()
assert(#control_entities == 3 and #control_writes == 0 and #damage == 1)
now = now + 0.06
m:OnIntervalThink()
assert(#particles == 2 and #control_entities == 6 and #damage == 1,
    "visual replay changed damage frequency")
now = now + 0.07
m:OnIntervalThink()
assert(immediate_destroys[first_segment] == true and particle_releases[first_segment] == 1,
    "expired beam left a detached native fade-out tail")
now = now + 0.81
m:OnIntervalThink()
assert(#damage == 2 and damage[1].base_damage == 100 and damage[2].base_damage == 105,
    "native follow changed the one-second damage ramp")
assert(#control_writes == 0, "moving attachments were overwritten by polling")

-- Switching attacks retires every old segment and binds the new body once.
tower.attack_target = second
m:OnAttackStart({ attacker = tower, target = second })
assert(m.laser_target == second and #damage == 3 and damage[3].base_damage == 100)
assert(control_entities[#control_entities].owner == second)
for id = 1, #particles - 1 do
    assert(immediate_destroys[id] == true and particle_releases[id] == 1)
end
local death_segment = m.laser_particles[1].index
second.alive = false
m:OnDeath({ attacker = dummy, unit = second })
assert(m.laser_target == nil and #m.laser_particles == 0,
    "another attacker's kill did not immediately detach the beam")
assert(immediate_destroys[death_segment] == true and particle_releases[death_segment] == 1)
second.alive = true

-- Tower relocation and destruction clean entity-bound segments exactly once.
tower.attack_target = dummy
m:OnAttackStart({ attacker = tower, target = dummy })
local moved_segment = m.laser_particles[1].index
m:ResetAfterRelocation()
assert(m.laser_target == nil and #m.laser_particles == 0)
assert(immediate_destroys[moved_segment] == true and particle_releases[moved_segment] == 1)
m:OnDestroy()
assert(particle_releases[moved_segment] == 1, "relocation cleanup double-released a beam")

-- Count the real modifier's engine calls for thirty seconds; no extra Lua
-- think or per-frame CP writes are needed to move supported attachments.
clear()
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
local count_start = now
local peak_live = 0
for step = 1, 1000 do
    now = count_start + step * 0.03
    m:OnIntervalThink()
    peak_live = math.max(peak_live, #m.laser_particles)
end
assert(#control_writes == 0 and #control_entities == #particles * 3)
assert(#particles == 251 and peak_live <= 2, "visual replay drifted from its 0.12-second cadence")
assert(#damage == 31, "beam following accelerated the thirty-second damage schedule")
print(string.format("LASER_FOLLOW_CALLS seconds=30 create=%d destroy=%d bind=%d setcp=%d peak_live=%d",
    #particles, #destroyed, #control_entities, #control_writes, peak_live))
m:OnDestroy()
assert(#destroyed == #particles, "laser segment leaked on modifier removal")
for id = 1, #particles do assert(particle_releases[id] == 1) end

-- A model without an attack socket still follows its body. With no sockets,
-- keep the legacy configured heights and update only the unsupported end.
clear()
tower.ScriptLookupAttachment = function(_, name) return name == "attach_hitloc" and 5 or 0 end
dummy.ScriptLookupAttachment = nil
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
assert(#control_entities == 2 and control_entities[1].point == "attach_hitloc")
assert(#control_writes == 1 and control_writes[1].cp == 1
    and control_writes[1].position.z == dummy.position.z + beam.target_offset_z)
dummy.position = vector(275, 90, 50)
now = now + 0.03
m:OnIntervalThink()
assert(#control_writes == 2 and control_writes[2].cp == 1
    and control_writes[2].position.z == 120)
m:OnDestroy()
tower.ScriptLookupAttachment = nil
second.ScriptLookupAttachment = nil
tower.position = vector(0, 0, 0)
dummy.position = vector(150, 0, 0)

-- Optional engine visuals cannot suspend the real laser's damage clock.
local particle_api = {}
for name, method in pairs(ParticleManager) do particle_api[name] = method end
local function restore_particle_api()
    for name, method in pairs(particle_api) do ParticleManager[name] = method end
end
clear()
tower.ScriptLookupAttachment, dummy.ScriptLookupAttachment = attachment_lookup, attachment_lookup
ParticleManager.CreateParticle = function() error("injected CreateParticle failure") end
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
now = now + 1
m:OnIntervalThink()
assert(#damage == 2 and #m.laser_particles == 0 and #particles == 0,
    "particle creation failure blocked the damage clock")
restore_particle_api()
now = now + 0.12
m:OnIntervalThink()
assert(#m.laser_particles == 1 and #damage == 2, "visual retry reset damage timing")
m:OnDestroy()

-- Failure of only CP0 must not overwrite the successfully bound CP9 source.
clear()
ParticleManager.SetParticleControlEnt = function(self, id, cp, ...)
    if cp == 0 then error("injected CP0 attachment failure") end
    return particle_api.SetParticleControlEnt(self, id, cp, ...)
end
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
assert(m.laser_particles[1].source9_follows and not m.laser_particles[1].source0_follows)
now = now + 0.03
m:OnIntervalThink()
assert(#control_writes == 2 and control_writes[1].cp == 0 and control_writes[2].cp == 0,
    "fallback for a failed CP overwrote a working attachment")
ParticleManager.SetParticleControl = function() error("injected fallback update failure") end
now = now + 0.03
m:OnIntervalThink()
assert(#m.laser_particles == 0 and particle_releases[1] == 1,
    "failed fallback update stranded its particle")
restore_particle_api()
m:OnDestroy()

-- Failed binding AND fallback must roll back an already registered handle.
clear()
ParticleManager.SetParticleControlEnt = function()
    assert(#m.laser_particles == 1, "particle was not owned before binding")
    error("injected attachment failure")
end
ParticleManager.SetParticleControl = function() error("injected fallback binding failure") end
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
assert(#damage == 1 and #m.laser_particles == 0 and #particles == 1)
assert(immediate_destroys[1] == true and particle_releases[1] == 1)
now = now + 1
m:OnIntervalThink()
assert(#damage == 2 and #m.laser_particles == 0,
    "CP binding failure suspended subsequent damage ticks")
assert(#destroyed == #particles, "binding rollback leaked a particle")
restore_particle_api()
m:OnDestroy()

-- Destroy and Release errors are independent, including expiration during a
-- damage tick. Remaining IDs still receive exactly one cleanup attempt.
clear()
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
now = now + 0.12
m:OnIntervalThink()
assert(#m.laser_particles == 2)
ParticleManager.DestroyParticle = function(self, id, immediate)
    particle_api.DestroyParticle(self, id, immediate)
    if id == 1 then error("injected DestroyParticle failure") end
end
ParticleManager.ReleaseParticleIndex = function(self, id)
    particle_api.ReleaseParticleIndex(self, id)
    if id == 2 then error("injected ReleaseParticleIndex failure") end
end
now = now + 0.88
m:OnIntervalThink()
assert(#damage == 2 and particle_releases[1] == 1 and particle_releases[2] == 1)
m:OnDestroy()
assert(#m.laser_particles == 0 and #destroyed == #particles)
for id = 1, #particles do assert(particle_releases[id] == 1) end
restore_particle_api()
clear()
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
now = now + 0.12
m:OnIntervalThink()
ParticleManager.DestroyParticle = function(self, id, immediate)
    assert(#m.laser_particles == 0, "terminal cleanup retained particle ownership")
    particle_api.DestroyParticle(self, id, immediate)
    if id == 1 then error("injected terminal destroy failure") end
end
ParticleManager.ReleaseParticleIndex = function(self, id)
    particle_api.ReleaseParticleIndex(self, id)
    if id == 1 then error("injected terminal release failure") end
end
m:OnDestroy()
assert(#destroyed == 2 and particle_releases[1] == 1 and particle_releases[2] == 1,
    "one cleanup failure prevented release or cleanup of the remaining ID")
restore_particle_api()
tower.ScriptLookupAttachment, dummy.ScriptLookupAttachment = nil, nil

-- Production continuous beams create once and remain owned well beyond the
-- original native 0.7-second lifespan; all movement comes from attachments.
beam.beam_mode = "continuous"
clear()
tower.ScriptLookupAttachment, dummy.ScriptLookupAttachment = attachment_lookup, attachment_lookup
second.ScriptLookupAttachment = attachment_lookup
tower.attack_target = dummy
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
local continuous_start = now
for step = 1, 3000 do
    now = continuous_start + step * 0.03
    dummy.position = vector(150 + step % 200, step % 80, 0)
    m:OnIntervalThink()
end
assert(#particles == 1 and #destroyed == 0 and #control_entities == 3 and #control_writes == 0,
    "continuous beam was replayed or its native attachments were overwritten")
assert(#m.laser_particles == 1 and m.laser_particles[1].expires_at == math.huge)
assert(#damage == 91, "continuous resource changed the ninety-second damage clock")
assert(damage[1].base_damage == 100 and damage[2].base_damage == 105)
m:OnAttackStart({ attacker = tower, target = dummy })
assert(#particles == 1 and #damage == 91, "same-target attack restarted a continuous beam")
print(string.format("LASER_CONTINUOUS_CALLS seconds=90 create=%d destroy=%d bind=%d setcp=%d ticks=%d",
    #particles, #destroyed, #control_entities, #control_writes, #damage))
tower.attack_target = second
m:OnAttackStart({ attacker = tower, target = second })
assert(#particles == 2 and particle_releases[1] == 1 and #m.laser_particles == 1)
assert(#damage == 92 and damage[92].base_damage == 100)
m:ResetAfterRelocation()
m:OnDestroy()
assert(particle_releases[2] == 1 and #m.laser_particles == 0 and m.laser_next_visual_retry == nil,
    "continuous relocation cleanup retained a handle or retry deadline")

-- Persistent effects must recover on the same target after a visual failure,
-- while repeated failures stay throttled and never delay a real damage tick.
clear()
tower.attack_target = dummy
dummy.position = vector(150, 0, 0)
local attempts = 0
ParticleManager.CreateParticle = function()
    attempts = attempts + 1
    error("injected persistent creation failure")
end
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
local retry_start = now
for step = 1, 40 do
    now = retry_start + step * 0.03
    m:OnIntervalThink()
end
assert(attempts == 3 and #damage == 2 and #m.laser_particles == 0,
    "continuous visual retries ran each think or interrupted the damage clock")
restore_particle_api()
now = retry_start + 1.6
m:OnIntervalThink()
assert(#particles == 1 and #m.laser_particles == 1 and #damage == 2,
    "same-target continuous beam did not recover without resetting damage")
now = retry_start + 2.01
m:OnIntervalThink()
assert(#particles == 1 and #damage == 3 and math.abs(damage[3].base_damage - 110) < 0.00001)
m:OnDeath({ attacker = second, unit = dummy })
assert(m.laser_target == nil and #m.laser_particles == 0 and particle_releases[1] == 1)
now = retry_start + 3
m:OnIntervalThink()
assert(#particles == 1 and #damage == 3, "dead-target continuous beam was resurrected by retry")

-- Failure during a fallback coordinate update also recovers through that
-- bounded retry path; the successfully bound source is never overwritten.
clear()
dummy.ScriptLookupAttachment = nil
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
ParticleManager.SetParticleControl = function() error("injected persistent fallback failure") end
now = now + 0.03
m:OnIntervalThink()
assert(#m.laser_particles == 0 and particle_releases[1] == 1)
restore_particle_api()
dummy.ScriptLookupAttachment = attachment_lookup
now = now + 0.5
m:OnIntervalThink()
assert(#particles == 2 and #m.laser_particles == 1 and #damage == 1)
assert(m.laser_particles[1].source_follows and m.laser_particles[1].target_follows)
m:OnDestroy()
assert(particle_releases[1] == 1 and particle_releases[2] == 1)
tower.ScriptLookupAttachment, dummy.ScriptLookupAttachment, second.ScriptLookupAttachment = nil, nil, nil

-- Production head-surface path: one persistent beam, moving head endpoint,
-- tier color, independent damage clock and pose cleanup after relocation.
clear()
beam.target_surface = true
beam.source_orb = true
tower.ScriptLookupAttachment = attachment_lookup
dummy.ScriptLookupAttachment = function(_, name) return name == "attach_head" and 7 or 0 end
dummy.GetAttachmentOrigin = function(self) return self.position + vector(0, 0, 96) end
dummy.GetHullRadius = function() return 24 end
local pose_destroyed, pose_created = 0, 0
tower.AddNewModifier = function(_, _, _, name)
    assert(name == "modifier_tower_laser_pose")
    pose_created = pose_created + 1
    return { IsNull = function() return false end, Destroy = function() pose_destroyed = pose_destroyed + 1 end }
end
tower.attack_target = dummy
dummy.position = vector(150, 0, 0)
m = modifier({ laser })
m:OnAttackStart({ attacker = tower, target = dummy })
assert(#particles == 2 and #control_entities == 1 and particle_releases[2] == 1)
assert(control_entities[1].cp == 7 and control_entities[1].owner == dummy,
    "electric arcs must bind the enemy model independently of the head endpoint")
assert(control_writes[1].cp == 9 and control_writes[1].position.z == tower.position.z + 185,
    "beam must originate at the orb, never the attack attachment")
assert(control_writes[3].cp == 1 and control_writes[3].position.z == 96
    and control_writes[3].position.x == 138, "beam must stop on the near head surface")
assert(control_writes[4].cp == 2 and control_writes[4].position.x == beam.color_r)
local surface_start = now
for step = 1, 100 do
    now = surface_start + step * 0.03
    dummy.position = vector(150 + step, 0, 0)
    m:OnIntervalThink()
end
assert(#particles == 5 and #damage == 4 and #control_entities == 1)
local last_head
for _, write in ipairs(control_writes) do
    if write.id == 1 and write.cp == 1 then last_head = write.position end
end
assert(last_head.x == 238)
local upgraded = require("config/generated/tower_laser_effects").by_id["laser_lv03:default"]
local prior_key, prior_red = beam.effect_key, beam.color_r
beam.effect_key, beam.color_r = upgraded.effect_key, upgraded.color_r
now = now + 0.03
m:OnIntervalThink()
local recolored = false
for _, write in ipairs(control_writes) do
    if write.id == 1 and write.cp == 2 and write.position.x == upgraded.color_r then recolored = true end
end
assert(recolored and #particles == 5 and #damage == 4, "upgrade must recolor without replay/reset")
beam.effect_key, beam.color_r = prior_key, prior_red
-- A kill followed by idle acquisition and a new enemy must retain the SAME
-- pose; no brief native attack animation and no AddNewModifier replay.
m:OnDeath({ unit = dummy, attacker = tower })
tower.attack_target = nil
now = now + 0.03
m:OnIntervalThink()
assert(pose_created == 1 and pose_destroyed == 0 and m.laser_pose)
tower.attack_target = second
m:OnAttackStart({ attacker = tower, target = second })
assert(pose_created == 1 and pose_destroyed == 0)
assert(control_entities[#control_entities].cp == 7 and control_entities[#control_entities].owner == second,
    "target switch must bind arcs to the new enemy")
assert(particle_releases[1] == 1, "old beam and all its electric children must be released on death")
m:ResetAfterRelocation()
assert(pose_destroyed == 0, "relocation should preserve the charging pose")
m:OnDestroy()
assert(particle_releases[1] == 1 and pose_destroyed == 1)
beam.target_surface = false
beam.source_orb = false
tower.AddNewModifier, tower.ScriptLookupAttachment = nil, nil
dummy.ScriptLookupAttachment, dummy.GetAttachmentOrigin, dummy.GetHullRadius = nil, nil, nil

-- Lethal damage synchronously invokes death/removal before Deal returns.
-- The new finite tail must use pre-hit snapshots and never delay the next hit.
clear()
beam.target_surface, beam.source_orb = true, true
tower.attack_target = dummy
m = modifier({laser})
local service = package.loaded["combat/damage_service"]
local original_deal = service.Deal
local old_null, old_origin = dummy.IsNull, dummy.GetAbsOrigin
service.Deal = function(self, payload)
    local result = original_deal(self, payload)
    if payload.victim == dummy then
        dummy.alive = false
        m:OnDeath({unit=dummy,attacker=tower})
        dummy.IsNull = function() return true end
        dummy.GetAbsOrigin = function() error("removed corpse must not be read") end
    end
    return result
end
m:OnAttackStart({attacker=tower,target=dummy})
assert(#damage == 1 and #scheduled == 0 and m.laser_target == nil)
assert(#particles == 3 and particles[2].path:find("laser_afterglow.vpcf",1,true)
    and particles[2].owner == nil and particle_releases[2] == 1 and immediate_destroys[2] == nil,
    "same-frame kill must keep an independent finite tail alive")
assert(immediate_destroys[1] == true and particle_releases[1] == 1)
local tail_end
for _, write in ipairs(control_writes) do if write.id == 2 and write.cp == 1 then tail_end = write.position end end
assert(tail_end and tail_end.x < dummy.position.x and tail_end.z == dummy.position.z + beam.target_offset_z)
m:OnDeath({unit=dummy,attacker=tower})
assert(#particles == 3, "duplicate death must not replay the residue")
tower.attack_target = second
m:OnAttackStart({attacker=tower,target=second})
assert(#damage == 2 and m.laser_target == second and #scheduled == 0,
    "visual residue must never delay the next target's immediate hit")
m:OnDestroy()
assert(immediate_destroys[2] == nil and particle_releases[2] == 1,
    "live beam cleanup must not swallow the released finite tail")
service.Deal = original_deal
dummy.IsNull, dummy.GetAbsOrigin, dummy.alive = old_null, old_origin, true
beam.target_surface, beam.source_orb = false, false

-- Legal bounty hits still award gold once; a queued hit must recheck its target.

-- Production native Tinker: two overlapping pulses, no Io/Zeus CPs, a
-- same-frame kill retains the actual native effect, without a timer or damage delay.
clear()
for key,value in pairs(production_beam) do beam[key] = value end
tower.attack_target = dummy
m = modifier({laser})
local native_start = now
m:OnAttackStart({attacker=tower,target=dummy})
for step=1,100 do now=native_start+step*0.03; m:OnIntervalThink() end
assert(#damage == 4 and #m.laser_particles <= 3 and #m.laser_particles >= 1)
assert(#control_entities == 0 and #scheduled == 0)
for _, write in ipairs(control_writes) do assert(write.cp ~= 7, "native Q must not bind custom Zeus arcs") end
local tail_id = m.laser_particles[#m.laser_particles].index
assert(particles[tail_id].path == production_beam.particle_name)
m:OnDeath({unit=dummy,attacker=tower})
assert(m.laser_target == nil and #m.laser_particles == 0 and #m.laser_native_residue == 1)
assert(particle_releases[tail_id] == nil, "death must not swallow the latest native pulse")
m:OnDeath({unit=dummy,attacker=tower})
assert(#m.laser_native_residue == 1)
tower.attack_target = second
m:OnAttackStart({attacker=tower,target=second})
assert(#damage == 5 and #scheduled == 0, "residue must not defer next target's first hit")
now=now+0.31; m:OnIntervalThink()
assert(particle_releases[tail_id] == 1 and #m.laser_native_residue == 0)
-- With no live target the same existing think still expires a one-shot kill.
m:OnDeath({unit=second,attacker=tower})
assert(#m.laser_native_residue == 1)
tower.attack_target=nil
now=now+0.31; m:OnIntervalThink()
assert(#m.laser_native_residue == 0)
m:OnDestroy()

clear()
m = modifier({ bounty, gatling })
assert(effects._fire_machine_gun_hit_for_test(m, tower, dummy, 1))
assert(#damage == 1 and count_request(events.RESOURCE_ADD_REQUEST) == 1)
assert(count_event(events.TOWER_ATTACK_LANDED) == 1 and m.gatling_target_hits == 1)
clear()
m = modifier({ { skill_id = "machine_gun_lv01", barrage_interval = 0.1, max_targets = 3 }, bounty })
m:OnAttack({ attacker = tower, target = dummy })
assert(#scheduled > 0, "machine-gun regression did not exercise a pending hit")
local damage_before = #damage
local rewards_before = count_request(events.RESOURCE_ADD_REQUEST)
dummy.name = "enemy_tree"
drain()
assert(#damage == damage_before and count_request(events.RESOURCE_ADD_REQUEST) == rewards_before)
dummy.name = "npc_dota_training_dummy"

-- Real configuration: one cosmetic projectile per damage hit (6/7/8/8/8),
-- one gesture per burst, unchanged hit clock and every-hit gold rewards.
do
    local skills = require("config/generated/tower_skill_definitions")
    local buff_service = package.loaded["systems/buff_manager"]
    local old_value = buff_service.value
    tower.survival_model_asset_id = "test_native_stage"
    for _, speed_bonus in ipairs({0, 100}) do
        buff_service.value = function() return speed_bonus end
        for level, hits in ipairs({6, 7, 8, 8, 8}) do
            clear()
            local skill = skills.by_id[string.format("machine_gun_lv%02d", level)]
            assert(skill.max_targets == hits)
            local burst = modifier({skill, bounty})
            local started = now
            burst:OnAttackStart({attacker=tower, target=dummy})
            assert(#gestures == 0, "windup must not add a second burst gesture")
            burst:OnAttack({attacker=tower, target=dummy})
            assert(#damage == 1 and #tracking == 1 and #gestures == 1)
            local step = 1
            while #scheduled > 0 do
                local task = table.remove(scheduled, 1)
                assert(not task.cancelled and not task.repeating)
                local interval = skill.barrage_interval / (1 + speed_bonus / 100)
                assert(math.abs(task.delay - interval) < 0.000001)
                now = now + task.delay
                task.callback()
                step = step + 1
                assert(step <= hits and #damage == step and #tracking == step)
            end
            assert(step == hits and #gestures == 1 and #native_attacks == 0)
            assert(count_request(events.RESOURCE_ADD_REQUEST) == hits)
            assert(count_event(events.TOWER_ATTACK_LANDED) == hits)
            assert(math.abs(now - started - (hits - 1) * skill.barrage_interval
                / (1 + speed_bonus / 100)) < 0.000001)
            for _, hit in ipairs(damage) do assert(hit.base_damage == 100) end
            for _, request in ipairs(requested) do
                if request.event == events.RESOURCE_ADD_REQUEST then
                    assert(request.payload.gold == bounty.damage_multiplier)
                end
            end
            for _, shot in ipairs(tracking) do
                assert(shot.Source == tower and shot.Target == dummy)
                assert(shot.Ability == nil and shot.bIsAttack == false)
                assert(shot.EffectName == "particles/units/heroes/hero_sniper/sniper_base_attack.vpcf")
            end
            local guns, coins = 0, 0
            for _, cue in ipairs(sounds) do
                if cue == "tower_machine_gun" then guns = guns + 1 end
                if cue == "tower_bounty_machine_gun" then coins = coins + 1 end
            end
            assert(guns == hits and coins == 1, "gun per shot, coin feedback once per burst")
            assert(#gold_numbers == 1 and gold_numbers[1].owner == tower
                and gold_numbers[1].amount == hits * bounty.damage_multiplier,
                "round popup must count every successful gold grant exactly once")
            assert(#particles == 1 and particles[1].owner == tower)
            assert(particles[1].path == "particles/generic_gameplay/lasthit_coins.vpcf")
            assert(particle_releases[1] == 1 and #destroyed == 0)
            local center
            for _, write in ipairs(control_writes) do
                if write.id == 1 and write.cp == 1 then center = write.position end
            end
            assert(center and center.x == tower.position.x and center.y == tower.position.y
                and center.z > tower.position.z + 100, "native coin CP1 must sit over tower head")
            burst:OnDestroy()
        end
    end
    buff_service.value = old_value
    tower.survival_model_asset_id = nil

    -- The first and second victims die during one round. Remaining configured
    -- shots must continue at the enemy nearest the wall, with one animation.
    clear()
    tower.survival_model_asset_id = "test_native_stage"
    local saved_building_system = package.loaded["systems/building_system"]
    package.loaded["systems/building_system"] = {wall_for_player=function(id)
        assert(id==0)
        return unit(90,"building_wall",600,2)
    end}
    local out_of_range = unit(91,"npc_survival_wave_monster",650)
    candidates = {tree, dummy, second, out_of_range, third}
    local combat = package.loaded["combat/damage_service"]
    local saved_deal = combat.Deal
    combat.Deal = function(self, payload)
        local result = saved_deal(self, payload)
        if payload.victim == dummy or payload.victim == third then payload.victim.alive=false end
        return result
    end
    local chain = modifier({skills.by_id.machine_gun_lv03, bounty})
    local chain_started = now
    chain:OnAttack({attacker=tower,target=dummy})
    for shot=2,8 do
        local task = assert(table.remove(scheduled,1), "kill must retain the remaining configured hits")
        assert(math.abs(task.delay-skills.by_id.machine_gun_lv03.barrage_interval)<0.000001)
        now = now + task.delay
        task.callback()
        assert(#damage==shot)
    end
    assert(#scheduled==0, "handoff must not create an additional burst")
    assert(#damage == 8 and #tracking == 8 and #gestures == 1)
    assert(damage[1].victim==dummy and damage[2].victim==third and damage[3].victim==second,
        "burst handoff must use wall proximity, while rejecting the closer-to-wall out-of-range enemy")
    assert(math.abs(now-chain_started-7*skills.by_id.machine_gun_lv03.barrage_interval)<0.000001)
    for _,hit in ipairs(damage) do assert(hit.base_damage==100) end
    assert(count_request(events.RESOURCE_ADD_REQUEST)==8)
    assert(#gold_numbers==1 and gold_numbers[1].amount==8*bounty.damage_multiplier)
    chain:OnDestroy()
    assert(#gold_numbers==1, "cleanup must not duplicate paid-gold popup")
    combat.Deal=saved_deal
    dummy.alive,third.alive=true,true
    package.loaded["systems/building_system"] = saved_building_system
    tower.survival_model_asset_id=nil

    -- Broken presentation cannot consume damage, gold, or cancel later hits.
    clear()
    local create_shot, create_coin = ProjectileManager.CreateTrackingProjectile, ParticleManager.CreateParticle
    ProjectileManager.CreateTrackingProjectile = function() error("injected projectile failure") end
    ParticleManager.CreateParticle = function() error("injected coin failure") end
    local burst = modifier({skills.by_id.machine_gun_lv01, bounty})
    burst:OnAttack({attacker=tower, target=dummy})
    drain()
    assert(#damage == 6 and count_request(events.RESOURCE_ADD_REQUEST) == 6)
    burst:OnDestroy()
    ProjectileManager.CreateTrackingProjectile, ParticleManager.CreateParticle = create_shot, create_coin

    -- A lethal first hit still launches its projectile before damage is applied.
    clear()
    local combat = package.loaded["combat/damage_service"]
    local old_deal = combat.Deal
    combat.Deal = function(self, payload)
        assert(#tracking == 1, "lethal hit must not swallow its projectile")
        local result = old_deal(self, payload)
        dummy.alive = false
        return result
    end
    burst = modifier({skills.by_id.machine_gun_lv01, bounty})
    burst:OnAttack({attacker=tower, target=dummy})
    drain()
    assert(#damage == 1 and #tracking == 1 and count_request(events.RESOURCE_ADD_REQUEST) == 1)
    assert(#gold_numbers == 1 and gold_numbers[1].amount == bounty.damage_multiplier,
        "lethal hit without another target must display only the partial round's earned gold")
    burst:OnDestroy()
    combat.Deal, dummy.alive = old_deal, true

    for _, case in ipairs({
        {"critical_strike_lv01", "tower_death_attack"},
        {"frost_attack_lv01", "tower_frost_launch"},
        {"anti_air_missile_lv01", "tower_anti_air_attack"},
    }) do
        clear()
        local attack = modifier({{skill_id=case[1]}})
        attack:OnAttack({attacker=tower, target=dummy})
        assert(#sounds == 1 and sounds[1] == case[2], "native attack launch cue missing")
        attack:OnDestroy()
    end
    print("MACHINE_GUN_FEEDBACK_PASS: 5 levels, 2 speeds, hit timing/damage/gold, 6-8 projectiles, one gesture, coins, failure and lethal hits")
end

-- Flying classifications cannot let a resource tree into the anti-air burst
-- or ensnare. A target that changes before the scheduled missile is rechecked.
clear()
local missile = { skill_id = "anti_air_missile_lv01", max_targets = 3 }
local drag = { skill_id = "drag_net_lv01", trigger_chance_pct = 100 }
m = modifier({ missile })
tree.survival_movement_type = "flying"
effects._start_anti_air_sequence_for_test(m, tower, tree, missile)
assert(effects._trigger_drag_net_for_test(tower, tree, drag) == false)
assert(#scheduled == 0)
no_effects("flying tree")
dummy.survival_movement_type = "flying"
effects._start_anti_air_sequence_for_test(m, tower, dummy, missile)
assert(#scheduled > 0)
dummy.name = "enemy_tree"
drain()
assert(#native_attacks == 0)
dummy.name = "npc_dota_training_dummy"
effects._start_anti_air_sequence_for_test(m, tower, dummy, missile)
drain()
assert(#native_attacks > 0)
dummy.survival_movement_type = nil
tree.survival_movement_type = nil

-- Anti-air missiles also retain their scheduled extra shots after a kill,
-- using wall priority while ignoring ground enemies and resource trees.
clear()
tower.survival_tower_class = "class_7"
dummy.survival_movement_type, third.survival_movement_type, fourth.survival_movement_type = "flying", "flying", "flying"
local saved_building_system = package.loaded["systems/building_system"]
package.loaded["systems/building_system"] = {wall_for_player=function() return unit(90,"building_wall",600,2) end}
candidates = {tree, second, third, fourth}
m = modifier({missile})
effects._start_anti_air_sequence_for_test(m, tower, dummy, missile)
dummy.alive = false
drain()
assert(#native_attacks == missile.max_targets - 1)
for _, target in ipairs(native_attacks) do assert(target == fourth, "missile handoff must use wall priority") end
dummy.alive = true
dummy.survival_movement_type, third.survival_movement_type, fourth.survival_movement_type = nil, nil, nil
package.loaded["systems/building_system"] = saved_building_system
tower.survival_tower_class = nil

-- Every real airborne hit rolls its own configured chance. Ensnare belongs to
-- its visible skill, lasts two seconds, and never adds stun or extra damage.
clear()
local net_skills = require("config/generated/tower_skill_definitions")
local chances = { 2, 3, 4, 5, 5 }
local original_roll = RollPercentage
local rolled
RollPercentage = function(chance) rolled = chance; return true end
for level, chance in ipairs(chances) do
    local skill = net_skills.by_id[string.format("drag_net_lv%02d", level)]
    dummy.survival_movement_type = nil
    rolled = nil
    assert(not effects._trigger_drag_net_for_test(tower, dummy, skill))
    assert(rolled == nil, "ground targets must not roll ensnare")
    dummy.survival_movement_type = "flying"
    assert(effects._trigger_drag_net_for_test(tower, dummy, skill))
    assert(rolled == chance)
    local applied = buffs[#buffs]
    assert(applied.name == "modifier_tower_drag_net")
    assert(applied.caster == tower and applied.ability == ability)
    assert(applied.options.duration == 2)
end
local applied_count = #buffs
RollPercentage = function() return false end
assert(not effects._trigger_drag_net_for_test(tower, dummy, drag))
assert(#buffs == applied_count and #damage == 0 and #scheduled == 0)
RollPercentage = original_roll
dummy.survival_movement_type = nil

-- Three secondary arrows go to actual enemies despite a tree in first place.
-- Without Script_GetAttackRange, the real GetAttackRange fallback still works.
clear()
local saved_getter = tower.Script_GetAttackRange
tower.Script_GetAttackRange = nil
m = modifier({ { skill_id = "multi_attack_lv01", max_targets = 4, damage_multiplier = 1 } })
candidates = { tree, dummy, second, third, fourth }
m:OnAttack({ attacker = tower, target = dummy })
assert(last_radius == 600 and #tracking == 3)
assert(tracking[1].Target == second and tracking[2].Target == third and tracking[3].Target == fourth)
second.name = "enemy_tree"
drain()
assert(#damage == 2 and damage[1].victim == third and damage[2].victim == fourth)
second.name = "npc_survival_wave_monster"
tower.Script_GetAttackRange = saved_getter

-- The Clinkz SR outfit uses its chosen searing arrow for all five levels, while
-- the existing tracking speed, split count, delay, damage and armor ignore stay.
local ballista_asset_id = "tower_multi_drow_dread_retribution"
local real_catalog = assert(loadfile("scripts/vscripts/config/asset_catalog.lua"))()
local ballista_asset = real_catalog.by_id[ballista_asset_id]
local ballista_path = "particles/units/heroes/hero_clinkz/clinkz_searing_arrow.vpcf"
assert(ballista_asset.attack.projectile == ballista_path)
local preloaded = false
for _, path in ipairs(ballista_asset.particle_resources) do
    if path == ballista_path then preloaded = true end
end
assert(preloaded, "ballista tracking art must be in the asset preload bundle")
local mock_catalog = require("config/asset_catalog")
mock_catalog.by_id[ballista_asset_id] = ballista_asset
local route = require("config/generated/tower_class_multi")
local skills = require("config/generated/tower_skill_definitions")
local saved_asset = tower.survival_model_asset_id
for level = 1, 5 do
    clear()
    local id = string.format("piercing_ballista_lv%02d", level)
    assert(route.by_id[id].projectile_model == ballista_path)
    tower.survival_model_asset_id = ballista_asset_id
    local multi = skills.by_id.multi_attack_lv05
    m = modifier({ multi, skills.by_id[id] })
    candidates = { tree, dummy, second, third, fourth }
    m:OnAttack({ attacker = tower, target = dummy })
    assert(#tracking == 4 and #scheduled == 4 and #damage == 0)
    for i, projectile in ipairs(tracking) do
        assert(projectile.EffectName == ballista_path and projectile.iMoveSpeed == 1250)
        assert(projectile.Ability == nil and projectile.bDodgeable == false)
        local expected_delay = (projectile.Target:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D() / 1250
        assert(math.abs(scheduled[i].delay - expected_delay) < 1e-9)
    end
    drain()
    assert(#damage == 4)
    for _, hit in ipairs(damage) do
        assert(hit.physical_armor_ignore_pct == skills.by_id[id].attack_armor_reduction)
        local expected_damage = 100 * require("systems/tower_multi_damage").multiplier(multi, hit.victim)
        assert(hit.base_damage == expected_damage)
    end
end
tower.survival_model_asset_id = saved_asset
mock_catalog.by_id[ballista_asset_id] = nil

-- A tree cannot consume a lightning bounce slot. A dead primary must still
-- supply its final location for normal lethal-hit splash/chain behavior.
clear()
m = modifier({ { skill_id = "lightning_strike_lv01", max_targets = 3, area = 300 } })
candidates = { tree, dummy, second, third }
dummy.alive = false
m:OnAttackLanded({ attacker = tower, target = dummy })
drain()
assert(#damage == 2 and damage[1].victim == second and damage[2].victim == third)
assert(#particles == 3 and count_event(events.TOWER_ATTACK_LANDED) == 1)
dummy.alive = true

-- Frost splash/slow share the query filter and reject a tree primary before
-- creating its point particle or applying any debuff.
clear()
local frost = { skill_id = "frost_attack_lv01", damage_multiplier = 0.5, area = 300, buff_id = "frost" }
candidates = { tree, dummy, second }
effects._trigger_frost_attack_for_test(tower, tree, frost, 100)
no_effects("tree frost primary")
effects._trigger_frost_attack_for_test(tower, dummy, frost, 100)
assert(#particles == 1 and #damage == 1 and damage[1].victim == second and #buffs == 2)

-- Lightning-storm area damage emits hit events only for its real enemies;
-- its independent ground-area visual is allowed to continue.
clear()
m = modifier({})
candidates = { tree, dummy, second }
effects._start_lightning_storm_for_test(tower, vector(0, 0, 0), {
    skill_id = "lightning_storm_lv01", strike_count = 2, duration = 1,
    damage_multiplier = 1, area = 300,
})
assert(#damage == 2 and count_event(events.TOWER_LIGHTNING_HIT) == 2)
for _, hit in ipairs(emitted) do assert(hit.payload.target ~= tree) end
drain()

-- PA blood is a hit effect, not a critical-roll effect. Five tiers retain 5x
-- damage, lethal hits can emit it, and native world snapshots own their tail.
local blood_path = "particles/units/heroes/hero_phantom_assassin/phantom_assassin_crit_impact.vpcf"
for level = 1, 5 do
    for _, lethal in ipairs({ false, true }) do
        clear()
        dummy.alive = true
        local critical = skills.by_id[string.format("critical_strike_lv%02d", level)]
        m = modifier({ critical })
        m:OnAttackStart({ attacker = tower, target = dummy })
        assert(m:GetModifierPreAttack_CriticalStrike() == 500)
        assert(#particles == 0, "rolling a critical must not emit blood before impact")
        dummy.alive = not lethal
        m:OnAttackLanded({ attacker = tower, target = dummy, damage = 500 })
        assert(#particles == 1 and particles[1].path == blood_path and particles[1].owner == nil)
        assert(#control_entities == 0 and #control_writes == 2)
        assert(control_writes[1].position.z == dummy.position.z + 60)
        assert(control_writes[2].cp == 1)
        local direction = particles[1].orientations[1].forward
        assert(direction.x * (tower.position.x - dummy.position.x)
            + direction.y * (tower.position.y - dummy.position.y) > 0)
        assert(particle_releases[1] == 1 and #destroyed == 0 and #scheduled == 0)
        assert(#damage == 0 and count_event(events.TOWER_ATTACK_LANDED) == 1)
        for _, event in ipairs(emitted) do
            if event.event == events.TOWER_ATTACK_LANDED then
                assert(event.payload.damage == 500 and event.payload.critical_multiplier == 5)
            end
        end
        dummy.alive = true
    end
end
clear()
m = modifier({ skills.by_id.critical_strike_lv01 })
m:OnAttackStart({ attacker = tower, target = dummy })
m:OnAttackFail({ attacker = tower, target = dummy })
assert(#particles == 0, "misses must not spray blood")
subscribers[events.TOWER_ATTACK_LANDED]({ tower = tower, target = dummy, critical = false,
    critical_source = "critical_strike", skills = {} })
assert(#particles == 0, "normal hits must not spray blood")
subscribers[events.TOWER_ATTACK_LANDED]({ tower = tower, target = dummy, critical = true,
    critical_source = "research_critical", skills = {} })
assert(#particles == 0, "unrelated tower critical sources retain their visuals")
subscribers[events.TOWER_ATTACK_LANDED]({ tower = tower, target = dummy, critical = true,
    critical_source = "bone_cannon", skills = {} })
assert(#particles == 1 and particles[1].path == blood_path, "advanced bone criticals also spray blood")

-- Special event consumers also reject tree primaries (including externally
-- emitted events) before counters, criticals or area visuals can run.
clear()
local bone = { skill_id = "bone_cannon_lv01", trigger_attack_count = 2 }
local eye = { skill_id = "arcane_eye_lv01", damage_multiplier = 0.3, area = 300 }
local diffusion = { skill_id = "lightning_diffusion_lv01", trigger_chance_pct = 100, damage_multiplier = 2 }
local burning = { skill_id = "burning_great_arrow_lv01", damage_multiplier = 3.24 }
local payload = { tower = tower, target = tree, damage = 100, critical = true,
    critical_source = "bone_cannon", source = "lightning_storm", can_trigger_diffusion = true,
    skills = { bone, eye, diffusion, burning } }
subscribers[events.TOWER_ATTACK_START](payload)
subscribers[events.TOWER_ATTACK_LANDED](payload)
subscribers[events.TOWER_LASER_HIT](payload)
subscribers[events.TOWER_LIGHTNING_HIT](payload)
no_effects("special events tree")
local critical_payload = { tower = tower, target = dummy, skills = { bone } }
subscribers[events.TOWER_ATTACK_LANDED]({ tower = tower, target = dummy, skills = { bone } })
assert(handlers[events.TOWER_CRITICAL_QUERY](critical_payload) == nil, "tree advanced bone counter")
subscribers[events.TOWER_ATTACK_LANDED]({ tower = tower, target = dummy, skills = { bone } })
assert(handlers[events.TOWER_CRITICAL_QUERY]({ tower = tower, target = tree, skills = { bone } }) == nil)
assert(handlers[events.TOWER_CRITICAL_QUERY](critical_payload).multiplier_pct == 1000,
    "tree critical query consumed a pending legal critical")

-- Arcane-eye splash and lightning diffusion preserve normal damage while
-- skipping trees returned by an independent area query.
clear()
candidates = { tree, dummy, second }
payload.target = dummy
subscribers[events.TOWER_LASER_HIT](payload)
assert(#damage == 1 and damage[1].victim == second and damage[1].base_damage == 30)
subscribers[events.TOWER_LIGHTNING_HIT](payload)
assert(#damage == 2 and damage[2].victim == second and damage[2].base_damage == 200)
assert(#particles == 1)

-- A penetrating wave may physically contact a tree, but its hit count,
-- penetration decay and deduplication only advance for valid enemy hits.
clear()
subscribers[events.TOWER_ATTACK_START]({ tower = tower, target = dummy, skills = { burning } })
assert(#linear == 1)
local extra = linear[1].ExtraData
assert(special.on_burning_wave_projectile_hit(ability, tree, nil, extra) == false)
assert(#damage == 0)
assert(special.on_burning_wave_projectile_hit(ability, dummy, nil, extra) == false)
assert(special.on_burning_wave_projectile_hit(ability, dummy, nil, extra) == false)
assert(special.on_burning_wave_projectile_hit(ability, tree, nil, extra) == false)
assert(special.on_burning_wave_projectile_hit(ability, second, nil, extra) == false)
assert(#damage == 2 and math.abs(damage[1].base_damage - 324) < 0.0001
    and math.abs(damage[2].base_damage - 259.2) < 0.0001,
    "tree contact consumed a penetration slot or duplicate hit caused damage")
drain()
-- Display rarity is independent of inherited skill rank and the route CSV's
-- legacy rarity. Exercise real modifier particle selection across every tier.
local selector = require("systems/tower_laser_effect_selector")
local rarity_paths = {
    R = "particles/units/heroes/hero_tinker/tinker_laser.vpcf",
    SR = "particles/econ/items/tinker/tinker_ti10_immortal_laser/tinker_ti10_immortal_laser.vpcf",
    SSR = "particles/econ/items/tinker/tinker_ti10_immortal_laser/tinker_ti10_immortal_laser_aghs.vpcf",
}
for level = 6, 25 do
    clear()
    tower.survival_level = level
    local rarity = level <= 10 and "R" or (level <= 15 and "SR" or "SSR")
    for skill_level = 1, 5 do
        local chosen = selector.get(tower, "laser_lv0" .. skill_level)
        assert(chosen.particle_name == rarity_paths[rarity], "skin must follow displayed rarity")
        assert(math.abs(selector.width(tower, "laser_lv0" .. skill_level, chosen)
            - 1) < 0.00001,
            "all ranks retain native width")
        assert((rarity == "R" and chosen.color_b > chosen.color_r)
            or (rarity ~= "R" and chosen.color_r > chosen.color_g and chosen.color_g < 100),
            "orb colors follow the native blue/red beams; no artificial yellow")
    end
    local skill = {skill_id="laser_lv0" .. (level <= 10 and level-5 or 5),
        damage_interval=1, damage_multiplier=1}
    tower.attack_target = dummy
    m = modifier({skill})
    m:OnAttackStart({attacker=tower,target=dummy})
    assert(#damage == 1 and particles[1].path == rarity_paths[rarity])
    local widths = 0
    for _, cp in ipairs(control_writes) do
        if cp.cp == 60 then
            widths = widths + 1
            assert(math.abs(cp.position.x - 1) < 0.00001)
        end
    end
    assert(widths == 0, "native width must not receive scaling control points")
    m:OnDestroy()
end
for _, level in ipairs({6,11,16}) do
    clear(); tower.survival_level, tower.attack_target = level, dummy
    m = modifier({{skill_id="laser_lv01", damage_interval=1, damage_multiplier=1}})
    m:OnAttackStart({attacker=tower,target=dummy})
    local start, beam_id = now, m.laser_particles[1].index
    for step=1,3000 do
        now=start+step*.03; m:OnIntervalThink()
        assert(#m.laser_particles >= 1 and #m.laser_particles <= 3,
            "native one-shot overlap must stay bounded throughout the channel")
        assert(m.laser_particles[#m.laser_particles].expires_at - now >= 0.38,
            "native beam must be refreshed before its 0.7 second lifetime ends")
    end
    assert(#damage==91,"native visual replay must preserve original 90-second damage clock")
    local count=0
    for _,p in ipairs(particles) do if p.path==particles[beam_id].path then count=count+1 end end
    assert(count>=300 and count<=301,"native art is replayed at 0.3s, not per frame")
    m:OnDestroy()
end
-- A live upgrade changes the next native segment without granting an extra
-- first hit or resetting the ongoing one-second damage clock.
clear()
tower.survival_level, tower.attack_target = 10, dummy
m = modifier({{skill_id="laser_lv05", damage_interval=1, damage_multiplier=1}})
m:OnAttackStart({attacker=tower,target=dummy})
local rarity_start = now
for _, upgrade in ipairs({{11,"SR"},{16,"SSR"}}) do
    tower.survival_level = upgrade[1]
    now = now + 0.24
    m:OnIntervalThink()
    local segment = m.laser_particles[#m.laser_particles]
    assert(particles[segment.index].path == rarity_paths[upgrade[2]])
    assert(segment.width_scale == nil, "rarity switch retains native width")
    assert(#damage == 1, "cosmetic rarity change must not add damage")
end
-- A level within the same skin keeps the same beam handle and native width.
local unchanged_beam = m.laser_particles[1].index
now = now + 0.24
tower.survival_level = 17
m:OnIntervalThink()
assert(m.laser_particles[1].index == unchanged_beam and m.laser_particles[1].width_scale == nil)
assert(#damage == 1, "same-rarity upgrade must not reset damage clock")
assert(math.abs(m.laser_elapsed - (now-rarity_start)) < 0.001)
m:OnDestroy()
tower.survival_level = nil
local lightning_fx = require("config/generated/tower_lightning_effects").by_id
for level = 6, 25 do
    clear()
    tower.survival_level = level
    local expected = level <= 10 and "particles/units/heroes/hero_zuus/zuus_arc_lightning.vpcf"
        or (level <= 15 and lightning_fx.SR.particle_name or lightning_fx.SSR.particle_name)
    m = modifier({{skill_id="lightning_strike_lv05", max_targets=3, area=300}})
    candidates = {dummy, second, third}
    m:OnAttackLanded({attacker=tower,target=dummy})
    drain()
    assert(#damage==2 and damage[1].victim==second and damage[2].victim==third,
        "rarity must not change chain targets or damage count")
    assert(damage[1].base_damage==90 and damage[2].base_damage==80,
        "native skin must preserve 10% per-bounce decay")
    local chains, impacts = 0, 0
    for _, particle in ipairs(particles) do
        if particle.path==expected then chains=chains+1 end
        if particle.path==lightning_fx.SSR.impact_particle then impacts=impacts+1 end
    end
    assert(chains==3 and impacts==0 and #particles==3, "no extra golden hit particles")
    if level>=16 then
        assert(expected=="particles/survival/towers/trial/lightning_ssr_arc.vpcf",
            "third-stage attacks and bounces use the native white-blue thick variant, never gold")
    end
    m:OnDestroy()
end
clear()
effects._start_lightning_storm_for_test(tower, vector(0,0,0), {
    skill_id="lightning_storm_lv01",strike_count=2,duration=1,damage_multiplier=1,area=300})
local before_storm_damage=#damage
drain()
local storms=0
for id, p in ipairs(particles) do
    if p.path==lightning_fx.strike.particle_name then
        storms=storms+1
        assert(particle_releases[id]==1 and immediate_destroys[id]==false,
            "storm completion must stop emission and allow native endcap fade")
        local radius, duration
        for _,cp in ipairs(control_writes) do
            if cp.id==id and cp.cp==1 then radius=cp.position.x end
            if cp.id==id and cp.cp==2 then duration=cp.position.x end
        end
        assert(radius==300 and duration==1, "tower visual must use its actual skill radius/duration")
    end
end
assert(storms==1 and #particles==1 and #damage==before_storm_damage,
    "one full storm replaces all random falling bolts without extra damage")
tower.survival_level=nil
-- Winter's Curse presentation keeps all four damage waves and their old clock.
local blizzard_visual = require("systems/wyvern_blizzard_visual")
local blizzard_skills = require("config/generated/tower_skill_definitions").by_id
local effect_rows = require("config/generated/asset_effects").rows
for _, row in ipairs(effect_rows) do
    if row.skill_id and row.skill_id:match("^ice_blizzard_lv") then
        assert(row.effect_role ~= "skill_chain", "old falling shards must be removed")
        assert(row.particle_path == (row.effect_role == "skill_strike"
            and blizzard_visual.GROUND or blizzard_visual.SNOW))
    end
end
local scheduler_mock = package.loaded["core/scheduler"]
local original_every, original_after = scheduler_mock.every, scheduler_mock.after
-- Simulate the production scheduler's 50ms think; no time accumulator shortcut.
local function timed_blizzard(level, cancel_at)
    clear()
    now = 0
    tower.alive = true
    candidates = {dummy}
    local tasks, hit_times = {}, {}
    scheduler_mock.every = function(delay, callback)
        tasks[#tasks + 1] = {delay=delay, at=now+delay, callback=callback}
    end
    scheduler_mock.after = function(delay, callback)
        tasks[#tasks + 1] = {delay=delay, at=now+delay, callback=function() callback(); return false end}
    end
    effects._start_blizzard_for_test(tower, vector(90,80,0), blizzard_skills["ice_blizzard_lv0" .. level])
    assert(#particles == 2 and #damage == 0, "field and snow start before first damage")
    assert(particles[1].path == blizzard_visual.GROUND and particles[2].path == blizzard_visual.SNOW)
    assert(particles[1].owner == nil and particles[2].owner == nil, "field survives the trigger target")
    local ground_radius, snow_radius
    for _, cp in ipairs(control_writes) do
        if cp.id == 1 and cp.cp == 2 then ground_radius = cp.position.x end
        if cp.id == 2 and cp.cp == 1 then snow_radius = cp.position.x end
    end
    assert(ground_radius == 300 and snow_radius == 300)
    for frame = 1, 120 do
        now = frame * 0.05
        if cancel_at and now >= cancel_at then tower.alive = false end
        if not cancel_at and now < 5 then assert(#destroyed == 0, "storm must remain visible for five seconds") end
        local due = {}
        for _, task in ipairs(tasks) do
            if task.at and task.at <= now + 0.0000001 then due[#due + 1] = task end
        end
        for _, task in ipairs(due) do
            local before = #damage
            local again = task.callback()
            task.at = again ~= false and now + task.delay or nil
            if #damage > before then hit_times[#hit_times + 1] = now end
        end
    end
    if cancel_at then
        assert(#damage == 0, "dead caster cancels pending damage")
    else
        assert(#damage == 4 and #buffs == 4 and last_radius == 300)
        for i, hit in ipairs(damage) do
            assert(hit.base_damage == 50 and hit.victim == dummy, "four 50% waves unchanged")
            assert(math.abs(hit_times[i] - (i + 0.6)) < 0.001, "old fall clock must be preserved")
            assert(buffs[i].options.duration == 1.1)
        end
    end
    assert(#destroyed == 2 and particle_releases[1] == 1 and particle_releases[2] == 1)
    assert(#control_writes == 4, "snowfall must not need per-frame particle updates")
    blizzard_visual.clear()
    assert(#destroyed == 2, "completion must be idempotent")
    tower.alive = true
    scheduler_mock.every, scheduler_mock.after = original_every, original_after
end
for level = 1, 5 do timed_blizzard(level) end
timed_blizzard(1, 1.2)
clear()
local first = blizzard_visual.play(vector(0,0,0), 300)
local second_field = blizzard_visual.play(vector(500,0,0), 300)
blizzard_visual.finish(first)
assert(#destroyed == 2, "overlapping fields have independent ownership")
blizzard_visual.clear()
assert(#destroyed == 4 and particle_releases[4] == 1, "session clear removes active fields")
clear()
local create_blizzard_particle = ParticleManager.CreateParticle
ParticleManager.CreateParticle = function(self, name, attach, owner)
    if name == blizzard_visual.SNOW then error("injected snow failure") end
    return create_blizzard_particle(self, name, attach, owner)
end
candidates = {dummy}
effects._start_blizzard_for_test(tower, vector(0,0,0), blizzard_skills.ice_blizzard_lv01)
drain()
assert(#damage == 4 and #destroyed == 1 and particle_releases[1] == 1,
    "optional snow failure must clean the first root and preserve combat")
ParticleManager.CreateParticle = create_blizzard_particle
print("TOWER_SKILL_TREE_EXCLUSION_PASS: native visuals, blizzard five levels/timing/damage/cleanup")
