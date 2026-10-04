-- Execute the real moving void-effect simulation through a read-only seam.
package.path = "scripts/vscripts/?.lua;" .. package.path
local definition = assert(require("config/hero_passive_skill_definitions").by_id.proto_void_pulse)
local file = assert(io.open("scripts/vscripts/systems/hero_passive_skill_service.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function between(first_text, last_text)
    local first = assert(source:find(first_text, 1, true), first_text)
    local last = assert(source:find(last_text, first + #first_text, true), last_text)
    return source:sub(first, last - 1)
end
local seam = table.concat({
    "local active_tornadoes = {}; local tornado_sequence = 0; local tornado_task = nil; local tornado_slow_units = {}; local ARCANE_MAX_HULL_RADIUS = 256",
    between("local tornado_visual =", "local function valid(unit)"),
    between("local function valid(unit)", "function arcane_snapfire_visual.release_particle(particle)"),
    between("local function level_value(definition, field, level, fallback)", "local function owned_passives(player_id)"),
    between("local function enemies_in_radius(attacker, position, radius)", "local function line_targets(attacker, origin, direction, length, width)"),
    between("function tornado_visual.release(state)", "local runners ="),
    "return {run = run_void, states = active_tornadoes, clear = clear_tornadoes}",
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
local tornado_path = "particles/survival_tornado/survival_tornado_follow.vpcf"
local area_slow = "debuff_hero_tornado_area_slow"
local hit_slow = "debuff_hero_tornado_hit_slow"

local function harness(level, visual_failure)
    local h = {now = 0, tasks = {}, particles = {}, damage = {}, world = {}, errors = {}, attributes = 100}
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
        local unit = {position = vector(x, y, 0), living = true, team = team or 3, buffs = {}}
        unit.IsNull = function(self) return self.null == true end
        unit.IsAlive = function(self) return self.living end
        unit.entindex = function() return id end
        unit.GetAbsOrigin = function(self) return self.position end
        unit.GetTeamNumber = function(self) return self.team end
        unit.GetHullRadius = function() return 0 end
        h.world[#h.world + 1] = unit
        return unit
    end
    h.attacker = h.unit(100, 0, 0, 2)
    h.primary = h.unit(1, 100, 0)
    h.context = {attacker = h.attacker, target = h.primary, level = level, player_id = 0, skill_id = "proto_void_pulse", attributes = {all_attributes = 100}}
    local manager = {}
    function manager:CreateParticle(path, attach, owner)
        assert(path == tornado_path, "only the ordinary Invoker Tornado wrapper may render")
        assert(attach == 0 and owner == h.attacker, "the tornado must use a world-origin particle")
        if visual_failure == "create" then error("injected tornado creation failure") end
        h.particles[#h.particles + 1] = {controls = {}, writes = {}, destroys = 0, releases = 0}
        return #h.particles - 1 -- The engine can return particle index zero.
    end
    function manager:SetParticleControl(index, control, value)
        assert(control == 0 or control == 3,
            "Lua must move both native tornado birth/follow frames")
        if visual_failure == "control" then error("injected tornado control failure") end
        local particle = assert(h.particles[index + 1])
        particle.controls[control] = vector(value.x, value.y, value.z)
        particle.writes[control] = (particle.writes[control] or 0) + 1
    end
    function manager:DestroyParticle(index, immediate)
        local particle = assert(h.particles[index + 1])
        particle.destroys = particle.destroys + 1
        particle.immediate = immediate
        particle.destroyed_at = h.now
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
        FindUnitsInRadius = function(team, position, _, radius, target_team, target_type, flags)
            assert(team == 2 and target_team == 1 and target_type == 6 and flags == 8)
            local result = {}
            for _, unit in ipairs(h.world) do
                if unit.team ~= team and (unit.position - position):Length2D() <= radius then result[#result + 1] = unit end
            end
            return result
        end,
        RandomInt = function(low) return low end,
        scheduler = {after = enqueue, cancel = function(id) h.tasks[id] = nil end},
        attribute_snapshot = function() return {all_attributes = h.attributes} end,
        M = {sound_service = {play = function() end}},
        buff_manager = {
            apply = function(_, target, buff_id, options)
                assert(buff_id == area_slow or buff_id == hit_slow)
                target.buffs[buff_id] = options.value
            end,
            remove = function(target, buff_id) target.buffs[buff_id] = nil end,
        },
        deal = function(context, target, multiplier, secondary)
            assert(context == h.context)
            h.damage[#h.damage + 1] = {
                at = h.now, target = target, multiplier = multiplier, secondary = secondary,
                amount = context.attributes.all_attributes * multiplier,
            }
        end,
        print = function(message)
            if tostring(message):find("failed", 1, true) then h.errors[#h.errors + 1] = message end
        end,
    }, {__index = _G})
    local chunk = assert(loadstring(seam, "@void_tornado_regression"))
    setfenv(chunk, env)
    h.service = chunk()
    function h.cast() return h.service.run(h.context, definition) end
    return h
end

local function assert_visual(state, particle)
    assert(same_position(assert(particle.controls[0]), state.position), "tornado dust must follow its simulation state")
    assert(same_position(assert(particle.controls[3]), state.position), "the native funnel and base must follow the same center")
    assert(particle.writes[0] == particle.writes[3], "both tornado frames must move together")
    assert(particle.controls[1] == nil and particle.controls[2] == nil
        and particle.controls[20] == nil and particle.controls[21] == nil,
        "ordinary tornado visuals need no independent mover or extra aura")
end

for level = 1, 4 do
    local h = harness(level)
    local outside_core = h.unit(2, 501, 0)
    assert(h.cast())
    local state = assert(h.service.states[1])
    local particle = h.particles[1]
    assert(state.particle == 0 and state.duration == 3 and state.move_speed == 500)
    assert_visual(state, particle)
    assert(#h.damage == 1 and h.damage[1].at == 0 and h.damage[1].target == h.primary
        and h.damage[1].multiplier == 2 and h.damage[1].amount == 200 and h.damage[1].secondary == false,
        "main damage must start immediately inside the 300-radius core")
    h.advance(0.5)
    assert(state.attached_to_target and same_position(state.position, h.primary.position))
    assert_visual(state, particle)
    assert(particle.writes[0] > 1)
    if level >= 3 then
        assert(h.primary.buffs[area_slow] == -20 and h.primary.buffs[hit_slow] == -15)
        assert(outside_core.buffs[area_slow] == -20 and outside_core.buffs[hit_slow] == nil,
            "the 600-radius aura must preserve area slow outside the damage core")
    else
        assert(next(h.primary.buffs) == nil and next(outside_core.buffs) == nil)
    end
    h.attributes = 200
    h.advance(1)
    h.advance(1.5)
    h.attributes = 300
    h.advance(2)
    assert(#h.damage == 3 and near(h.damage[2].at, 1) and near(h.damage[3].at, 2)
        and h.damage[2].amount == 400 and h.damage[3].amount == 600,
        "main ticks at zero, one and two seconds must use live attributes")
    h.advance(2.99)
    assert(particle.destroys == 0 and h.service.states[1])
    h.advance(3)
    assert(#h.damage == 3 and next(h.service.states) == nil and next(h.tasks) == nil,
        "three-second completion must not add another damage tick")
    assert(particle.destroys == 1 and particle.releases == 1 and particle.immediate == true
        and near(particle.destroyed_at, 3) and state.particle == nil,
        "natural completion must immediately destroy and release index zero once")
    assert(next(h.primary.buffs) == nil and next(outside_core.buffs) == nil,
        "the last effect's natural expiry must remove every retained slow")
    assert(#h.errors == 0)
end

local tracking = harness(1)
tracking.primary.position = vector(1000, 0, 0)
assert(tracking.cast())
local tracking_state = tracking.service.states[1]
tracking.advance(0.2)
assert(near(tracking_state.position.x, 100), "chasing movement must retain speed 500")
tracking.primary.position = vector(500, 100, 0)
tracking.advance(0.25)
assert(tracking_state.direction.y > 0, "moving the original target must change the tracking direction")
assert_visual(tracking_state, tracking.particles[1])
tracking.advance(1.2)
assert(tracking_state.attached_to_target)
tracking.primary.position = vector(400, 300, 0)
tracking.advance(1.25)
assert(same_position(tracking_state.position, tracking.primary.position), "after arrival the effect must follow the original target")
assert_visual(tracking_state, tracking.particles[1])
tracking.primary.living = false
tracking.primary.position = vector(9999, 9999, 0)
tracking.advance(1.3)
assert(same_position(tracking_state.position, vector(400, 300, 0)), "target death must freeze the last observed position")
assert_visual(tracking_state, tracking.particles[1])
tracking.service.clear()

local children = harness(5)
assert(children.cast())
children.advance(3)
assert(children.service.states[1] == nil and children.particles[1].releases == 1)
local child = assert(children.service.states[2])
assert(child.is_small and child.duration == 2 and near(child.damage_multiplier, 1.2) and child.hit_slow_pct == 0)
assert(#children.particles == 2 and #children.damage == 4 and near(children.damage[4].at, 3)
    and near(children.damage[4].multiplier, 1.2) and children.damage[4].secondary == true,
    "a surviving main hit must spawn one small effect with an immediate sixty-percent damage tick")
assert_visual(child, children.particles[2])
children.advance(3.5)
assert(near(child.position.x, 350) and children.primary.buffs[hit_slow] == nil,
    "small effects must move straight at 500 without the main hit slow")
children.primary.position = vector(650, 0, 0)
children.attributes = 200
children.advance(4)
assert(#children.damage == 5 and near(children.damage[5].at, 4) and near(children.damage[5].amount, 240),
    "the small effect's one-second tick must preserve live sixty-percent attribute damage")
assert_visual(child, children.particles[2])
children.advance(4.99)
assert(children.particles[2].destroys == 0)
children.advance(5)
assert(#children.damage == 5 and next(children.service.states) == nil and next(children.tasks) == nil)
assert(children.particles[2].destroys == 1 and children.particles[2].releases == 1
    and children.particles[2].immediate == true and near(children.particles[2].destroyed_at, 5))
assert(next(children.primary.buffs) == nil, "the final small effect must not leave an area slow behind")
assert(#children.errors == 0)

for _, failure in ipairs({"create", "control"}) do
    local broken = harness(3, failure)
    assert(broken.cast())
    broken.advance(1)
    assert(#broken.damage == 2 and broken.damage[2].multiplier == 2
        and broken.primary.buffs[area_slow] == -20 and broken.primary.buffs[hit_slow] == -15,
        "cosmetic setup failure must preserve tracking damage and slows")
    assert(broken.service.states[1].particle == nil and #broken.errors == 1)
    if failure == "control" then
        assert(broken.particles[1].destroys == 1 and broken.particles[1].releases == 1 and broken.particles[1].immediate == true,
            "partially configured particle zero must be destroyed and released")
    else
        assert(#broken.particles == 0)
    end
    broken.advance(3)
    assert(next(broken.service.states) == nil and next(broken.primary.buffs) == nil)
end

print("VOID_TORNADO_PASS: ordinary Invoker funnel/dust follow CP0/3; following/attachment/death, main0/1/2 damage, level5 small tornadoes, index0 cleanup, slows and visual failures")
