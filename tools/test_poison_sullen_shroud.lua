-- Run the real stationary cloud and its natural/forced particle cleanup.
-- Engine-owned particle fading is not rendered or timed by these mocks.
package.path = "scripts/vscripts/?.lua;" .. package.path
local definition = assert(require("config/hero_passive_skill_definitions").by_id.proto_poison_cloud)
local file = assert(io.open("scripts/vscripts/systems/hero_passive_skill_service.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function between(first_text, last_text)
    local first = assert(source:find(first_text, 1, true), first_text)
    local last = assert(source:find(last_text, first + #first_text, true), last_text)
    return source:sub(first, last - 1)
end
local seam = table.concat({
    "local active_poison_clouds = {}; local poison_cloud_sequence = 0; local poison_cloud_units = {}; local poison_cloud_deaths = {}; local poison_cloud_task = nil; local ARCANE_MAX_HULL_RADIUS = 256",
    between("local POISON_CLOUD_PARTICLE =", "local blade_pulse_visual ="),
    between("local function valid(unit)", "function arcane_snapfire_visual.release_particle(particle)"),
    between("local function level_value(definition, field, level, fallback)", "local function owned_passives(player_id)"),
    between("local function enemies_in_radius(attacker, position, radius)", "local function normalized_direction(origin, destination, fallback)"),
    between("local function poison_cloud_contains(cloud, target, require_alive)", "local function periodic_on_target(context, target, duration, interval, multiplier, finish, refresh_existing)"),
    between("local function run_poison(context, definition)", "function blade_pulse_visual.release(state, immediate)"),
    "return {run = run_poison, states = active_poison_clouds, release = release_poison_cloud, clear = clear_poison_clouds, death = on_poison_cloud_death}",
}, "\n")

local vector_meta = {}
vector_meta.__index = vector_meta
local function vector(x, y, z) return setmetatable({x = x, y = y, z = z}, vector_meta) end
function vector_meta:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
vector_meta.__sub = function(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
local function near(a, b) return math.abs(a - b) < 0.000001 end
local function same_position(a, b) return near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z) end
local function contains(items, target)
    for _, item in ipairs(items) do if item == target then return true end end
    return false
end
local aura_path = "particles/survival/skills/poison_sullen_shroud.vpcf"
local burst_path = "particles/basic_explosion/basic_explosion.vpcf"
local modifier_name = "modifier_hero_poison_cloud_armor"
local ground_center = vector(100, 200, 0)

local function harness(level, visual_failure)
    local h = {now = 0, tasks = {}, particles = {}, groups = {}, world = {}, errors = {}, sounds = {}, events = {},
        cleanup_failures = {}}
    local task_sequence = 0
    local function enqueue(delay, callback, task_id)
        task_sequence = task_sequence + 1
        task_id = task_id or ("test_task_" .. task_sequence)
        h.tasks[task_id] = {at = h.now + delay, callback = callback}
        return task_id
    end
    function h.advance(until_time)
        while true do
            local next_id, next_task
            for id, task in pairs(h.tasks) do
                if not next_task or task.at < next_task.at then next_id, next_task = id, task end
            end
            if not next_task or next_task.at > until_time + 0.0000001 then break end
            h.tasks[next_id] = nil
            h.now = next_task.at
            local delay = next_task.callback()
            if type(delay) == "number" and delay >= 0 then enqueue(delay, next_task.callback, next_id) end
        end
        h.now = until_time
    end
    function h.unit(id, x, y, team)
        local unit = {position = vector(x, y, 99), living = true, team = team or 3, hull = 0}
        unit.IsNull = function(self) return self.null == true end
        unit.IsAlive = function(self) return self.living end
        unit.entindex = function() return id end
        unit.GetAbsOrigin = function(self) return self.position end
        unit.GetTeamNumber = function(self) return self.team end
        unit.GetHullRadius = function(self) return self.hull end
        unit.FindModifierByName = function(self, name) assert(name == modifier_name); return self.modifier end
        unit.AddNewModifier = function(self, caster, ability, name, parameters)
            assert(caster == self and ability == nil and name == modifier_name)
            local modifier = {destroyed = false}
            modifier.IsNull = function(actual) return actual.destroyed end
            modifier.SetPoisonValues = function(actual, values)
                actual.stacks = values.poison_stacks
                actual.per_stack_pct = values.armor_per_stack_pct
            end
            modifier.Destroy = function(actual) actual.destroyed = true; self.modifier = nil end
            modifier:SetPoisonValues(parameters)
            self.modifier = modifier
            return modifier
        end
        h.world[#h.world + 1] = unit
        return unit
    end
    h.attacker = h.unit(100, 0, 0, 2)
    h.primary = h.unit(1, ground_center.x, ground_center.y)
    h.context = {attacker = h.attacker, target = h.primary, level = level, skill_id = "proto_poison_cloud"}
    local manager = {}
    function manager:CreateParticle(path, attach, owner)
        assert(path == aura_path or path == burst_path, "retired Viper cloud particles must not be created")
        assert(attach == 0 and owner:GetTeamNumber() == 2, "the aura must use a world-origin particle")
        if path == aura_path and visual_failure == "create" then error("injected shroud creation failure") end
        h.particles[#h.particles + 1] = {path = path, owner = owner, at = h.now,
            controls = {}, writes = {}, destroys = 0, releases = 0}
        return #h.particles - 1 -- Particle zero must be cleaned up as an ordinary handle.
    end
    function manager:SetParticleControl(index, control, value)
        local particle = assert(h.particles[index + 1])
        assert(control == 0 or control == 1, "the stationary aura must only use CP0 and CP1")
        if particle.path == aura_path and visual_failure == "control" then error("injected shroud control failure") end
        particle.controls[control] = vector(value.x, value.y, value.z)
        particle.writes[control] = (particle.writes[control] or 0) + 1
    end
    function manager:DestroyParticle(index, immediate)
        local particle = assert(h.particles[index + 1])
        assert(type(immediate) == "boolean")
        for _, cloud in pairs(h.service and h.service.states or {}) do
            assert(cloud.particle ~= index,
                "detach gameplay and its particle handle before calling fallible cleanup APIs")
        end
        particle.destroys = particle.destroys + 1
        particle.immediate = immediate
        particle.destroyed_at = h.now
        h.events[#h.events + 1] = {kind = "destroy", index = index, at = h.now}
        if particle.path == aura_path and (visual_failure == "destroy" or visual_failure == "cleanup")
            and not h.cleanup_failures.destroy then
            h.cleanup_failures.destroy = true
            error("injected shroud destroy failure")
        end
    end
    function manager:ReleaseParticleIndex(index)
        local particle = assert(h.particles[index + 1])
        particle.releases = particle.releases + 1
        particle.released_at = h.now
        h.events[#h.events + 1] = {kind = "release", index = index, at = h.now}
        if particle.path == aura_path and (visual_failure == "release" or visual_failure == "cleanup")
            and not h.cleanup_failures.release then
            h.cleanup_failures.release = true
            error("injected shroud release failure")
        end
    end
    local env = setmetatable({
        Vector = vector, ParticleManager = manager, PATTACH_WORLDORIGIN = 0,
        GameRules = {GetGameTime = function() return h.now end},
        GetGroundPosition = function(position) return vector(position.x, position.y, 0) end,
        DOTA_UNIT_TARGET_TEAM_ENEMY = 1, DOTA_UNIT_TARGET_HERO = 2, DOTA_UNIT_TARGET_BASIC = 4,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 8, FIND_CLOSEST = 0, FIND_ANY_ORDER = 1,
        FindUnitsInRadius = function(team, position, _, radius, target_team, target_type, flags, order)
            assert(team == 2 and target_team == 1 and target_type == 6 and flags == 8 and order == 1)
            h.last_area = {position = vector(position.x, position.y, position.z), radius = radius - 256}
            local result = {}
            for _, unit in ipairs(h.world) do
                if unit.team ~= team and (unit.position - position):Length2D() <= radius then result[#result + 1] = unit end
            end
            return result
        end,
        scheduler = {after = enqueue, cancel = function(id) h.tasks[id] = nil end},
        M = {sound_service = {play = function(cue) h.sounds[#h.sounds + 1] = cue end}},
        deal_group = function(context, targets, multiplier, secondary)
            assert(context.skill_id == "proto_poison_cloud" and secondary == true)
            h.groups[#h.groups + 1] = {
                at = h.now, context = context, multiplier = multiplier, targets = targets,
                position = h.last_area.position, radius = h.last_area.radius,
            }
            h.events[#h.events + 1] = {kind = "damage", at = h.now}
        end,
        print = function(message) h.errors[#h.errors + 1] = message end,
    }, {__index = _G})
    local chunk = assert(loadstring(seam, "@poison_sullen_shroud_regression"))
    setfenv(chunk, env)
    h.service = chunk()
    function h.cast(context) return h.service.run(context or h.context, definition) end
    return h
end

local function assert_aura(particle)
    assert(particle.path == aura_path)
    assert(same_position(assert(particle.controls[0]), ground_center), "shroud must stay at the copied ground target location")
    assert(same_position(assert(particle.controls[1]), vector(400, 0, 0)), "shroud radius must remain 400")
    assert(particle.writes[0] == 1 and particle.writes[1] == 1 and particle.controls[2] == nil,
        "a stationary shroud must not follow a unit or receive movement controls")
end

for _, level in ipairs({1, 2, 3, 4, 5}) do
    local h = harness(level)
    local victim = h.unit(2, 120, 200)
    local outside = h.unit(3, 501, 200)
    local duration = level <= 2 and 5 or 7
    assert(h.cast())
    local cloud = assert(h.service.states["100"])
    local particle = h.particles[1]
    assert(cloud.particle == 0 and cloud.radius == 400 and cloud.total_ticks == duration)
    assert_aura(particle)
    assert(not h.cast() and #h.particles == 1 and #h.sounds == 1, "a caster must have at most one active aura")
    h.attacker.position = vector(5000, 5000, 0)
    h.primary.position = vector(6000, 6000, 0)
    h.advance(0.99)
    assert(#h.groups == 0, "casting must wait for the first whole-second damage tick")
    h.advance(1)
    assert(#h.groups == 1 and h.groups[1].multiplier == 1)
    assert(contains(h.groups[1].targets, victim) and not contains(h.groups[1].targets, outside),
        "damage must remain inside the original radius despite unit movement")
    if level >= 2 then
        assert(victim.modifier.stacks == 1 and victim.modifier.per_stack_pct == 20)
    else
        assert(victim.modifier == nil)
    end
    h.advance(3)
    if level >= 2 then assert(victim.modifier.stacks == 3 and victim.modifier.per_stack_pct == 20) end
    h.advance(duration - 0.01)
    assert(#h.groups == duration - 1 and particle.destroys == 0 and not h.cast(),
        "the aura and caster lock must survive until the final scheduled tick")
    h.advance(duration)
    assert(#h.groups == duration and h.service.states["100"] == nil)
    assert(particle.destroys == 1 and particle.releases == 1 and particle.immediate == false
        and near(particle.destroyed_at, duration) and near(particle.released_at, duration),
        "expiry stops emission once and hands the native fade to the engine at the original deadline")
    local final_damage, stop
    for index, event in ipairs(h.events) do
        if event.kind == "damage" then final_damage = index end
        if event.kind == "destroy" and event.index == 0 then stop = index end
    end
    assert(final_damage and stop and final_damage < stop,
        "the last whole-second damage tick must finish before the natural particle stop")
    assert(cloud.particle == nil and victim.modifier == nil, "expiry must clear the particle reference and armor modifier")
    assert(same_position(cloud.position, ground_center))
    assert_aura(particle)
    for index, group in ipairs(h.groups) do
        assert(near(group.at, index) and group.multiplier == 1 and group.radius == 400 and same_position(group.position, ground_center),
            "all five or seven ticks must preserve timing, damage and stationary radius")
    end
    victim.living = false
    h.service.death({victim = victim})
    assert(#h.groups == duration and #h.particles == 1,
        "an engine-owned fading shroud cannot cause additional death explosions")
    assert(h.cast(), "the caster must be able to trigger again after expiry")
    local next_particle = assert(h.particles[2])
    h.service.clear()
    assert(next(h.service.states) == nil and next(h.tasks) == nil and #h.errors == 0)
    assert(next_particle.immediate == true and next_particle.destroys == 1 and next_particle.releases == 1,
        "explicit clear still immediately removes the newly active shroud")
    h.advance(duration + 20)
    assert(#h.groups == duration and #h.particles == 2
        and particle.destroys == 1 and particle.releases == 1 and particle.immediate == false,
        "recast and clear cannot destroy, release or reuse the old engine-owned fade again")
end

local armor = harness(2)
local armor_victim = armor.unit(2, 100, 200)
assert(armor.cast())
armor.advance(1)
local prior_modifier = assert(armor_victim.modifier)
armor_victim.position = vector(600, 200, 0)
armor.advance(1.05)
assert(armor_victim.modifier == nil and prior_modifier.destroyed, "leaving the stationary cloud must remove its armor reduction")
armor_victim.position = vector(100, 200, 0)
armor.advance(2)
assert(armor_victim.modifier.stacks == 1, "reentering must start fresh armor stacks")
armor.service.clear()
assert(armor_victim.modifier == nil)

local independent = harness(1)
local other_caster = independent.unit(101, 0, 0, 2)
local other_context = {attacker = other_caster, target = independent.primary, level = 1, skill_id = "proto_poison_cloud"}
assert(independent.cast() and independent.cast(other_context))
assert(#independent.particles == 2 and independent.service.states["101"].particle == 1)
independent.service.release("100", true)
assert(independent.particles[1].destroys == 1 and independent.particles[1].releases == 1
    and independent.particles[1].immediate == true,
    "particle zero must release correctly")
independent.advance(1)
assert(#independent.groups == 1 and independent.groups[1].context == other_context
    and independent.particles[2].destroys == 0, "releasing one caster's cloud must preserve another's aura and damage")
independent.service.clear()
assert(independent.particles[2].destroys == 1 and independent.particles[2].releases == 1)

-- Natural expiry of one overlapping cloud must recalculate armor from the
-- other caster instead of retaining expired stacks or ending the other aura.
do
    local h = harness(2)
    local victim = h.unit(2, 120, 200)
    local other = h.unit(101, 0, 0, 2)
    local context = {attacker = other, target = h.primary, level = 3, skill_id = "proto_poison_cloud"}
    assert(h.cast() and h.cast(context))
    h.advance(5)
    assert(h.service.states["100"] == nil and h.service.states["101"]
        and #h.groups == 10 and victim.modifier.stacks == 3)
    assert(h.particles[1].immediate == false and h.particles[1].releases == 1
        and h.particles[2].destroys == 0 and h.particles[2].releases == 0)
    h.advance(7)
    assert(#h.groups == 12 and victim.modifier == nil and next(h.service.states) == nil
        and next(h.tasks) == nil and h.particles[2].immediate == false)
    for _, particle in ipairs(h.particles) do assert(particle.destroys == 1 and particle.releases == 1) end
end

-- Retriggering immediately after expiry creates a new gameplay cloud while
-- the old released particle has no further ownership or cleanup callbacks.
do
    local h = harness(2)
    local victim = h.unit(2, 120, 200)
    assert(h.cast())
    local old_cloud = h.service.states["100"]
    h.advance(5)
    assert(victim.modifier == nil and h.cast())
    local new_cloud = h.service.states["100"]
    assert(new_cloud ~= old_cloud and new_cloud.particle == 1 and old_cloud.particle == nil)
    h.advance(5.99)
    assert(#h.groups == 5 and victim.modifier == nil and h.service.states["100"] == new_cloud)
    h.advance(6)
    assert(#h.groups == 6 and victim.modifier.stacks == 1 and h.particles[2].destroys == 0)
    h.advance(10)
    assert(#h.groups == 10 and victim.modifier == nil and next(h.service.states) == nil and next(h.tasks) == nil)
    for _, particle in ipairs(h.particles) do
        assert(particle.immediate == false and particle.destroys == 1 and particle.releases == 1)
    end
end

-- Explicit cancellation and invalid casters immediately clean owned handles,
-- including index zero, and suppress every later damage/armor update.
for _, ending in ipairs({"clear", "invalid"}) do
    local h = harness(2)
    local victim = h.unit(2, 120, 200)
    assert(h.cast())
    local cloud = h.service.states["100"]
    h.advance(1)
    assert(#h.groups == 1 and victim.modifier.stacks == 1)
    if ending == "clear" then h.service.clear()
    else h.attacker.null = true; h.advance(1.05) end
    local particle = h.particles[1]
    assert(particle.immediate == true and particle.destroys == 1 and particle.releases == 1
        and cloud.particle == nil and victim.modifier == nil
        and next(h.service.states) == nil and next(h.tasks) == nil)
    h.advance(10)
    assert(#h.groups == 1 and particle.destroys == 1 and particle.releases == 1)
end

-- Destroy and Release are separately protected. Even when both fail, gameplay
-- ownership, armor removal, the remaining cleanup attempt and recasting survive.
for _, failure in ipairs({"destroy", "release", "cleanup"}) do
    for _, ending in ipairs({"natural", "clear", "invalid"}) do
        local h = harness(2, failure)
        local victim = h.unit(2, 120, 200)
        assert(h.cast())
        local cloud = h.service.states["100"]
        h.advance(1)
        if ending == "natural" then h.advance(5)
        elseif ending == "clear" then h.service.clear()
        else h.attacker.null = true; h.advance(1.05) end
        assert(h.cleanup_failures.destroy == (failure ~= "release" and true or nil)
            and h.cleanup_failures.release == (failure ~= "destroy" and true or nil))
        local particle = h.particles[1]
        assert(particle.destroys == 1 and particle.releases == 1
            and particle.immediate == (ending ~= "natural")
            and cloud.particle == nil and victim.modifier == nil and next(h.service.states) == nil,
            "particle API errors cannot retain gameplay state or skip the independent release attempt")
        if ending == "invalid" then h.attacker.null = false end
        local prior_damage = #h.groups
        assert(prior_damage == (ending == "natural" and 5 or 1) and h.cast())
        local new_cloud = h.service.states["100"]
        h.advance(h.now + 1)
        assert(#h.groups == prior_damage + 1 and victim.modifier.stacks == 1
            and h.service.states["100"] == new_cloud,
            "old cleanup failure cannot block or corrupt a new cloud at the same caster key")
        h.service.clear()
        assert(victim.modifier == nil and next(h.service.states) == nil and next(h.tasks) == nil
            and particle.destroys == 1 and particle.releases == 1)
    end
end

local deaths = harness(5)
local next_victim = deaths.unit(2, 200, 200)
assert(deaths.cast())
deaths.primary.living = false
deaths.service.death({victim = deaths.primary})
assert(#deaths.groups == 1 and deaths.groups[1].radius == 300 and deaths.groups[1].multiplier == 3
    and contains(deaths.groups[1].targets, next_victim), "level-five death damage must retain its 300 radius and multiplier three")
assert(#deaths.particles == 2 and deaths.particles[2].path == burst_path
    and same_position(deaths.particles[2].controls[1], vector(300, 0, 0)) and deaths.particles[2].releases == 1)
deaths.service.death({victim = deaths.primary})
assert(#deaths.groups == 1 and #deaths.particles == 2, "duplicate death events must not duplicate an explosion")
next_victim.living = false
deaths.service.death({victim = next_victim})
assert(#deaths.groups == 2 and deaths.groups[2].multiplier == 3, "a distinct subsequent death must retain chain-explosion behavior")
assert_aura(deaths.particles[1])
deaths.service.clear()

for _, failure in ipairs({"create", "control"}) do
    local broken = harness(2, failure)
    local victim = broken.unit(2, 120, 200)
    assert(broken.cast(), "a cosmetic setup failure must preserve cloud gameplay")
    broken.advance(1)
    assert(#broken.groups == 1 and broken.groups[1].multiplier == 1 and victim.modifier.stacks == 1)
    assert(broken.service.states["100"].particle == nil and #broken.errors == 1)
    if failure == "control" then
        assert(broken.particles[1].destroys == 1 and broken.particles[1].releases == 1 and broken.particles[1].immediate == true,
            "partial setup must destroy and release its index-zero particle")
    else
        assert(#broken.particles == 0)
    end
    broken.service.clear()
    assert(victim.modifier == nil and next(broken.service.states) == nil)
end

print("POISON_SULLEN_SHROUD_PASS: natural expiry soft-stops native shroud after exact5/7 ticks; radius400, armor/lock/death bounds, immediate clear/invalid, overlapping/recast isolation and independent failed cleanup; native fading not simulated")
