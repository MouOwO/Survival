-- Execute the real original-skin Snapfire barrage, including its reset path.
-- One native root owns its flight graph; Lua only configures it at creation.
-- Mocks verify inputs/lifetime and damage deadlines, not native particle physics.
package.path = "scripts/vscripts/?.lua;" .. package.path
local config = require("config/hero_passive_skill_definitions")
local definition = assert(config.by_id.proto_arcane_barrage)
local file = assert(io.open("scripts/vscripts/systems/hero_passive_skill_service.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()

local function between(first_text, last_text)
    local first = assert(source:find(first_text, 1, true), first_text)
    local last = assert(source:find(last_text, first + #first_text, true), last_text)
    return source:sub(first, last - 1)
end

local seam = table.concat({
    "local active_arcane_barrages = {}; local arcane_barrage_sequence = 0\n",
    between("local arcane_snapfire_visual =", "local FLAME_MAIN_EXPLOSION_PARTICLE ="),
    between("local function valid(unit)", "local function alive(unit)"),
    between("local function copy_position(position)", "local function ice_cone_locked(attacker_key)"),
    between("local function level_value(definition, field, level, fallback)", "local function owned_passives(player_id)"),
    between("local function unit_position(unit)", "local function normalized_direction(origin, destination, fallback)"),
    between("local function run_arcane(context, definition)", "local function create_magic_slingshot_rubble(context, position, definition)"),
    between("function M.init()", "M._test ="),
    "return { run = run_arcane, reset = M.init, locked = arcane_barrage_locked,",
    "active = function() return active_arcane_barrages end, visual = arcane_snapfire_visual }",
}, "\n")

local vector_meta = {}
local function vector(x, y, z)
    return setmetatable({x = x, y = y, z = z}, vector_meta)
end
vector_meta.__add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
local function near(a, b) return math.abs(a - b) < 0.000001 end
local function same_position(a, b)
    return a and b and near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z)
end
local paths = {
    flight = "particles/units/heroes/hero_snapfire/snapfire_lizard_blobs_arced.vpcf",
    impact = "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_impact.vpcf",
    linger = "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_linger.vpcf",
}

local function harness(level, failure, real_scheduler)
    local h = {now = 0, queue = {}, particles = {}, by_index = {}, damage = {},
        sounds = {}, errors = {}, events = {}, next_task = 0, ice_clear_calls = 0}
    local target_position = vector(100, 200, 10)
    local attacker_null = false
    local attacker = {
        IsNull = function() return attacker_null end,
        entindex = function() return 42 end,
    }
    h.owners = {[attacker] = true}
    h.second_attacker = {IsNull = function() return false end, entindex = function() return 43 end}
    h.owners[h.second_attacker] = true
    local target = {
        IsNull = function() return false end,
        GetAbsOrigin = function() return target_position end,
    }
    h.context = {attacker = attacker, target = target, level = level}
    h.move_target = function() target_position = vector(10000, 10000, 10) end
    h.invalidate_attacker = function() attacker_null = true end
    local function enqueue(delay, callback)
        h.next_task = h.next_task + 1
        local item = {at = h.now + delay, callback = callback, id = h.next_task}
        h.queue[#h.queue + 1] = item
        return item.id
    end
    local function cancel(id)
        for index = #h.queue, 1, -1 do
            if h.queue[index].id == id then table.remove(h.queue, index) end
        end
    end
    function h.advance(until_time)
        while true do
            table.sort(h.queue, function(a, b)
                return a.at == b.at and a.id < b.id or a.at < b.at
            end)
            local item = h.queue[1]
            if not item or item.at > until_time + 0.0000001 then break end
            table.remove(h.queue, 1)
            h.now = item.at
            local delay = item.callback()
            if type(delay) == "number" then enqueue(delay, item.callback) end
        end
        h.now = until_time
    end
    function h.of_kind(kind)
        local result = {}
        for _, particle in ipairs(h.particles) do
            if particle.kind == kind then result[#result + 1] = particle end
        end
        return result
    end
    local manager = {}
    function manager:CreateParticle(path, attach, owner)
        local kind
        for name, expected in pairs(paths) do if expected == path then kind = name end end
        assert(kind, "unexpected Arcane particle: " .. tostring(path))
        assert(attach == 0 and h.owners[owner], "particles must retain their actual caster")
        if failure and failure.kind == kind and failure.create and not failure.used then
            failure.used = true
            error("injected creation failure")
        end
        local index = #h.particles -- index 0 must be cleaned and released normally.
        local particle = {index = index, kind = kind, path = path, owner = owner, at = h.now, controls = {},
            forwards = {}, history = {}, releases = 0, destroys = 0}
        h.particles[#h.particles + 1] = particle
        h.by_index[index] = particle
        return index
    end
    function manager:SetParticleControl(index, control, position)
        local particle = assert(h.by_index[index], "unknown particle")
        if particle.kind == "flight" then
            assert(control == 0 or control == 1 or control == 2 or control == 3,
                "native flight CP4 belongs to the particle graph; custom size controls are unsupported")
            assert(near(h.now, particle.at), "Lua must not overwrite native motion controls after creation")
            assert(particle.controls[control] == nil, "each native flight input is initialized only once")
        else
            assert(control == 0 or control == 1 or control == 3,
                "native ground roots use positional CP0/1/3, including the liquid repulsion origin")
        end
        if failure and failure.kind == particle.kind and failure.control == control
            and h.now >= (failure.after or 0) and not failure.used then
            failure.used = true
            particle.failed = true
            error("injected control failure")
        end
        particle.controls[control] = vector(position.x, position.y, position.z)
        particle.history[#particle.history + 1] = {
            at = h.now, control = control, position = vector(position.x, position.y, position.z),
        }
    end
    function manager:SetParticleControlForward(index, control, direction)
        error("native projectile graph owns carrier orientation; Lua must not overwrite CP3/4 facing")
    end
    function manager:ReleaseParticleIndex(index)
        local particle = assert(h.by_index[index])
        particle.releases = particle.releases + 1
        h.events[#h.events + 1] = {kind = "release", index = index, at = h.now}
    end
    function manager:DestroyParticle(index, immediate)
        local particle = assert(h.by_index[index])
        assert(immediate == true, "discarded flights and partial visuals stop immediately")
        particle.destroys = particle.destroys + 1
        particle.destroyed_at = h.now
        h.events[#h.events + 1] = {kind = "destroy", index = index, at = h.now}
        if failure and failure.kind == particle.kind and failure.destroy and not failure.used then
            failure.used = true
            particle.failed = true
            error("injected destroy failure")
        end
    end
    local noop = function() end
    local env = setmetatable({
        Vector = vector, PATTACH_WORLDORIGIN = 0, ParticleManager = manager,
        GameRules = {GetGameTime = function() return h.now end},
        RandomFloat = function(low, high)
            if h.random_float then return h.random_float(low, high) end
            return (low + high) * 0.5
        end,
        GetGroundPosition = function(position) return vector(position.x, position.y, 64) end,
        scheduler = {after = enqueue, cancel = cancel},
        M = {sound_service = {reset = noop, play = function(cue, arguments)
            h.sounds[#h.sounds + 1] = {cue = cue, position = arguments.position, at = h.now}
        end}},
        enemies_touching_radius = function(actual_attacker, position, radius)
            assert(actual_attacker == attacker and radius == 150, "damage radius must remain 150")
            return {position = position, radius = radius}
        end,
        deal_group = function(context, targets, multiplier, option)
            assert(context == h.context and multiplier == 2 and option == false)
            h.damage[#h.damage + 1] = {position = targets.position, radius = targets.radius, at = h.now}
            h.events[#h.events + 1] = {kind = "damage", at = h.now}
        end,
        print = function(message) h.errors[#h.errors + 1] = message end,
        definitions = {validate = noop}, exclusive_passives = {init = noop},
        echo_slash = {clear = noop}, earth_rock = {clear = noop},
        clear_flame_burns = noop, clear_moving_ice_balls = noop,
        clear_poison_clouds = noop, clear_meteors = noop,
        ice_cone_visual = {clear = function() h.ice_clear_calls = h.ice_clear_calls + 1 end},
        clear_magic_slingshot_rubble = noop, clear_tornadoes = noop,
        blade_pulse_projectiles = {}, blade_pulse_visual = {release = noop},
        meteor_explosion_visuals = {}, event_bus = {subscribe = noop}, events = {},
    }, {__index = _G})
    if real_scheduler then
        local scheduler_chunk = assert(loadfile("scripts/vscripts/core/scheduler.lua"))
        setfenv(scheduler_chunk, env)
        local scheduler = scheduler_chunk()
        env.scheduler = scheduler
        local tick = 0
        function h.advance(until_time)
            local final_tick = math.floor(until_time / 0.05 + 0.0000001)
            while tick < final_tick do
                tick = tick + 1
                h.now = tick * 0.05
                scheduler.think()
            end
            h.now = until_time
        end
    end
    local chunk = assert(loadstring(seam, "@arcane_native_snapfire_regression"))
    setfenv(chunk, env)
    h.service = chunk()
    function h.cast() return h.service.run(h.context, definition) end
    return h
end

-- Each shell needs its own complete ground graph, including its spreading
-- floor. Counting isolated short children cannot substitute for that graph.
local function assert_ground_hits(h)
    for _, kind in ipairs({"impact", "linger"}) do
        local effects = h.of_kind(kind)
        assert(#effects == #h.damage,
            "every shell needs its own complete native " .. kind .. " even at the same landing position")
        for _, hit in ipairs(h.damage) do
            local matching = 0
            for _, particle in ipairs(effects) do
                if near(particle.at, hit.at) and same_position(particle.controls[0], hit.position) then
                    matching = matching + 1
                end
            end
            assert(matching == 1, "complete ground roots must occur once at each actual landing: " .. kind)
        end
        for _, particle in ipairs(effects) do
            assert(same_position(particle.controls[0], particle.controls[1])
                and same_position(particle.controls[0], particle.controls[3]),
                "all native ground origins must point to this impact rather than world origin")
            assert(not particle.failed and particle.owner == h.context.attacker
                and particle.destroys == 0 and particle.releases == 1,
                "each complete native ground root keeps its caster and natural decay")
        end
    end
end

for _, level in ipairs({1, 2, 3, 4, 5}) do
    local h = harness(level)
    local per_round = level <= 2 and 5 or 7
    local count = level == 5 and 21 or per_round
    local first_impact = 0.8
    local final_impact = (level == 5 and 2 or 0) + (per_round - 1) / per_round + 0.8
    local landing_radius = level == 1 and 500 or 200
    assert(h.cast(), "initial barrage must trigger")
    local original_state = assert(h.service.active()["42"])
    local token = original_state.token
    assert(h.service.visual.flight == paths.flight)
    assert(h.service.visual.flights == nil, "create the complete native projectile instead of separated child resources")
    assert(h.service.visual.linger == paths.linger and h.service.visual.ground_impacts == nil
        and h.service.visual.ground_pools == nil and h.service.visual.landing_pool == nil,
        "complete per-shell ground graphs replace the removed merge and standalone-child paths")
    assert(#h.of_kind("flight") == 1 and #h.particles == 1 and #h.damage == 0,
        "the first root starts in the cast frame without damage or a ground field")
    for _, particle in ipairs(h.particles) do assert(particle.at == 0) end
    assert(not h.cast(), "an active barrage must block retriggering")
    assert(#h.queue == 4 and #h.sounds == 1,
        "blocked cast adds no work beyond flight maintenance, first landing, launch and failsafe")
    h.move_target()
    h.advance(0)
    local first_flight = assert(h.of_kind("flight")[1], "first root must be created before the damage deadline")
    assert(first_flight.index == 0 and first_flight.releases == 0, "particle zero is a valid flight handle")
    local first_missile = original_state.missiles[1]
    assert(first_missile.particle == first_flight.index and first_missile.particles == nil,
        "each missile owns exactly one native root handle")
    local initial_center = first_flight.controls[0]
    assert(near(initial_center.z, 1864), "native flight is configured 1800 above the grounded target")
    assert(#first_flight.history == 4, "initialize CP0/1/2/3 exactly once")
    h.advance(first_impact / 2)
    assert(same_position(first_flight.controls[0], initial_center) and #first_flight.history == 4,
        "lifetime maintenance must leave native projectile motion to its graph")
    h.advance(first_impact - 0.001)
    assert(#h.damage == 0 and #h.of_kind("impact") == 0 and #h.of_kind("linger") == 0)
    h.advance(first_impact)
    assert(#h.damage == 1 and #h.of_kind("impact") == 1 and #h.of_kind("linger") == 1,
        "the first landing plays the original-skin explosion and pool and applies damage once")
    assert(first_flight.destroys == 1 and first_flight.releases == 1
        and near(first_flight.destroyed_at, first_impact), "one root ends at the first damage deadline")
    assert(first_missile.particle == nil and first_missile.particles == nil)
    h.advance(final_impact - 0.001)
    assert(not h.cast() and h.service.active()["42"].remaining_missiles == 1)
    h.advance(final_impact)
    assert(#h.damage == count and #h.of_kind("impact") == count and #h.of_kind("linger") == count,
        "overlapping landings each retain the complete native ground expansion and explosion")
    assert(h.service.active()["42"] == nil, "unlock waits for the last full-duration flight")
    assert(next(h.service.visual.active) == nil, "finished barrage retains no flight handles")
    assert(h.ice_clear_calls == 0, "Arcane casts never clear independent Ice Cone visuals")
    assert(#h.of_kind("flight") == count and #h.particles == count * 3,
        "each missile creates exactly one complete flight, impact and linger without duplicate child layers")
    local impacts, ground_effects = h.of_kind("impact"), h.of_kind("linger")
    for index, landing in ipairs(h.damage) do
        local expected_time = math.floor((index - 1) / per_round)
            + ((index - 1) % per_round) / per_round + 0.8
        local expected_position = vector(100 - math.sqrt(0.5) * landing_radius, 200, 64)
        assert(near(landing.at, expected_time), "damage follows each shell's full flight")
        assert(same_position(landing.position, expected_position), "scatter retains its grounded snapshot")
        local particle = h.of_kind("flight")[index]
        local expected_start = expected_time - 0.8
        local sky = expected_position + vector(0, 0, 1800)
        assert(near(particle.at, expected_start))
        assert(particle.destroys == 1 and particle.releases == 1
            and near(particle.destroyed_at, expected_time), "each native root releases exactly once at its damage deadline")
        assert(same_position(particle.controls[0], sky) and same_position(particle.controls[3], sky))
        assert(same_position(particle.controls[1], expected_position), "CP1 is the grounded destination")
        assert(same_position(particle.controls[2], vector(2250, 0, 0)),
            "every native shell uses the same half-speed limit, including the first")
        assert(particle.controls[4] == nil and next(particle.forwards) == nil and #particle.history == 4)
        for _, sample in ipairs(particle.history) do
            assert(near(sample.at, expected_start), "initialization cannot become a per-frame carrier override")
        end
        for _, particle in ipairs({impacts[index], ground_effects[index]}) do
            assert(near(particle.at, landing.at) and same_position(particle.controls[0], landing.position))
            assert(same_position(particle.controls[1], landing.position)
                and same_position(particle.controls[3], landing.position))
            assert(particle.destroys == 0 and particle.releases == 1,
                "unmodified landing effects retain native decay instead of custom destruction timers")
        end
    end
    assert_ground_hits(h)
    assert(#h.errors == 0)
    assert(h.cast(), "skill retriggers after the final full-duration landing")
    local new_state = h.service.active()["42"]
    assert(new_state.token ~= token and new_state ~= original_state)
    h.advance(final_impact + 0.5)
    assert(h.service.active()["42"] == new_state and not h.cast(), "old failsafe cannot end a new cast")
    assert(#h.errors == 0)
end

-- A later barrage at the exact same position still creates one full ground
-- graph per shell, even while the previous native ground particles are fading.
do
    local h = harness(1)
    assert(h.cast())
    h.advance(1.6)
    assert(h.cast())
    h.advance(3.2)
    assert(#h.damage == 10 and #h.of_kind("impact") == 10 and #h.of_kind("flight") == 10)
    assert(#h.of_kind("linger") == 10 and #h.particles == 30)
    assert_ground_hits(h)
    assert(#h.errors == 0 and h.service.active()["42"] == nil)
end

-- Nearby but distinct shell destinations each retain their exact full ground
-- origin, even though all destinations fit inside the former merge distance.
do
    local h = harness(3)
    local rolls = 0
    h.random_float = function(low, high)
        rolls = rolls + 1
        return low + (high - low) * ((rolls * 7) % 19) / 19
    end
    assert(h.cast())
    h.advance(1.8)
    assert(#h.damage == 7 and #h.of_kind("linger") == 7)
    for index, hit in ipairs(h.damage) do
        for prior = 1, index - 1 do
            assert(not same_position(hit.position, h.damage[prior].position))
        end
    end
    assert_ground_hits(h)
end

-- Creation/setup failure affects only that allocation; the next complete
-- ground graph at the same point must still be created and released normally.
for _, failure in ipairs({{kind = "linger", create = true}, {kind = "linger", control = 0},
    {kind = "linger", control = 1}, {kind = "linger", control = 3}}) do
    local h = harness(1, failure)
    local visual, attacker = h.service.visual, h.context.attacker
    assert(visual.landing_particle(paths.linger, attacker, vector(0, 0, 64)) == false)
    assert(failure.used and #h.errors == 1)
    assert(visual.landing_particle(paths.linger, attacker, vector(0, 0, 64)) == true)
    local successful = h.of_kind("linger")[#h.of_kind("linger")]
    assert(not successful.failed and successful.destroys == 0 and successful.releases == 1)
    for _, particle in ipairs(h.particles) do
        assert(particle.releases == 1)
        if particle.failed then assert(particle.destroys == 1) end
    end
end

-- Explicit visual clear and reset cancel unlanded shells but leave complete
-- ground effects already handed to the engine to finish their native decay.
for _, reset in ipairs({false, true}) do
    local h = harness(1)
    assert(h.cast())
    h.advance(0.8)
    local first = h.of_kind("linger")[1]
    if reset then h.service.reset() else h.service.visual.clear() end
    h.advance(2)
    assert(first.releases == 1 and first.destroys == 0
        and #h.of_kind("linger") == 1 and #h.damage == 1)
    assert(h.cast())
    h.advance(3.6)
    assert(#h.of_kind("linger") == 6 and #h.damage == 6 and #h.errors == 0)
    assert_ground_hits(h)
end

local visual_failures = {
    {kind = "flight", control = 0}, {kind = "flight", control = 1},
    {kind = "flight", control = 2}, {kind = "flight", control = 3},
    {kind = "flight", create = true}, {kind = "flight", destroy = true},
    {kind = "impact", create = true}, {kind = "impact", control = 0},
    {kind = "impact", control = 1}, {kind = "impact", control = 3},
    {kind = "linger", create = true}, {kind = "linger", control = 0},
    {kind = "linger", control = 1}, {kind = "linger", control = 3},
}
for _, failure in ipairs(visual_failures) do
    local h = harness(1, failure)
    assert(h.cast())
    h.advance(1.6)
    assert(failure.used and #h.errors == 1, "injected visual failure must be caught")
    assert(#h.damage == 5 and h.service.active()["42"] == nil, "visual failure preserves damage and unlock")
    for index, hit in ipairs(h.damage) do
        assert(near(hit.at, 0.8 + (index - 1) / 5), "visual failure cannot change landing damage times")
    end
    assert(next(h.service.visual.active) == nil)
    for _, particle in ipairs(h.particles) do
        assert(particle.releases == 1, "every allocated native root releases exactly once")
        if particle.failed then assert(particle.destroys == 1, "partial visual setup destroys its handle") end
        if particle.kind:find("flight", 1, true) then assert(particle.destroys == 1) end
    end
    for _, kind in ipairs({"impact", "linger"}) do
        local successful = {}
        for _, particle in ipairs(h.of_kind(kind)) do
            if not particle.failed then successful[#successful + 1] = particle end
        end
        assert(#successful == (failure.kind == kind and 4 or 5),
            "a failed complete ground root cannot suppress the other root or any later missile")
        if failure.kind == kind then assert(near(successful[1].at, 1), "the next shell independently retries its ground graph") end
    end
end

-- Execute the real reset while old timers are retained, then reuse token 1.
do
    local h = harness(1)
    assert(h.cast())
    local old_launch, old_impact, old_failsafe = h.queue[3], h.queue[2], h.queue[4]
    h.advance(0.1)
    local old_state, old_particles = h.service.active()["42"], {}
    for _, particle in ipairs(h.particles) do old_particles[#old_particles + 1] = particle end
    h.service.reset()
    assert(h.service.active()["42"] == nil and next(h.service.visual.active) == nil)
    for _, particle in ipairs(old_particles) do assert(particle.destroys == 1 and particle.releases == 1) end
    assert(h.ice_clear_calls == 1, "reset clears Ice Cone through its independent hook")
    assert(h.cast())
    local new_state = h.service.active()["42"]
    assert(old_state.token == new_state.token and old_state ~= new_state,
        "reset intentionally reuses sequence; table identity isolates timers")
    local count_before = #h.particles
    assert(old_launch.callback() == false and old_impact.callback() == false)
    old_failsafe.callback()
    assert(#h.particles == count_before and #h.damage == 0 and h.service.active()["42"] == new_state)
    h.advance(0.2)
    assert(#h.damage == 0, "old scheduled impact cannot damage the new cast")
    h.advance(1.7)
    assert(#h.damage == 5 and #h.errors == 0 and h.service.active()["42"] == nil)
    for _, particle in ipairs(h.particles) do assert(particle.releases == 1) end
end

-- Direct visual clear also invalidates scheduled launch/landing work, without
-- requiring a full game reset or touching the independent Ice Cone state.
do
    local h = harness(1)
    assert(h.cast())
    local stale = {}
    for _, task in ipairs(h.queue) do stale[#stale + 1] = task end
    h.advance(0.1)
    h.service.visual.clear()
    assert(h.service.active()["42"] == nil and next(h.service.visual.active) == nil)
    assert(h.ice_clear_calls == 0)
    assert(h.cast())
    local new_state, count_before = h.service.active()["42"], #h.particles
    for _, task in ipairs(stale) do task.callback() end
    assert(h.service.active()["42"] == new_state and #h.particles == count_before and #h.damage == 0)
    h.advance(1.7)
    assert(#h.damage == 5 and h.service.active()["42"] == nil and #h.errors == 0)
    for _, particle in ipairs(h.particles) do assert(particle.releases == 1) end
end

-- Invalid/nil casters still finish and release every native root.
for _, invalidate in ipairs({"null", "nil"}) do
    local h = harness(1)
    assert(h.cast())
    h.advance(0.1)
    if invalidate == "null" then h.invalidate_attacker() else h.context.attacker = nil end
    h.advance(1.6)
    assert(#h.damage == 0 and #h.of_kind("impact") == 0 and #h.of_kind("linger") == 0)
    assert(h.service.active()["42"] == nil and next(h.service.visual.active) == nil)
    for _, particle in ipairs(h.particles) do assert(particle.destroys == 1 and particle.releases == 1) end
    assert(#h.errors == 0)
end

-- A late scheduler launches overdue shells at half speed and gives each its
-- full flight. The old failsafe must follow the newly extended final deadline.
do
    local h = harness(1)
    assert(h.cast())
    local first_impact, launch, failsafe = h.queue[2], h.queue[3], h.queue[4]
    h.queue, h.now = {}, 2
    assert(launch.callback() == false)
    assert(#h.of_kind("flight") == 5 and #h.damage == 0)
    local state = h.service.active()["42"]
    for index = 2, 5 do
        local particle, missile = h.of_kind("flight")[index], state.missiles[index]
        assert(near(particle.at, 2) and near(particle.controls[2].x, 2250))
        assert(near(missile.land_at, 2.8), "late launches extend landing instead of accelerating")
    end
    first_impact.callback()
    assert(#h.damage == 1)
    assert(first_impact.callback() == false and #h.damage == 1, "one missile cannot hit twice")
    h.now = 2.1
    assert(h.service.locked("42") and near(failsafe.callback(), 1.2),
        "failsafe reschedules past the actual late landing")
    h.advance(2.799)
    assert(#h.damage == 1 and not h.cast())
    h.advance(2.8)
    assert(#h.damage == 5 and h.service.active()["42"] == nil)
    assert(next(h.service.visual.active) == nil and #h.errors == 0)
    for _, particle in ipairs(h.particles) do
        assert(particle.releases == 1)
        if particle.kind == "flight" then assert(particle.destroys == 1) end
    end
end

for _, fallback in ipairs({"expired_lock", "failsafe"}) do
    local h = harness(1)
    assert(h.cast())
    local old_impact, failsafe = h.queue[2], h.queue[4]
    h.advance(0)
    h.queue, h.now = {}, fallback == "expired_lock" and 1.86 or 2.1
    if fallback == "expired_lock" then assert(not h.service.locked("42")) else failsafe.callback() end
    assert(h.service.active()["42"] == nil and next(h.service.visual.active) == nil)
    for _, particle in ipairs(h.particles) do assert(particle.destroys == 1 and particle.releases == 1) end
    assert(old_impact.callback() == false and #h.damage == 0)
    assert(#h.errors == (fallback == "failsafe" and 1 or 0))
end

-- The actual scheduler quantizes launches and landings to 50 ms without
-- shortening any shell's native model lifetime or increasing its speed.
for _, level in ipairs({1, 2, 3, 4, 5}) do
    local h = harness(level, nil, true)
    local per_round = level <= 2 and 5 or 7
    local expected_count = level == 5 and 21 or per_round
    local duration = (level == 5 and 2 or 0) + (per_round - 1) / per_round + 0.8
    assert(h.cast())
    assert(#h.of_kind("flight") == 1, "real scheduler starts the first root synchronously")
    for _, flight in ipairs(h.of_kind("flight")) do assert(flight.at == 0) end
    h.advance(duration + 0.2)
    assert(#h.damage == expected_count and #h.of_kind("impact") == expected_count
        and #h.of_kind("linger") == expected_count)
    assert(#h.of_kind("flight") == expected_count
        and #h.particles == expected_count * 3)
    for index, landing in ipairs(h.damage) do
        local flight = h.of_kind("flight")[index]
        local launch_deadline = math.floor((index - 1) / per_round)
            + ((index - 1) % per_round) / per_round
        assert(flight.at >= launch_deadline - 0.0000001 and flight.at <= launch_deadline + 0.0500001)
        local deadline = flight.at + 0.8
        assert(landing.at >= deadline - 0.0000001 and landing.at <= deadline + 0.0500001)
        assert(#flight.history == 4 and flight.controls[4] == nil)
        assert(flight.destroyed_at - flight.at >= 0.8 - 0.0000001,
            "every native root gets the full descent after its model child's birth delay")
        assert(near(flight.controls[2].x, 2250), "a delayed native launch cannot accelerate")
    end
    assert_ground_hits(h)
    assert(h.service.active()["42"] == nil and next(h.service.visual.active) == nil)
    for _, particle in ipairs(h.particles) do assert(particle.releases == 1) end
    assert(#h.errors == 0 and h.ice_clear_calls == 0)
end

print("ARCANE_NATIVE_SNAPFIRE_PASS:5/5/7/7/21 independent complete native impact+linger roots at every landing, including identical/nearby positions and consecutive casts; no merged ground or duplicate child layers; full0.8s flights, damage150, failures/reset/stale/failsafe/50ms retained (native rendering not simulated)")
