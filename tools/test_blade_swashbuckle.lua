-- Execute the actual pulse launch/hit bodies against engine-shaped mocks.
package.path = "scripts/vscripts/?.lua;" .. package.path
local definition = assert(require("config/hero_passive_skill_definitions").by_id.proto_blade_nova)
local skill_definitions = require("config/generated/hero_skill_definitions")
local file = assert(io.open("scripts/vscripts/systems/hero_passive_skill_service.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function between(first_text, last_text)
    local first = assert(source:find(first_text, 1, true), first_text)
    local last = assert(source:find(last_text, first + #first_text, true), last_text)
    return source:sub(first, last - 1)
end
local seam = table.concat({
    "local blade_pulse_projectiles = {}; local blade_pulse_sequence = 0\n",
    between("local blade_pulse_visual =", "echo_slash.particle ="),
    between("local function valid(unit)", "function arcane_snapfire_visual.release_particle(particle)"),
    between("local function level_value(definition, field, level, fallback)", "local function owned_passives(player_id)"),
    between("local function unit_position(unit)", "local function line_targets(attacker, origin, direction, length, width)"),
    between("local function current_attack_range(attacker)", "local function magic_slingshot_targets("),
    between("function blade_pulse_visual.release(state, immediate)", "function echo_slash.destroy_visual_particle(state)"),
    "return {run = run_blade, hit = blade_pulse_projectile_hit, states = blade_pulse_projectiles}",
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
vector_meta.__mul = function(a, b)
    if type(a) == "number" then return vector(a * b.x, a * b.y, a * b.z) end
    return vector(a.x * b, a.y * b, a.z * b)
end
local function near(a, b) return math.abs(a - b) < 0.000001 end
local function same_position(a, b)
    return near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z)
end
local origin = vector(100, 200, 16)
local direction = vector(0.6, 0.8, 0)

local function harness(level, random_roll, visual_failure, attack_range)
    attack_range = attack_range or 600
    local h = {now = 0, tasks = {}, projectiles = {}, particles = {}, damage = {}, errors = {}, sounds = {}, range_reads = {script = 0, native = 0}}
    local task_sequence = 0
    local function enqueue(delay, callback, task_id)
        task_sequence = task_sequence + 1
        task_id = task_id or ("test_task_" .. task_sequence)
        h.tasks[task_id] = {at = h.now + delay, callback = callback}
        return task_id
    end
    local scheduler = {
        after = enqueue,
        cancel = function(id) h.tasks[id] = nil end,
        every = function(interval, callback, id)
            return enqueue(interval, function()
                if callback() == false then return false end
                return interval
            end, id)
        end,
    }
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
    h.ability = {IsNull = function() return false end}
    h.attacker = {
        IsNull = function() return false end,
        IsAlive = function() return true end,
        GetAbsOrigin = function() return origin end,
        GetForwardVector = function() return vector(3, 4, 10) end,
        GetTeamNumber = function() return 2 end,
        Script_GetAttackRange = function()
            h.range_reads.script = h.range_reads.script + 1
            return attack_range
        end,
        GetAttackRange = function()
            h.range_reads.native = h.range_reads.native + 1
            return attack_range * 5 / 6
        end,
        survival_attack_range = attack_range * 2 / 3,
        FindAbilityByName = function(_, name)
            assert(name == skill_definitions.by_id.proto_blade_nova.ability_name)
            return h.ability
        end,
    }
    h.context = {attacker = h.attacker, skill_id = "proto_blade_nova", level = level}
    local manager = {}
    function manager:CreateParticle(path, attach, owner)
        if visual_failure == "create" then error("injected particle creation failure") end
        local particle = {path = path, attach = attach, owner = owner, controls = {}, forwards = {}, at = h.now, releases = 0, destroys = 0}
        h.particles[#h.particles + 1] = particle
        return #h.particles - 1 -- Engine particle index zero is valid.
    end
    function manager:SetParticleControl(index, control, value)
        if visual_failure == "control" then error("injected particle control failure") end
        h.particles[index + 1].controls[control] = vector(value.x, value.y, value.z)
    end
    function manager:SetParticleControlForward(index, control, value)
        assert(control == 0 or control == 3)
        h.particles[index + 1].forwards[control] = vector(value.x, value.y, value.z)
    end
    function manager:DestroyParticle(index, immediate)
        h.particles[index + 1].destroys = h.particles[index + 1].destroys + 1
        h.particles[index + 1].destroyed_at = h.now
        h.particles[index + 1].immediate = immediate
    end
    function manager:ReleaseParticleIndex(index)
        h.particles[index + 1].releases = h.particles[index + 1].releases + 1
    end
    local env = setmetatable({
        Vector = vector, GameRules = {GetGameTime = function() return h.now end},
        PATTACH_WORLDORIGIN = 0, ParticleManager = manager,
        DOTA_UNIT_TARGET_TEAM_ENEMY = 1, DOTA_UNIT_TARGET_HERO = 2,
        DOTA_UNIT_TARGET_BASIC = 4, DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 8,
        skill_definitions = skill_definitions, hero_definitions = {by_id = {}},
        scheduler = scheduler,
        ProjectileManager = {CreateLinearProjectile = function(_, options)
            h.projectiles[#h.projectiles + 1] = options
            return #h.projectiles
        end},
        RandomFloat = function() return random_roll or 0.9 end,
        GetGroundPosition = function(position) return vector(position.x, position.y, position.z) end,
        M = {sound_service = {play = function(cue) h.sounds[#h.sounds + 1] = cue end}},
        deal = function(context, target, multiplier, secondary)
            assert(context == h.context and secondary == false)
            h.damage[#h.damage + 1] = {target = target, multiplier = multiplier}
        end,
        print = function(message) h.errors[#h.errors + 1] = message end,
    }, {__index = _G})
    local chunk = assert(loadstring(seam, "@blade_swashbuckle_regression"))
    setfenv(chunk, env)
    h.service = chunk()
    function h.cast() return h.service.run(h.context, definition) end
    function h.target(id, progress, team)
        local distance = attack_range * (level == 5 and 1.5 or 1)
        return {
            IsNull = function() return false end, IsAlive = function() return true end,
            GetTeamNumber = function() return team or 3 end,
            entindex = function() return id end,
            GetAbsOrigin = function() return origin + direction * (distance * progress) end,
        }
    end
    return h
end

for _, case in ipairs({
    {1, 0.9, 1}, {2, 0.9, 1}, {3, 0.9, 1}, {4, 0.9, 1}, {5, 0.9, 1}, {5, 0.1, 3},
    {1, 0.9, 1, 150}, {5, 0.1, 3, 150}, {1, 0.9, 1, 900}, {5, 0.9, 1, 900}, {5, 0.1, 3, 900},
}) do
    local level, random_roll, expected_count, attack_range = unpack(case)
    attack_range = attack_range or 600
    local h = harness(level, random_roll, nil, attack_range)
    assert(h.cast(), "a valid blade pulse must launch")
    assert(#h.projectiles == expected_count, "single/triple pulse count changed")
    assert(#h.particles == expected_count, "every pulse must create its own moving Swashbuckle visual")
    local expected_distance = attack_range * (level == 5 and 1.5 or 1)
    local visual_endpoint = attack_range / expected_distance
    assert(h.range_reads.script == 1 and h.range_reads.native == 1,
        "launch must capture the current attack range once for gameplay and the visual cap")
    for pulse_index, projectile in ipairs(h.projectiles) do
        assert(projectile.Ability == h.ability and projectile.Source == h.attacker)
        assert(projectile.EffectName == "", "collision projectiles must not render a second visual")
        assert(same_position(projectile.vSpawnOrigin, origin), "pulse must start at the hero")
        assert(same_position(projectile.vVelocity, direction * expected_distance), "pulse must use hero facing and complete the path in one second")
        assert(projectile.fDistance == expected_distance, "pulse distance must follow the current attack range")
        assert(projectile.fStartRadius == 100 and projectile.fEndRadius == 100, "collision width must remain 200")
        assert(projectile.iUnitTargetTeam == 1 and projectile.iUnitTargetType == 6 and projectile.iUnitTargetFlags == 8)
        assert(projectile.bDeleteOnHit == false and projectile.bProvidesVision == false)
        local particle = h.particles[pulse_index]
        assert(particle.path == "particles/survival/skills/blade_swashbuckle.vpcf")
        assert(particle.attach == 0 and particle.owner == h.attacker, "Swashbuckle must use a world-origin particle")
        assert(same_position(assert(particle.controls[0]), origin) and same_position(assert(particle.controls[3]), origin),
            "Swashbuckle must begin at the collision projectile origin")
        assert(same_position(assert(particle.controls[1]), projectile.vVelocity), "visual velocity must match projectile velocity")
        assert(same_position(assert(particle.forwards[0]), direction), "anchored ghost swords must follow hero facing through CP0")
        assert(same_position(assert(particle.forwards[3]), direction), "moving slash orientation must follow hero facing through CP3")
        local sword_scale = assert(particle.controls[2])
        assert(near(sword_scale.x, attack_range / (805.9557 * 1.1)) and sword_scale.y == 0 and sword_scale.z == 0,
            "CP2 must scale the native ghost sword forward extent and radius to the hero attack range")
        assert(near(sword_scale.x * 805.9557 * 1.1, attack_range),
            "anchored ghost sword length must equal the attack range at every supported range")
        local id = assert(projectile.ExtraData.blade_pulse_projectile_id)
        local friend = h.target(10, 0, 2)
        h.service.hit(h.ability, friend, id)
        h.service.hit({}, h.target(11, 0), id)
        assert(#h.damage == (pulse_index - 1) * 3, "friendly units and a mismatched ability must not deal damage")
        local near_target, middle_target, far_target = h.target(20, 0), h.target(21, 0.5), h.target(22, 1)
        local prior = #h.damage
        assert(h.service.hit(h.ability, near_target, id) == false, "a hit must keep the piercing projectile alive")
        h.service.hit(h.ability, near_target, id)
        h.service.hit(h.ability, middle_target, id)
        h.service.hit(h.ability, far_target, id)
        assert(#h.damage == prior + 3, "a pulse must deduplicate each enemy independently")
        assert(near(h.damage[prior + 1].multiplier, level >= 2 and 8 or 4), "first-target multiplier changed")
        assert(near(h.damage[prior + 2].multiplier, level >= 3 and 6 or 4), "midpoint distance scaling changed")
        assert(near(h.damage[prior + 3].multiplier, level >= 3 and 8 or 4), "end-of-range distance scaling changed")
    end
    assert(#h.damage == expected_count * 3, "each of three pulses must independently hit the same enemies")
    h.advance(visual_endpoint - 0.001)
    for _, particle in ipairs(h.particles) do
        assert(particle.destroys == 0 and particle.releases == 0,
            "the moving visual must survive until the hero attack-range endpoint")
    end
    h.advance(visual_endpoint)
    for _, particle in ipairs(h.particles) do
        assert(particle.destroys == 1 and particle.releases == 1 and near(particle.destroyed_at, visual_endpoint),
            "every Swashbuckle visual must be destroyed and released at the attack-range endpoint")
        assert(particle.immediate == true, "visual completion must immediately stop children at the range cap")
        local traveled = particle.controls[1]:Length2D() * (particle.destroyed_at - particle.at)
        assert(near(traveled, attack_range) and traveled <= attack_range + 0.000001,
            "visual speed multiplied by lifetime must equal the current hero attack range")
    end
    for _, projectile in ipairs(h.projectiles) do
        assert(h.service.states[projectile.ExtraData.blade_pulse_projectile_id],
            "reaching the visual cap must keep native collision state alive")
    end
    if level == 5 then
        h.advance(0.9)
        local prior_damage = #h.damage
        local late_target = h.target(50, 0.9)
        for _, projectile in ipairs(h.projectiles) do
            local pulse_id = projectile.ExtraData.blade_pulse_projectile_id
            h.service.hit(h.ability, late_target, pulse_id)
        end
        assert(#h.damage == prior_damage + expected_count,
            "all level-five pulses must retain collision damage beyond the capped visual")
        for index = prior_damage + 1, #h.damage do
            assert(near(h.damage[index].multiplier, 7.6), "visual shortening must preserve level-five distance damage")
        end
    end
    h.advance(1.249)
    for _, projectile in ipairs(h.projectiles) do
        assert(h.service.states[projectile.ExtraData.blade_pulse_projectile_id], "collision state must survive until cleanup grace")
    end
    h.advance(1.25)
    assert(next(h.service.states) == nil, "expired projectile state must be cleared")
    for _, particle in ipairs(h.particles) do
        assert(particle.destroys == 1 and particle.releases == 1, "cleanup grace must not release a visual twice")
    end
    assert(#h.errors == 0, "blade visual or scheduled cleanup failed")
end

local h = harness(5, 0.1)
assert(h.cast())
local id = h.projectiles[1].ExtraData.blade_pulse_projectile_id
assert(h.service.hit(h.ability, nil, id) == false)
assert(h.service.states[id] == nil, "native projectile completion must clear its own state")
assert(h.service.states[h.projectiles[2].ExtraData.blade_pulse_projectile_id], "finishing one pulse must not clear its siblings")
assert(h.particles[1].destroys == 1 and h.particles[1].releases == 1,
    "native completion must release particle index zero")
assert(h.particles[2].destroys == 0 and h.particles[3].destroys == 0,
    "finishing one pulse must not release its siblings' visuals")
h.advance(1.25)
assert(next(h.service.states) == nil)
for _, particle in ipairs(h.particles) do
    assert(particle.destroys == 1 and particle.releases == 1, "early completion and delayed cleanup must release once")
end

local scaling = harness(5, 0.9)
assert(scaling.cast())
local scaling_id = scaling.projectiles[1].ExtraData.blade_pulse_projectile_id
scaling.service.hit(scaling.ability, scaling.target(30, 0.5), scaling_id)
scaling.service.hit(scaling.ability, scaling.target(31, -0.5), scaling_id)
scaling.service.hit(scaling.ability, scaling.target(32, 1.5), scaling_id)
assert(near(scaling.damage[1].multiplier, 12), "first-hit doubling must multiply the distance bonus")
assert(near(scaling.damage[2].multiplier, 4) and near(scaling.damage[3].multiplier, 8),
    "distance damage must clamp at the near and far endpoints")

for _, failure in ipairs({"create", "control"}) do
    local broken = harness(1, 0.9, failure)
    assert(broken.cast(), "visual failures must not prevent a valid damage projectile")
    local broken_id = broken.projectiles[1].ExtraData.blade_pulse_projectile_id
    broken.service.hit(broken.ability, broken.target(40, 0.5), broken_id)
    assert(#broken.damage == 1 and broken.damage[1].multiplier == 4, "visual failure must preserve damage")
    if failure == "control" then
        assert(#broken.particles == 1 and broken.particles[1].destroys == 1 and broken.particles[1].releases == 1,
            "a partially initialized visual must release its particle index")
        assert(broken.particles[1].immediate == true, "failed visual setup requires immediate cleanup")
    else
        assert(#broken.particles == 0)
    end
    broken.advance(1.25)
    assert(next(broken.service.states) == nil and #broken.errors == 1, "failed visuals must retain collision cleanup and log one failure")
end
print("BLADE_SWASHBUCKLE_PASS: CP0/3 facing and CP2 ghost swords scaled to hero range150/600/900; visual travel cap, level5 stops at2/3s; full damage and independent triple caps; immediate cleanup and visual-failure safety")
