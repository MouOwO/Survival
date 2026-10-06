-- Execute the actual moving-ice-ball runner and simulation with engine mocks.
-- Assert the fixed-birth-size Tusk root and unchanged gameplay/control inputs.
-- Native radius interpolation is checked separately in the compiled particle;
-- these mocks do not render or prove the model's visible size over time.
package.path = "scripts/vscripts/?.lua;" .. package.path
local definition = assert(require("config/hero_passive_skill_definitions").by_id.proto_frost_nova)
local file = assert(io.open("scripts/vscripts/systems/hero_passive_skill_service.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function between(first_text, last_text)
    local first = assert(source:find(first_text, 1, true), first_text)
    local last = assert(source:find(last_text, first + #first_text, true), last_text)
    return source:sub(first, last - 1)
end
local seam = table.concat({
    "local active_moving_ice_balls = {}; local moving_ice_ball_sequence = 0; local moving_ice_ball_task = nil; local ARCANE_MAX_HULL_RADIUS = 256",
    between("local MOVING_ICE_BALL_PARTICLE =", "local METEOR_FALL_PARTICLE ="),
    between("local MOVING_ICE_BALL_EXPLOSION_PARTICLE =", "local magic_slingshot_visual ="),
    between("local function valid(unit)", "function arcane_snapfire_visual.release_particle(particle)"),
    between("local function level_value(definition, field, level, fallback)", "local function owned_passives(player_id)"),
    between("local function enemies_in_radius(attacker, position, radius)", "local function line_targets(attacker, origin, direction, length, width)"),
    between("local function is_enemy(attacker, target)", "local function magic_slingshot_targets("),
    between("local function moving_ice_ball_point_segment_distance_sq(point, start_position, end_position)", "local function fury_thunder_visual(context, position, radius, target)"),
    "return {run = run_frost, states = active_moving_ice_balls, release = release_moving_ice_ball, clear = clear_moving_ice_balls}",
}, "\n")

local vector_meta = {}
vector_meta.__index = vector_meta
local function vector(x, y, z) return setmetatable({x = x, y = y, z = z}, vector_meta) end
function vector_meta:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
function vector_meta:Normalized()
    local length = self:Length2D()
    return vector(self.x / length, self.y / length, self.z / length)
end
vector_meta.__add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector_meta.__sub = function(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector_meta.__mul = function(a, b) return vector(a.x * b, a.y * b, a.z * b) end
local function near(a, b) return math.abs(a - b) < 0.000001 end
local function same_position(a, b) return near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z) end
local function contains(items, target)
    for _, item in ipairs(items) do if item == target then return true end end
    return false
end
local snowball_path = "particles/survival/skills/tusk_snowball_fixed_size.vpcf"
local explosion_path = "particles/units/heroes/hero_tusk/tusk_snowball_impact.vpcf"

local function harness(level, visual_failure)
    local h = {now = 0, tasks = {}, particles = {}, groups = {}, world = {}, searches = {}, errors = {}, pick = 1}
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
    function h.unit(id, x, y)
        local unit = {position = vector(x, y, 0), living = true, team = 3, hull = 0}
        unit.IsNull = function(self) return self.null == true end
        unit.IsAlive = function(self) return self.living end
        unit.entindex = function() return id end
        unit.GetAbsOrigin = function(self) return self.position end
        unit.GetTeamNumber = function(self) return self.team end
        unit.GetHullRadius = function(self) return self.hull end
        h.world[#h.world + 1] = unit
        return unit
    end
    h.attacker = {
        IsNull = function(self) return self.null == true end,
        GetAbsOrigin = function() return vector(0, 0, 0) end,
        GetTeamNumber = function() return 2 end,
    }
    h.primary = h.unit(1, 1000, 0)
    h.context = {attacker = h.attacker, target = h.primary, level = level, skill_id = "proto_frost_nova"}
    local manager = {}
    function manager:CreateParticle(path, attach, owner)
        assert(path == snowball_path or path == explosion_path,
            "use the Tusk root with fixed birth scale and the original native impact")
        assert(attach == 0 and owner == h.attacker)
        if path == snowball_path and (visual_failure == "create" or visual_failure == "impact_control") then
            error("injected snowball creation failure")
        end
        h.particles[#h.particles + 1] = {
            path = path, controls = {}, forwards = {}, writes = {}, destroys = 0, releases = 0,
        }
        return #h.particles - 1 -- Zero is a valid engine particle index.
    end
    function manager:SetParticleControl(index, control, value)
        local particle = assert(h.particles[index + 1])
        if particle.path == snowball_path and (visual_failure == "control"
            or visual_failure == "sync" and h.now > 0) then error("injected snowball control failure") end
        if particle.path == explosion_path and visual_failure == "impact_control" then error("injected impact control failure") end
        particle.controls[control] = vector(value.x, value.y, value.z)
        particle.writes[control] = (particle.writes[control] or 0) + 1
    end
    function manager:SetParticleControlForward(index, control, value)
        assert(control == 0, "Tusk orientation must use CP0")
        h.particles[index + 1].forwards[control] = vector(value.x, value.y, value.z)
    end
    function manager:DestroyParticle(index, immediate)
        local particle = assert(h.particles[index + 1])
        particle.destroys = particle.destroys + 1
        particle.immediate = immediate
        particle.destroyed_at = h.now
        if particle.path == snowball_path and visual_failure == "destroy" then error("injected snowball destroy failure") end
    end
    function manager:ReleaseParticleIndex(index)
        local particle = assert(h.particles[index + 1])
        particle.releases = particle.releases + 1
    end
    local env = setmetatable({
        Vector = vector, ParticleManager = manager, PATTACH_WORLDORIGIN = 0,
        GameRules = {GetGameTime = function() return h.now end},
        GetGroundPosition = function(position) return vector(position.x, position.y, 0) end,
        DOTA_UNIT_TARGET_TEAM_ENEMY = 1, DOTA_UNIT_TARGET_HERO = 2, DOTA_UNIT_TARGET_BASIC = 4,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 8, FIND_CLOSEST = 0, FIND_ANY_ORDER = 1,
        FindUnitsInRadius = function(team, position, _, radius, target_team, target_type, flags, order)
            assert(team == 2 and target_team == 1 and target_type == 6 and flags == 8)
            h.searches[#h.searches + 1] = {position = vector(position.x, position.y, position.z), radius = radius, order = order}
            if order == 1 then
                h.last_area = {position = vector(position.x, position.y, position.z), radius = radius - 256}
            end
            local result = {}
            for _, unit in ipairs(h.world) do
                if unit.team ~= team and (unit.position - position):Length2D() <= radius then result[#result + 1] = unit end
            end
            return result
        end,
        RandomInt = function(low, high) assert(low == 1 and h.pick <= high); return h.pick end,
        scheduler = {after = enqueue, cancel = function(id) h.tasks[id] = nil end},
        M = {sound_service = {play = function() end}},
        deal_group = function(context, targets, multiplier, secondary)
            assert(context == h.context and secondary == true)
            h.groups[#h.groups + 1] = {
                at = h.now, multiplier = multiplier, targets = targets,
                position = h.last_area.position, radius = h.last_area.radius,
            }
        end,
        print = function(message) h.errors[#h.errors + 1] = message end,
    }, {__index = _G})
    local chunk = assert(loadstring(seam, "@frost_tusk_snowball_regression"))
    setfenv(chunk, env)
    h.service = chunk()
    function h.cast() return h.service.run(h.context, definition) end
    return h
end

local function assert_visual(h, state, particle)
    assert(particle.path == snowball_path)
    assert(same_position(assert(particle.controls[0]), vector(0, 0, 0)),
        "native CP0 is the spawn position and must not be used as a custom motion carrier")
    local destination = state.target_death_position or state.end_position
    if state.homing and state.target.living then destination = state.target.position end
    assert(same_position(assert(particle.controls[1]), destination), "native CP1 attracts the snowball toward its current destination")
    assert(same_position(assert(particle.controls[2]), vector(state.move_speed, 0, 0)), "CP2 must use the actual movement speed")
    assert(same_position(assert(particle.controls[3]), vector(state.radius, state.radius, state.radius)),
        "native CP3 receives the configured radius for the model and snow layers")
    assert(particle.writes[0] == 1 and particle.writes[2] == 1 and particle.writes[3] == 1,
        "spawn, speed and configured radius are initialized once; Lua must not animate size during movement")
    assert(particle.controls[4] == nil and particle.controls[5] == nil and next(particle.forwards) == nil,
        "the native root owns its carrier controls and facing")
end

for level = 1, 4 do
    local h = harness(level)
    local victim = h.unit(2, 180, 250)
    local outside = h.unit(3, 180, 400)
    assert(h.cast())
    local state = assert(h.service.states[1])
    local particle = h.particles[1]
    assert(state.particle == 0, "snowball particle index zero must remain valid")
    assert(state.radius == (level <= 2 and 300 or 350))
    assert(state.move_speed == (level == 1 and 360 or 540))
    assert_visual(h, state, particle)
    assert(#h.groups == 0, "casting must not deal an immediate periodic tick")
    h.advance(0.49)
    assert(#h.groups == 0, "the first damage tick must wait half a second")
    h.advance(0.5)
    assert(near(state.position.x, state.move_speed * 0.5) and state.position.y == 0,
        "straight movement speed must remain unchanged")
    assert_visual(h, state, particle)
    assert(particle.writes[1] > 1, "the native attractor must synchronize every movement step")
    assert(#h.groups == 1 and near(h.groups[1].at, 0.5) and h.groups[1].multiplier == 2)
    assert(contains(h.groups[1].targets, victim) and not contains(h.groups[1].targets, outside),
        "periodic damage must retain the configured ground radius")
    local fixed_endpoint = vector(state.end_position.x, state.end_position.y, state.end_position.z)
    h.primary.position = vector(1000, 600, 0)
    h.advance(0.6)
    assert(state.direction.y == 0 and same_position(state.end_position, fixed_endpoint),
        "levels one through four must retain the original straight endpoint")
    h.advance(4)
    assert(next(h.service.states) == nil, "a completed ball must leave no simulation state")
    assert(particle.destroys == 1 and particle.releases == 1 and particle.immediate == false,
        "finish must trigger the native shattering endcaps exactly once")
    assert(state.particle == nil)
    assert(#h.particles == 1 and same_position(particle.controls[1], state.position),
        "native root endcaps must shatter at the stop point without duplicate generic impacts")
    for _, group in ipairs(h.groups) do assert(group.radius == state.radius) end
    if level >= 3 then
        assert(h.groups[#h.groups].multiplier == 3, "level three and four must retain finish explosion damage")
    else
        for _, group in ipairs(h.groups) do assert(group.multiplier == 2, "early levels must have periodic damage only") end
    end
    assert(#h.errors == 0)
end

-- Roll well beyond the native 1.5-second growth interval. This checks that
-- gameplay and Lua CP3 stay fixed; the compiled-root audit checks interpolation.
for level = 1, 5 do
    local h = harness(level)
    h.primary.position = vector(5000, 0, 0)
    assert(h.cast())
    local state, particle = assert(h.service.states[1]), h.particles[1]
    local radius, speed = state.radius, state.move_speed
    assert(radius == (level <= 2 and 300 or 350))
    for _, time in ipairs({0.5, 1.5, 3}) do
        h.advance(time)
        assert(h.service.states[1] == state and particle.destroys == 0)
        assert(state.radius == radius and near(state.position.x, speed * time),
            "a long roll must preserve the configured damage radius and movement speed")
        assert_visual(h, state, particle)
        assert(particle.writes[3] == 1, "long rolls never rewrite the native size control")
    end
    assert(#h.groups == 6, "periodic damage keeps its half-second cadence through a long roll")
    for _, group in ipairs(h.groups) do assert(group.radius == radius) end
    h.service.clear()
    assert(particle.destroys == 1 and particle.releases == 1 and particle.immediate == true)
    assert(#h.particles == 1 and #h.errors == 0)
end

-- An unrelated enemy stops the ball at the earliest swept contact, including
-- hull size. Search iteration order must not select a farther enemy first.
for _, level in ipairs({1, 2, 3, 4, 5}) do
    local collisions = harness(level)
    collisions.primary.position = vector(5000, 0, 0)
    collisions.unit(100, 230, 0)
    local blocker = collisions.unit(101, 200, 0)
    blocker.hull = 24
    local friend = collisions.unit(102, 10, 0)
    friend.team = 2
    local corpse = collisions.unit(103, 10, 0)
    corpse.living = false
    assert(collisions.cast())
    local state = collisions.service.states[1]
    collisions.advance(0.2)
    assert(next(collisions.service.states) == nil and near(state.position.x, 48)
        and near(state.distance_travelled, 48), "first enemy contact must stop at hull + collision width")
    assert(state.target == collisions.primary and state.collided["101"] == true
        and not state.collided["100"], "any enemy can stop the ball before the selected target")
    assert(collisions.particles[1].immediate == false and collisions.particles[1].destroys == 1
        and collisions.particles[1].releases == 1, "the first collision plays native shattering once")
    assert(#collisions.groups == (level >= 3 and 1 or 0), "early collision does not invent periodic damage")
    if level >= 3 then
        assert(collisions.groups[1].multiplier == 3 and contains(collisions.groups[1].targets, blocker))
        assert(near(collisions.groups[1].position.x, 48))
    end
    collisions.advance(3)
    assert(collisions.particles[1].destroys == 1 and next(collisions.tasks) == nil)
    assert(#collisions.errors == 0)
end

-- Contact between think endpoints must not tunnel even if speed is increased.
do
    local swept = harness(3)
    local blocker = swept.unit(2, 400, 120)
    blocker.hull = 10
    assert(swept.cast())
    local state = swept.service.states[1]
    state.move_speed = 20000
    swept.advance(0.05)
    local contact_x = 400 - math.sqrt(138 * 138 - 120 * 120)
    assert(next(swept.service.states) == nil and near(state.position.x, contact_x),
        "swept circle collision must find the entry point, not the segment projection or endpoint")
    assert(near(state.distance_travelled, contact_x) and #swept.groups == 1)
end

do
    local overlapping = harness(3)
    overlapping.unit(2, 100, 0)
    assert(overlapping.cast())
    local state = overlapping.service.states[1]
    overlapping.advance(0.05)
    assert(next(overlapping.service.states) == nil and state.distance_travelled == 0
        and state.position.x == 0, "an enemy already touching the spawn must shatter the ball without movement")
    assert(#overlapping.groups == 1 and overlapping.groups[1].multiplier == 3)
end

local homing = harness(5)
local selected = homing.unit(2, 1000, 1000)
homing.pick = 2
assert(homing.cast())
local homing_state = homing.service.states[1]
assert(homing_state.target == selected and homing_state.max_distance == 1500,
    "level five must preserve random selection and the fifty-percent travel increase")
assert(homing.searches[1].radius == 1500)
homing.advance(0.25)
assert(near(homing_state.distance_travelled, 135) and near(homing_state.direction.x, homing_state.direction.y))
selected.position = vector(800, 1000, 0)
homing.advance(0.3)
assert(homing_state.direction.y > homing_state.direction.x, "a live target's motion must change the homing direction")
assert_visual(homing, homing_state, homing.particles[1])
homing.advance(0.5)
assert(#homing.groups == 1 and near(homing.groups[1].multiplier, 2.4),
    "level-five distance bonus must count each full hundred units traveled")
selected.position = vector(300, 700, 0)
selected.living = false
homing.advance(0.55)
local death_position = vector(300, 700, 0)
assert(same_position(homing_state.target_death_position, death_position))
selected.position = vector(9999, 9999, 0)
local death_victim = homing.unit(3, 300, 700)
homing.advance(3)
assert(next(homing.service.states) == nil and near((homing_state.position - death_position):Length2D(), 128),
    "a dead target keeps its fixed destination, but an intervening enemy still causes immediate shattering")
assert(homing_state.target == selected and same_position(homing_state.target_death_position, death_position))
assert(homing.groups[#homing.groups].multiplier == 3 and contains(homing.groups[#homing.groups].targets, death_victim))
assert(homing.particles[1].destroys == 1 and homing.particles[1].releases == 1)
assert(#homing.errors == 0)

local exhausted = harness(5)
assert(exhausted.cast())
local exhausted_state = exhausted.service.states[1]
exhausted.primary.position = vector(2500, 0, 0)
exhausted.advance(4)
assert(next(exhausted.service.states) == nil and near(exhausted_state.distance_travelled, 1500)
    and near(exhausted_state.position.x, 1500), "homing must stop at its fixed maximum travel distance")
assert(exhausted.groups[#exhausted.groups].multiplier == 3)

local independent = harness(1)
assert(independent.cast() and independent.cast())
local remaining = independent.service.states[2]
independent.service.release(1, false)
assert(independent.particles[1].destroys == 1 and independent.particles[1].releases == 1)
assert(independent.service.states[1] == nil and remaining.particle == 1)
independent.advance(0.25)
assert(near(remaining.position.x, 90) and independent.particles[2].destroys == 0,
    "releasing particle zero must not stop an independent ball")
assert_visual(independent, remaining, independent.particles[2])
independent.service.clear()
assert(next(independent.service.states) == nil and next(independent.tasks) == nil)
assert(independent.particles[2].destroys == 1 and independent.particles[2].releases == 1)
assert(#independent.particles == 2, "clearing balls must not create damage explosions")

for _, failure in ipairs({"create", "control", "sync"}) do
    local broken = harness(1, failure)
    assert(broken.cast(), "visual setup failure must not prevent movement and damage")
    local broken_state = broken.service.states[1]
    broken.advance(0.5)
    assert(near(broken_state.position.x, 180) and #broken.groups == 1 and broken.groups[1].multiplier == 2)
    assert(broken_state.particle == nil and #broken.errors == 1)
    if failure == "control" or failure == "sync" then
        assert(broken.particles[1].destroys == 1 and broken.particles[1].releases == 1 and broken.particles[1].immediate == true,
            "a partially initialized index-zero particle must be released")
    else
        assert(#broken.particles == 0)
    end
    broken.service.clear()
end

for _, failure in ipairs({"create", "control", "sync", "destroy", "impact_control"}) do
    local h = harness(3, failure)
    assert(h.cast())
    h.advance(3)
    assert(next(h.service.states) == nil and next(h.tasks) == nil)
    assert(h.groups[#h.groups].multiplier == 3, "all visual failures preserve final explosion damage")
    for _, particle in ipairs(h.particles) do
        assert(particle.releases == 1, "partial setup, sync and destroy errors must still release handles once")
        if particle.path == explosion_path and failure ~= "impact_control" then
            assert(same_position(particle.controls[0], particle.controls[1]), "fallback native impact must use its actual CP1 emitter")
        end
    end
    assert(#h.errors >= 1)
end

print("FROST_TUSK_SNOWBALL_PASS: fixed-birth-size Tusk root with native endcaps; unchanged CP2 speed and CP3 radius through 3-second rolls; any-enemy swept contact, periodic/final damage, level5 tracking/death/travel, index0 and failure cleanup (native visual size not simulated)")
