-- Exercise production Earth Line helpers, runner and reset with engine mocks.
-- Particle contracts/lifetimes are checked; native rendering is not simulated.
package.path = "scripts/vscripts/?.lua;" .. package.path
local definition = assert(require("config/hero_passive_skill_definitions").by_id.proto_earth_line)
local skill_definitions = require("config/generated/hero_skill_definitions")
local file = assert(io.open("scripts/vscripts/systems/hero_passive_skill_service.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function between(first, last)
    local begin = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(last, begin + #first, true), last)
    return source:sub(begin, finish - 1)
end
local seam = table.concat({
    "local earth_rock = {projectiles = {}, sequence = 0}; local ARCANE_MAX_HULL_RADIUS = 256",
    between("earth_rock.visual_particle =", "local tornado_visual ="),
    between("local function valid(unit)", "function arcane_snapfire_visual.release_particle("),
    between("local function level_value(", "local function owned_passives("),
    between("local function enemies_in_radius(", "local function normalized_direction("),
    between("local function stun(", "local function current_attack_range("),
    between("local function is_enemy(", "local function magic_slingshot_targets("),
    between("function earth_rock.explosion_visual(", "local function meteor_destroy_particle("),
    between("function M.init()", "M._test ="),
    "return {run = run_earth, visual = earth_rock, hit = earth_rock.projectile_hit, reset = M.init}",
}, "\n")

local meta = {}
meta.__index = meta
local function vector(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, meta) end
meta.__add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
meta.__sub = function(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
meta.__mul = function(a, n) return vector(a.x * n, a.y * n, a.z * n) end
function meta:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
function meta:Normalized()
    local length = math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
    return vector(self.x / length, self.y / length, self.z / length)
end
local function near(a, b) return math.abs(a - b) < 0.000001 end
local function same(a, b) return a and b and near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z) end
local rolling_path = "particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf"
local impact_core_path = "particles/survival/skills/earth_phoenix_impact_core.vpcf"
local impact_paths = {}
for _, radius in ipairs({75, 125, 300}) do
    impact_paths[radius] = "particles/survival/skills/earth_phoenix_impact_" .. radius .. ".vpcf"
end

local function harness(level, fault)
    local h = {now = 0, tasks = {}, next_task = 0, world = {}, particles = {},
        damage = {}, stuns = {}, events = {}, errors = {}, sounds = {}, launches = {}, rolls = 0}
    local function enqueue(delay, callback)
        h.next_task = h.next_task + 1
        h.tasks[#h.tasks + 1] = {id = h.next_task, at = h.now + delay, callback = callback}
        return h.next_task
    end
    function h.advance(until_time)
        while true do
            table.sort(h.tasks, function(a, b) return a.at == b.at and a.id < b.id or a.at < b.at end)
            local task = h.tasks[1]
            if not task or task.at > until_time + 0.0000001 then break end
            table.remove(h.tasks, 1)
            h.now = task.at
            local delay = task.callback()
            if type(delay) == "number" then enqueue(delay, task.callback) end
        end
        h.now = until_time
    end
    function h.unit(id, position, team)
        local unit = {id = id, position = position, team = team or 3, living = true, stunned = false}
        function unit:IsNull() return self.null == true end
        function unit:IsAlive() return self.living end
        function unit:entindex() return self.id end
        function unit:GetAbsOrigin() return self.position end
        function unit:GetTeamNumber() return self.team end
        function unit:GetHullRadius() return 0 end
        function unit:IsStunned() return self.stunned end
        function unit:HasModifier(name) assert(name == "modifier_stunned"); return self.stunned end
        function unit:AddNewModifier(attacker, ability, name, parameters)
            assert(attacker == h.attacker and ability == nil and name == "modifier_stunned")
            assert(parameters.duration == 1 and self.living)
            h.stuns[#h.stuns + 1] = {target = self, at = h.now}
            h.events[#h.events + 1] = {kind = "stun", target = self, at = h.now}
            self.stunned = true
        end
        h.world[#h.world + 1] = unit
        return unit
    end
    h.ability = {IsNull = function() return false end}
    h.attacker = h.unit(100, vector(1000, 2000, 10), 2)
    function h.attacker:FindAbilityByName(name)
        assert(name == skill_definitions.by_id.proto_earth_line.ability_name)
        return h.ability
    end
    h.target = h.unit(1, vector(2000, 2000, 10))
    h.first = h.unit(2, vector(1300, 2000, 44))
    h.second = h.unit(3, vector(1700, 2000, 22)); h.second.stunned = true
    h.nearby = h.unit(4, vector(1320, 2100, 22)); h.nearby.stunned = true
    h.context = {attacker = h.attacker, target = h.target, level = level,
        skill_id = "proto_earth_line", attributes = {all_attributes = 100}}
    function h.of_kind(kind)
        local result = {}
        for _, particle in ipairs(h.particles) do
            if particle.kind == kind then result[#result + 1] = particle end
        end
        return result
    end
    local function fail(kind, stage, particle)
        if fault and fault.kind == kind and fault.stage == stage and not fault.used then
            fault.used = true
            if particle then particle.failed = stage end
            error("injected " .. kind .. " " .. tostring(stage) .. " failure")
        end
    end
    local manager = {}
    function manager:CreateParticle(path, attachment, owner)
        local kind, radius = path == rolling_path and "rolling" or nil, nil
        if path == impact_core_path then kind = "impact_core" end
        for size, expected in pairs(impact_paths) do
            if path == expected then kind, radius = "impact", size end
        end
        assert(kind, "unexpected Earth Line particle: " .. tostring(path))
        assert(attachment == 0 and owner == h.attacker)
        fail(kind, "create")
        local particle = {index = #h.particles, kind = kind, radius = radius, path = path, owner = owner,
            at = h.now, controls = {}, history = {}, destroys = 0, releases = 0}
        h.particles[#h.particles + 1] = particle
        if kind == "impact" then
            h.pending_impact = particle
        elseif kind == "impact_core" then
            local ground = assert(h.pending_impact, "an airborne core belongs to a ground explosion")
            assert(ground.core == nil, "each logical explosion has exactly one airborne core")
            ground.core, particle.ground = particle, ground
            h.pending_impact = nil
        end
        h.events[#h.events + 1] = {kind = "particle", particle = particle, at = h.now}
        return particle.index
    end
    function manager:SetParticleControl(index, control, position)
        local particle = assert(h.particles[index + 1])
        if particle.kind == "rolling" then assert(control >= 0 and control <= 2)
        else assert(control == 0 or control == 1 or control == 3) end
        fail(particle.kind, control, particle)
        particle.controls[control] = vector(position.x, position.y, position.z)
        particle.history[#particle.history + 1] = {control = control, at = h.now}
    end
    function manager:DestroyParticle(index, immediate)
        local particle = assert(h.particles[index + 1])
        assert(type(immediate) == "boolean")
        particle.destroys, particle.immediate, particle.destroyed_at = particle.destroys + 1, immediate, h.now
        fail(particle.kind, "destroy", particle)
    end
    function manager:ReleaseParticleIndex(index)
        local particle = assert(h.particles[index + 1])
        if particle.kind ~= "rolling" and particle.destroys == 0 then
            local ground = particle.kind == "impact" and particle or particle.ground
            local core = assert(ground.core, "finish both impact graphs before releasing either handle")
            for _, graph in ipairs({ground, core}) do
                assert(graph.controls[0] and graph.controls[1] and graph.controls[3],
                    "both graphs must be fully positioned before normal release")
            end
        end
        particle.releases, particle.released_at = particle.releases + 1, h.now
        fail(particle.kind, "release", particle)
    end
    local noop = function() end
    local env = setmetatable({
        Vector = vector, ParticleManager = manager, PATTACH_WORLDORIGIN = 0,
        ProjectileManager = {CreateLinearProjectile = function(_, info)
            h.launches[#h.launches + 1] = info
            return #h.launches
        end},
        GameRules = {GetGameTime = function() return h.now end},
        GetGroundPosition = function(position) return vector(position.x, position.y, 16) end,
        RandomFloat = function(low, high)
            assert(low == 0 and high == 1)
            h.rolls = h.rolls + 1
            return h.rolls % 2 == 1 and 0.1 or 0.9
        end,
        DOTA_UNIT_TARGET_TEAM_ENEMY = 1, DOTA_UNIT_TARGET_HERO = 2, DOTA_UNIT_TARGET_BASIC = 4,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 8, FIND_CLOSEST = 0, FIND_ANY_ORDER = 1,
        FindUnitsInRadius = function(team, position, _, radius, target_team, target_type, flags, order)
            assert(team == 2 and target_team == 1 and target_type == 6 and flags == 8 and order == 1)
            assert(near(radius, 300 + 256), "only the original level-five first-hit damage queries an area")
            h.last_area = {position = vector(position.x, position.y, position.z), radius = radius - 256}
            local result = {}
            for _, unit in ipairs(h.world) do
                if unit.team ~= team and (unit.position - position):Length2D() <= radius then result[#result + 1] = unit end
            end
            return result
        end,
        skill_definitions = skill_definitions,
        scheduler = {after = enqueue, cancel = function(id)
            for i = #h.tasks, 1, -1 do if h.tasks[i].id == id then table.remove(h.tasks, i) end end
        end},
        deal = function(context, target, multiplier, secondary)
            assert(context == h.context)
            local event = {kind = "damage", target = target, multiplier = multiplier,
                secondary = secondary, was_stunned = target.stunned, at = h.now}
            h.damage[#h.damage + 1] = event; h.events[#h.events + 1] = event
        end,
        M = {sound_service = {reset = noop, play = function(cue, args)
            h.sounds[#h.sounds + 1] = {cue = cue, position = args.position, at = h.now}
        end}},
        print = function(message) h.errors[#h.errors + 1] = message end,
        definitions = {validate = noop}, exclusive_passives = {init = noop},
        echo_slash = {clear = noop}, arcane_snapfire_visual = {clear = noop}, ice_cone_visual = {clear = noop},
        clear_flame_burns = noop, clear_moving_ice_balls = noop, clear_poison_clouds = noop,
        clear_meteors = noop, clear_magic_slingshot_rubble = noop, clear_tornadoes = noop,
        blade_pulse_projectiles = {}, blade_pulse_visual = {release = noop},
        meteor_explosion_visuals = {},
        event_bus = {subscribe = noop}, events = {},
    }, {__index = _G})
    local chunk = assert(loadstring(seam, "@earth_line_visual_regression"))
    setfenv(chunk, env)
    h.service = chunk()
    function h.cast()
        local success = h.service.run(h.context, definition)
        if success then h.id = h.launches[#h.launches].ExtraData.earth_rock_projectile_id end
        return success
    end
    function h.hit(target, position, id, ability)
        return h.service.hit(ability or h.ability, target, position, id or h.id)
    end
    return h
end

local function assert_impact(particle, position, radius)
    local grounded = vector(position.x, position.y, 16)
    assert(particle.kind == "impact" and particle.path == impact_paths[radius] and particle.radius == radius)
    assert(same(particle.controls[0], grounded) and same(particle.controls[1], vector(1, 1, 1))
        and same(particle.controls[3], grounded + vector(0, 0, 100 * radius / 500)),
        "complete Phoenix roots keep grounded position and correctly scaled native shockwave normals")
    assert(particle.releases == 1 and particle.destroys == 0,
        "finite complete native explosions decay after one release without a custom kill timer")
    local core = assert(particle.core, "every ground explosion must also have the visible airborne core")
    assert(core.kind == "impact_core" and core.path == impact_core_path and core.ground == particle
        and near(core.at, particle.at), "the core and ground layers are created for the same logical impact")
    assert(same(core.controls[0], grounded + vector(0, 0, 90))
        and same(core.controls[1], vector(1, 1, 1))
        and same(core.controls[3], grounded + vector(0, 0, 150)),
        "the Phoenix core stays above terrain while its ground footprint remains level-scaled")
    assert(core.releases == 1 and core.destroys == 0,
        "the finite airborne graph retains its native lifespan after one release")
end

for level = 1, 5 do
    local h = harness(level)
    local radius = level == 1 and 75 or 125
    assert(h.cast())
    local state = assert(h.service.visual.projectiles[h.id])
    local info, rolling = h.launches[1], h.of_kind("rolling")[1]
    assert(info.Ability == h.ability and info.Source == h.attacker and info.EffectName == nil)
    assert(info.fDistance == 1000 and same(info.vVelocity, vector(500, 0, 0))
        and info.fStartRadius == radius and info.fEndRadius == radius
        and info.bDeleteOnHit == false and info.bProvidesVision == false,
        "cosmetic changes must preserve straight-line speed, range, collision width and piercing")
    assert(info.iUnitTargetTeam == 1 and info.iUnitTargetType == 6 and info.iUnitTargetFlags == 8)
    assert(state.impact_radius == radius and near(state.duration, 2) and state.visual_particle == 0)
    assert(same(rolling.controls[0], vector(1000, 2000, 10))
        and same(rolling.controls[1], vector(500, 0, 0)) and same(rolling.controls[2], vector(2, 0, 0)))
    assert(#rolling.history == 3 and rolling.releases == 0 and #h.damage == 0)
    h.attacker.position = vector(9000, 9000, 0)
    h.target.position = vector(8000, 8000, 0)
    local friendly = h.unit(5, vector(1300, 2000, 0), 2)
    local dead = h.unit(6, vector(1300, 2000, 0)); dead.living = false
    local wrong_ability = {IsNull = function() return false end}
    assert(h.hit(friendly) == false and h.hit(dead) == false and h.hit(h.first, nil, nil, wrong_ability) == false)
    assert(#h.damage == 0 and #h.of_kind("impact") == 0 and h.rolls == 0)
    h.now = 0.6
    local first_position = vector(1300, 2000, 55)
    assert(h.hit(h.first, first_position) == false)
    assert(h.damage[1].target == h.first and h.damage[1].multiplier == 3 and not h.damage[1].secondary)
    assert(#h.damage == (level == 5 and 3 or 1))
    if level == 5 then
        assert(h.damage[2].target == h.first and h.damage[2].multiplier == 3 and h.damage[2].secondary)
        assert(h.damage[3].target == h.nearby and h.damage[3].multiplier == 6 and h.damage[3].secondary)
        assert(same(h.last_area.position, first_position) and h.last_area.radius == 300)
        assert(state.first_hit_exploded)
    end
    assert(#h.stuns == (level >= 3 and 1 or 0) and h.rolls == (level >= 3 and 1 or 0))
    if level >= 3 then
        local stun_index
        for index, event in ipairs(h.events) do if event.kind == "stun" then stun_index = index; break end end
        assert(stun_index)
        for index, event in ipairs(h.events) do
            if event.kind == "damage" then assert(index < stun_index, "all original first-hit damage precedes its new stun") end
        end
    end
    assert(#h.of_kind("impact") == 1)
    assert_impact(h.of_kind("impact")[1], first_position, level == 5 and 300 or radius)
    local damage_before, rolls_before = #h.damage, h.rolls
    assert(h.hit(h.first, first_position) == false and #h.damage == damage_before
        and h.rolls == rolls_before and #h.of_kind("impact") == 1,
        "duplicate native callbacks cannot duplicate Phoenix bursts, damage or stun rolls")
    h.now = 1.4
    assert(h.hit(h.second) == false)
    assert(#h.damage == damage_before + 1 and h.damage[#h.damage].multiplier == 6
        and h.damage[#h.damage].target == h.second and not h.damage[#h.damage].secondary)
    assert(#h.of_kind("impact") == 2 and h.service.visual.projectiles[h.id] == state and rolling.destroys == 0,
        "each accepted enemy hit gets one burst while the same rock continues piercing")
    assert_impact(h.of_kind("impact")[2], h.second.position, radius)
    assert(#h.stuns == (level >= 3 and 1 or 0) and h.rolls == (level >= 3 and 2 or 0),
        "only accepted path hits independently roll the original 30-percent stun")
    h.now = 2
    h.hit(nil, vector(2000, 2000, 10))
    assert(next(h.service.visual.projectiles) == nil and #h.damage == damage_before + 1)
    assert(rolling.destroys == 1 and rolling.releases == 1 and rolling.immediate == false
        and near(rolling.destroyed_at, 2), "natural travel completion preserves the fire trail's native endcap")
    assert(#h.of_kind("impact") == 3)
    assert(#h.of_kind("impact_core") == 3,
        "both accepted hits and the harmless endpoint receive exactly one airborne core")
    assert_impact(h.of_kind("impact")[3], vector(2000, 2000, 10), radius)
    h.advance(10)
    assert(#h.of_kind("impact") == 3 and #h.of_kind("impact_core") == 3
        and rolling.destroys == 1 and rolling.releases == 1
        and #rolling.history == 3 and #h.errors == 0,
        "the old timeout cannot replay terminal visuals or overwrite the rolling graph")
end

-- A missed target still ends with the existing harmless terminal burst, and
-- missing engine end callbacks use the same natural stop at the original grace.
for _, ending in ipairs({"terminal", "fallback", "clear"}) do
    local h = harness(5)
    assert(h.cast())
    local rolling = h.particles[1]
    if ending == "terminal" then h.now = 2; h.hit(nil)
    elseif ending == "clear" then h.now = 0.5; h.service.visual.clear() end
    h.advance(3)
    assert(next(h.service.visual.projectiles) == nil and #h.damage == 0 and h.rolls == 0)
    assert(rolling.destroys == 1 and rolling.releases == 1 and rolling.immediate == (ending == "clear"))
    assert(near(rolling.destroyed_at, ending == "terminal" and 2 or ending == "clear" and 0.5 or 2.25))
    assert(#h.of_kind("impact") == (ending == "clear" and 0 or 1))
    assert(#h.of_kind("impact_core") == (ending == "clear" and 0 or 1),
        "terminal callbacks and fallback timers create one complete pair; explicit clear creates neither")
    if ending ~= "clear" then assert_impact(h.of_kind("impact")[1], vector(2000, 2000, 10), 125) end
end

-- The actual reset revokes current handles and preserves monotonically unique
-- IDs. Retained native hit callbacks and fallback timers cannot hit the new cast.
do
    local h = harness(1)
    assert(h.cast())
    local old_id, old_state, old_timer = h.id, h.service.visual.projectiles[h.id], h.tasks[1]
    local old_particle = h.particles[1]
    h.now = 0.1
    h.service.reset()
    assert(old_particle.immediate == true and old_particle.destroys == 1 and old_particle.releases == 1
        and old_state.visual_particle == nil and next(h.service.visual.projectiles) == nil)
    assert(h.cast())
    local new_id, new_state = h.id, h.service.visual.projectiles[h.id]
    assert(new_id > old_id and new_state ~= old_state)
    local before_particles = #h.particles
    h.hit(h.first, h.first.position, old_id)
    h.hit(nil, nil, old_id)
    old_timer.callback()
    assert(#h.damage == 0 and #h.particles == before_particles
        and h.service.visual.projectiles[new_id] == new_state)
    h.hit(h.first, h.first.position)
    assert(#h.damage == 1 and #h.of_kind("impact") == 1)
    h.advance(3)
    assert(next(h.service.visual.projectiles) == nil and #h.of_kind("impact") == 2
        and old_particle.destroys == 1 and old_particle.releases == 1)
end

local faults = {
    {kind = "rolling", stage = "create"}, {kind = "rolling", stage = 0},
    {kind = "rolling", stage = 1}, {kind = "rolling", stage = 2},
    {kind = "rolling", stage = "destroy"}, {kind = "rolling", stage = "release"},
    {kind = "impact", stage = "create"}, {kind = "impact", stage = 0},
    {kind = "impact", stage = 1}, {kind = "impact", stage = 3},
    {kind = "impact_core", stage = "create"}, {kind = "impact_core", stage = 0},
    {kind = "impact_core", stage = 1}, {kind = "impact_core", stage = 3},
}
for _, fault in ipairs(faults) do
    local h = harness(5, fault)
    assert(h.cast())
    h.now = 0.6; h.hit(h.first, h.first.position)
    h.now = 1.4; h.hit(h.second, h.second.position)
    h.now = 2; h.hit(nil)
    h.advance(3)
    assert(fault.used and #h.errors >= 1 and #h.damage == 4 and #h.stuns == 1 and h.rolls == 2
        and next(h.service.visual.projectiles) == nil,
        "any visual failure must preserve piercing damage, level-five first-hit AoE, stun and cleanup")
    for _, particle in ipairs(h.particles) do
        assert(particle.releases == 1, "every allocated graph receives one independent release attempt")
        if type(particle.failed) == "number" then
            assert(particle.destroys == 1 and particle.immediate == true,
                "partially configured native roots must be discarded immediately")
        elseif particle.kind == "rolling" then assert(particle.destroys == 1) end
    end
    if fault.kind == "impact_core" then
        local ground = h.of_kind("impact")[1]
        assert(ground.destroys == 1 and ground.immediate == true and ground.releases == 1,
            "core creation/configuration failure rolls back the already-created ground graph exactly once")
        if ground.core then
            assert(ground.core.destroys == 1 and ground.core.immediate == true
                and ground.core.releases == 1, "a partial core is rolled back with its paired ground graph")
        end
    end
    local last_impact = h.of_kind("impact")[#h.of_kind("impact")]
    assert_impact(last_impact, vector(2000, 2000, 10), 125)
end

print("EARTH_LINE_VISUAL_PASS: Phoenix75/125/300 ground plus elevated native core at unique hits and harmless endpoint; original500 speed/width/piercing/3x6x/stun/firstAoE retained; natural trail stop, hard clear, pair rollback and stale reset callbacks (native rendering not simulated)")
