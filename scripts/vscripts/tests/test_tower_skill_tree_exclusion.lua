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
        AddNewModifier = function(_, _, _, _, options)
            buffs[#buffs + 1] = { options = options }
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
assert(beam.beam_mode == "continuous" and beam.particle_name == "particles/survival/towers/laser_beam.vpcf",
    "production laser CSV must select the persistent beam resource")
-- Retain the existing segmented-mode regressions as a supported fallback.
-- The production continuous contract is exercised separately below.
beam.beam_mode = "segmented"
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

-- Legal bounty hits still award gold once; a queued hit must recheck its target.
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

-- Flying classifications cannot let a resource tree into the anti-air burst
-- or stun. A target that changes before the scheduled missile is rechecked.
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
print("TOWER_SKILL_TREE_EXCLUSION_PASS")
