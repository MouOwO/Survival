-- Run the actual ice-cone runner, visual helpers, lock and reset with engine mocks.
package.path = "scripts/vscripts/?.lua;" .. package.path
local definition = assert(require("config/hero_passive_skill_definitions").by_id.proto_ice_cone)
local file = assert(io.open("scripts/vscripts/systems/hero_passive_skill_service.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function between(first_text, last_text)
    local first = assert(source:find(first_text, 1, true), first_text)
    local last = assert(source:find(last_text, first + #first_text, true), last_text)
    return source:sub(first, last - 1)
end
local seam = table.concat({
    "local active_ice_cones = {}; local ice_cone_sequence = 0\n",
    between("local ice_cone_visual =", "local MOVING_ICE_BALL_PARTICLE ="),
    between("local function valid(unit)", "function arcane_snapfire_visual.release_particle(particle)"),
    between("local function ice_cone_locked(attacker_key)", "local sync_meteors"),
    between("local function level_value(definition, field, level, fallback)", "local function owned_passives(player_id)"),
    between("local function unit_position(unit)", "local function normalized_direction(origin, destination, fallback)"),
    between("function ice_cone_visual.release_particle(", "function tornado_visual.release(state)"),
    between("function M.init()", "M._test ="),
    "return {run = run_ice_cone, locked = ice_cone_locked, reset = M.init, visual = ice_cone_visual,",
    "active = function() return active_ice_cones end}",
}, "\n")

local vector_meta = {}
local function vector(x, y, z) return setmetatable({x = x, y = y, z = z}, vector_meta) end
vector_meta.__add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
local function near(a, b) return math.abs(a - b) < 0.000001 end
local function same(a, b) return a and b and near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z) end
local paths = {
    field = "particles/units/heroes/hero_winter_wyvern/wyvern_winters_curse_ground.vpcf",
    flight = "particles/econ/items/snapfire/snapfire_frostivus_2023/snapfire_frostivus_ultimate_lizard_blobs_arced.vpcf",
    impact = "particles/econ/items/snapfire/snapfire_frostivus_2023/snapfire_frostivus_ultimate_impact.vpcf",
}
local landing_delays = {
    linger_shockwave = 0, linger_impact_burst = 0, linger_ground_shockwave = 0,
    linger_impact_glow = 0, linger_torns = 0, linger_ground_sparks = 0.2,
}
for kind in pairs(landing_delays) do
    paths[kind] = "particles/econ/items/snapfire/snapfire_frostivus_2023/snapfire_frostivus_ultimate_"
        .. kind .. ".vpcf"
end
local speed_multiplier = 0.7
local minimum_flight = 0.8 / speed_multiplier
local maximum_flight = 0.96 / speed_multiplier

local function harness(level, options)
    options = options or {}
    local h = {now = 0, queue = {}, next_task = 0, particles = {}, by_index = {},
        damage = {}, buffs = {}, stuns = {}, sounds = {}, errors = {}, random_calls = 0,
        live_flights = 0, max_live_flights = 0, live_fields = 0, max_live_fields = 0}
    local target_position = vector(100, 200, 10)
    local attacker_null = false
    local attacker = {IsNull = function() return attacker_null end, entindex = function() return 42 end}
    local target = {IsNull = function() return false end, GetAbsOrigin = function() return target_position end}
    local enemies = {}
    for index = 1, 2 do
        local enemy = {id = index, living = true, IsNull = function() return false end}
        function enemy:IsAlive() return self.living end
        function enemy:AddNewModifier(source_unit, ability, modifier, parameters)
            assert(source_unit == attacker and ability == nil and self.living)
            assert(modifier == "modifier_hero_ice_cone_freeze" and parameters.duration == 1,
                "successful freezes use the dedicated real stun and complete native unit effect")
            h.stuns[#h.stuns + 1] = {enemy = self.id, at = h.now, modifier = modifier}
        end
        enemies[index] = enemy
    end
    local attributes = {all_attributes = 100}
    h.context = {attacker = attacker, target = target, level = level, attributes = attributes}
    h.invalidate_attacker = function() attacker_null = true end
    h.move_target = function() target_position = vector(10000, 10000, 99) end
    local function enqueue(delay, callback)
        h.next_task = h.next_task + 1
        local at = h.now + delay
        if options.engine_tick then
            at = math.ceil(at / options.engine_tick - 0.0000001) * options.engine_tick
        end
        local item = {at = at, callback = callback, id = h.next_task}
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
    local next_index = options.zero_kind and 1 or 0
    local zero_used = false
    function manager:CreateParticle(path, attach, owner)
        local kind
        for name, expected in pairs(paths) do if path == expected then kind = name end end
        assert(kind, "unexpected ice-cone particle: " .. tostring(path))
        assert(attach == 0 and owner == attacker)
        local failure = options.failure
        if options.fail_all_visuals then error("injected failure of every visual allocation") end
        if failure and failure.kind == kind and failure.create and not failure.used then
            failure.used = true
            error("injected creation failure")
        end
        local index = next_index
        if options.zero_kind == kind and not zero_used then
            index, zero_used = 0, true
        else next_index = next_index + 1 end
        local particle = {index = index, kind = kind, path = path, at = h.now, controls = {},
            forwards = {}, history = {}, destroys = 0, releases = 0}
        assert(h.by_index[index] == nil)
        h.particles[#h.particles + 1], h.by_index[index] = particle, particle
        if kind == "flight" then
            h.live_flights = h.live_flights + 1
            h.max_live_flights = math.max(h.max_live_flights, h.live_flights)
        elseif kind == "field" then
            h.live_fields = h.live_fields + 1
            h.max_live_fields = math.max(h.max_live_fields, h.live_fields)
        end
        return index
    end
    function manager:SetParticleControl(index, control, position)
        local particle = assert(h.by_index[index])
        if particle.kind == "field" then
            assert(control == 0 or control == 2 or control == 61,
                "complete Winter's Curse ground receives its position, XY radius and palette controls")
        elseif particle.kind == "flight" then
            assert(control >= 0 and control <= 3,
                "native Silver Squall arc only receives launch/target/speed/initial-body controls")
        else assert(control == 0 or control == 3, "native landing explosion only receives position controls") end
        local failure = options.failure
        if failure and failure.kind == particle.kind and failure.control == control
            and h.now >= (failure.after or 0) and not failure.used then
            failure.used, particle.failed = true, true
            error("injected control failure")
        end
        particle.controls[control] = vector(position.x, position.y, position.z)
        particle.history[#particle.history + 1] = {
            at = h.now, control = control, position = vector(position.x, position.y, position.z),
        }
    end
    function manager:SetParticleControlForward(index, control, direction)
        assert(control == 3 and same(direction, vector(0, 0, -1)))
        assert(h.by_index[index]).forwards[control] = vector(direction.x, direction.y, direction.z)
    end
    function manager:DestroyParticle(index, immediate)
        local particle = assert(h.by_index[index])
        assert(type(immediate) == "boolean")
        assert(particle.kind == "field" or particle.kind == "flight" or immediate == true,
            "only completed flights and ground fields may play native endcaps")
        particle.destroys, particle.destroyed_at = particle.destroys + 1, h.now
        particle.destroy_immediate = immediate
        if particle.kind == "flight" then h.live_flights = h.live_flights - 1 end
        if particle.kind == "field" then h.live_fields = h.live_fields - 1 end
        local failure = options.failure
        if failure and failure.kind == particle.kind and failure.destroy and not failure.used then
            failure.used, particle.failed = true, true
            error("injected destroy failure")
        end
    end
    function manager:ReleaseParticleIndex(index)
        local particle = assert(h.by_index[index])
        particle.releases = particle.releases + 1
        particle.released_at = h.now
    end
    local noop = function() end
    local env = setmetatable({
        Vector = vector, PATTACH_WORLDORIGIN = 0, ParticleManager = manager,
        GameRules = {GetGameTime = function() return h.now end},
        GetGroundPosition = function(position) return vector(position.x, position.y, 64) end,
        RandomFloat = function(low, high)
            assert(low == 0 and high == 1)
            h.random_calls = h.random_calls + 1
            return h.random_calls % 2 == 1 and 0.1 or 0.9
        end,
        scheduler = {after = enqueue, cancel = cancel},
        M = {sound_service = {reset = noop, play = function(cue)
            h.sounds[#h.sounds + 1] = {cue = cue, at = h.now}
        end}},
        enemies_touching_radius = function(actual_attacker, position, radius)
            assert(actual_attacker == attacker and same(position, vector(100, 200, 64)) and radius == 500,
                "damage keeps its grounded original center and radius 500")
            local result = {}
            for _, enemy in ipairs(enemies) do if enemy.living then result[#result + 1] = enemy end end
            return result
        end,
        deal = function(context, enemy, multiplier, secondary)
            assert(context == h.context and context.attributes == attributes and multiplier == 1 and secondary == false)
            h.damage[#h.damage + 1] = {enemy = enemy.id, at = h.now, amount = attributes.all_attributes * multiplier}
            if options.kill_second and enemy.id == 2 then enemy.living = false end
        end,
        buff_manager = {apply = function(source_unit, enemy, buff, parameters)
            assert(source_unit == attacker and enemy.living and buff == "debuff_hero_ice_cone_attack_slow")
            h.buffs[#h.buffs + 1] = {enemy = enemy.id, at = h.now,
                value = parameters.value, duration = parameters.duration}
        end},
        stun = function() error("generic stun cannot replace the native-effect Ice Cone freeze modifier") end,
        print = function(message) h.errors[#h.errors + 1] = message end,
        definitions = {validate = noop}, exclusive_passives = {init = noop},
        echo_slash = {clear = noop}, earth_rock = {clear = noop}, arcane_snapfire_visual = {clear = noop},
        clear_flame_burns = noop, clear_moving_ice_balls = noop, clear_poison_clouds = noop,
        clear_meteors = noop, clear_magic_slingshot_rubble = noop, clear_tornadoes = noop,
        blade_pulse_projectiles = {}, blade_pulse_visual = {release = noop},
        meteor_explosion_visuals = {}, event_bus = {subscribe = noop}, events = {},
    }, {__index = _G})
    local chunk = assert(loadstring(seam, "@ice_cone_silver_squall_regression"))
    setfenv(chunk, env)
    h.service = chunk()
    function h.cast() return h.service.run(h.context, definition) end
    return h
end

local function assert_complete_landings(h)
    local impacts = h.of_kind("impact")
    for kind, delay in pairs(landing_delays) do
        local layers = h.of_kind(kind)
        assert(#layers == #impacts, "every landing needs the full native " .. kind .. " layer")
        for _, impact in ipairs(impacts) do
            local count = 0
            for _, layer in ipairs(layers) do
                if same(layer.controls[0], impact.controls[0]) then
                    count = count + 1
                    assert(layer.at + 0.000001 >= impact.at + delay
                        and layer.at <= impact.at + delay + 0.050001,
                        "native layer delay must be relative to this shell's actual landing")
                    assert(same(layer.controls[3], impact.controls[0])
                        and layer.releases == 1 and layer.destroys == 0,
                        "native landing layers play and decay naturally at their own landing positions")
                end
            end
            assert(count == 1, "a shell must create each native landing layer exactly once")
        end
    end
end

for _, level in ipairs({1, 2, 3, 4, 5}) do
    local h = harness(level)
    local count, duration = level == 5 and 5 or 3, level == 5 and 5 or 3
    local hail_count = count * 10
    assert(h.cast())
    local original_state = assert(h.service.active()["42"])
    local field = assert(h.of_kind("field")[1])
    assert(h.service.visual.fall_duration_scale == 2
        and h.service.visual.fall_speed_multiplier == speed_multiplier
        and near(h.service.visual.first_impact_delay, minimum_flight))
    assert(#h.service.visual.landing_effects == 6)
    local configured = {}
    for _, effect in ipairs(h.service.visual.landing_effects) do
        for kind, delay in pairs(landing_delays) do
            if effect.particle == paths[kind] then
                assert((effect.delay or 0) == delay and not configured[kind])
                configured[kind] = true
            end
        end
    end
    for kind in pairs(landing_delays) do assert(configured[kind]) end
    assert(original_state.pending_impacts == count)
    assert(h.service.visual.field_duration == 5 and h.service.visual.field_fade_duration == 1
        and near(original_state.field_fade_at, 4),
        "the native ground stops emission at four seconds for its one-second natural fade")
    assert(field.index == 0 and field.releases == 0 and field.destroys == 0)
    assert(#h.damage == 0 and #h.of_kind("impact") == 0 and #h.of_kind("flight") >= 1,
        "the first ten-ball wave begins while damage waits for the slower falling missiles")
    assert(same(field.controls[0], vector(100, 200, 64)) and same(field.controls[2], vector(500, 500, 0)))
    assert(same(field.controls[61], vector(0, 0, 0)) and field.controls[3] == nil
        and field.controls[20] == nil and field.controls[21] == nil,
        "complete native ground sets both radius components and its original blue palette")
    assert(#original_state.hail == hail_count)
    assert(not h.cast() and #h.queue == 3 and #h.sounds == 1)
    h.move_target()
    h.advance(0.2)
    assert(#h.of_kind("flight") == 10 and #h.damage == 0 and #h.of_kind("impact") == 0)
    h.advance(minimum_flight - 0.001)
    assert(#h.of_kind("impact") == 0 and #h.damage == 0 and #h.buffs == 0 and #h.stuns == 0,
        "hail and combat effects wait until the first 70-percent-speed shells can arrive")
    h.advance(original_state.wave_landings[1])
    assert(#h.damage == 2 and original_state.pending_impacts == count - 1,
        "first combat wave follows the slower fall time")
    h.advance(1.55)
    assert(#h.of_kind("impact") == 10 and #h.damage == 2 and #h.of_kind("flight") == 20,
        "first-wave impacts finish while the next ten-ball wave is already falling")
    h.advance(duration - 1)
    assert(#h.damage == (count - 2) * 2)
    assert(h.service.active()["42"] == original_state,
        "the gameplay lock keeps its original three/five-second deadline")
    h.advance(duration - 0.001)
    assert(not h.cast() and #h.of_kind("field") == 1
        and h.live_fields == (duration < 4 and 1 or 0))
    assert(#h.of_kind("flight") == hail_count and #h.damage == (count - 1) * 2,
        "all visual waves launch before expiry while the last combat tick still has its own deadline")
    h.advance(duration)
    assert(h.service.active()["42"] == nil
        and h.live_fields == (duration < 4 and 1 or 0) and h.max_live_fields == 1,
        "cast expiry unlocks gameplay without shortening the independent ground lifetime")
    assert(original_state.cast_finished == true, "cast completion permits already-launched missiles to finish")
    assert(original_state.pending_impacts == 1 and #h.damage == (count - 1) * 2,
        "unlocking must retain the final pending damage wave")
    h.advance(duration + 0.55)
    assert(#h.of_kind("impact") == hail_count
        and h.live_flights == 0 and h.max_live_flights == 20
        and #h.damage == count * 2 and original_state.pending_impacts == 0,
        "all tail missiles land without exceeding the two-wave flight budget")
    assert((h.service.visual.active[original_state] ~= nil) == (duration < 4),
        "a finished cast remains tracked only while its ground handle still needs a natural stop")
    h.advance(math.max(h.now, 4.06, duration + 0.8))
    assert(next(h.service.visual.active) == nil and h.live_fields == 0
        and original_state.snow_particle == nil and original_state.field_fade_at == nil)
    assert_complete_landings(h)
    for index, native_field in ipairs(h.of_kind("field")) do
        assert(index == 1 and near(native_field.at, 0), "complete ground effect is created once without replay")
        assert(native_field.destroys == 1 and native_field.releases == 1
            and native_field.destroy_immediate == false,
            "normal completion requests native endcaps instead of killing the full ground graph")
        assert(native_field.destroyed_at >= 4 and native_field.destroyed_at <= 4.030001
            and near(native_field.released_at, native_field.destroyed_at),
            "stop emission once at four seconds and hand the fading particle to the engine")
        assert(same(native_field.controls[0], vector(100, 200, 64))
            and same(native_field.controls[2], vector(500, 500, 0)), "ground effect keeps the original center and XY radius")
    end
    for index, damage in ipairs(h.damage) do
        local wave = math.floor((index - 1) / 2) + 1
        local earliest
        for _, missile in ipairs(original_state.hail) do
            if missile.wave == wave then earliest = math.min(earliest or math.huge, missile.land_at) end
        end
        assert(near(damage.at, earliest) and near(original_state.wave_landings[wave], earliest)
            and damage.amount == 100,
            "each damage pulse follows its wave's actual first arrival, including the last post-unlock pulse")
    end
    local quadrants, inner, outer, waves = {}, 0, 0, {}
    local function planned_ball(position)
        for _, missile in ipairs(original_state.hail) do
            if near(position.x, missile.position.x) and near(position.y, missile.position.y) then return missile end
        end
        error("visual must correspond to a planned scattered landing")
    end
    for _, particle in ipairs(h.of_kind("impact")) do
        local position = assert(particle.controls[0])
        local missile = planned_ball(position)
        local dx, dy = position.x - 100, position.y - 200
        local distance = math.sqrt(dx * dx + dy * dy)
        assert(distance <= 500.000001 and position.z == 64, "native explosion is placed inside the original skill area")
        quadrants[(dx >= 0 and 1 or 0) + (dy >= 0 and 2 or 0)] = true
        if distance < 200 then inner = inner + 1 end
        if distance > 350 then outer = outer + 1 end
        assert(particle.at + 0.000001 >= missile.land_at and particle.at - missile.land_at <= 0.030001)
        assert(particle.at >= minimum_flight - 0.000001 and particle.at < duration + 0.55)
        local wave = math.floor(missile.launch_at + 0.000001)
        waves[wave] = (waves[wave] or 0) + 1
        assert(missile.launch_at >= wave and missile.launch_at <= wave + 0.072001)
        assert(missile.land_at >= wave + minimum_flight
            and missile.land_at <= wave + 0.072 + 0.03 + maximum_flight + 0.000001)
        assert(particle.at <= wave + 0.072 + 0.06 + maximum_flight + 0.000001,
            "all ten landings retain their full 70-percent-speed flight interval")
        assert(same(particle.controls[3], position) and particle.controls[20] == nil)
        assert(particle.forwards[3] == nil and particle.destroys == 0 and particle.releases == 1)
    end
    assert(quadrants[0] and quadrants[1] and quadrants[2] and quadrants[3] and inner > 0 and outer > 0,
        "the blizzard must fill the disk, rather than land at a single center")
    for wave = 0, count - 1 do assert(waves[wave] == 10, "each damage wave has exactly ten visual missiles") end
    assert(waves[count] == nil)
    for _, particle in ipairs(h.of_kind("flight")) do
        local first_position
        for _, sample in ipairs(particle.history) do
            if sample.control == 0 then first_position = sample.position; break end
        end
        local missile = planned_ball(assert(first_position))
        assert(particle.at + 0.000001 >= missile.launch_at and particle.at - missile.launch_at <= 0.030001)
        assert(particle.destroys == 1 and particle.releases == 1 and particle.destroy_immediate == false,
            "successful arrivals preserve the complete native projectile endcap")
        assert(particle.destroyed_at + 0.000001 >= missile.land_at and particle.destroyed_at < duration + 0.55)
        assert(missile.height >= 1800 and missile.height <= 2200)
        local flight_time = missile.land_at - particle.at
        assert(flight_time >= minimum_flight - 0.000001 and flight_time <= maximum_flight + 0.000001
            and near(flight_time, missile.travel_duration), "scheduler delay cannot shorten the slower travel duration")
        assert(particle.controls[20] == nil and particle.controls[4] == nil)
        assert(same(particle.controls[0], missile.position + vector(0, 0, missile.height))
            and same(particle.controls[3], particle.controls[0]) and same(particle.controls[1], missile.position))
        assert(same(particle.controls[2], vector(missile.height / flight_time, 0, 0)),
            "native arc speed always uses the full planned travel duration")
        local written = {}
        for _, sample in ipairs(particle.history) do
            written[sample.control] = (written[sample.control] or 0) + 1
            assert(near(sample.at, particle.at), "native projectile control points are initialized once, with no competing per-frame mover")
        end
        for control = 0, 3 do assert(written[control] == 1, "native arc owns control updates after setup") end
    end
    assert(#h.buffs == (level >= 2 and count * 2 or 0))
    for _, buff in ipairs(h.buffs) do
        assert(buff.value == (level == 5 and -40 or -20) and buff.duration == 3)
    end
    assert(#h.stuns == (level >= 3 and count or 0) and h.random_calls == (level >= 3 and count * 2 or 0),
        "cosmetic hail consumes no gameplay RNG and preserves each target's freeze roll")
    for _, stun in ipairs(h.stuns) do assert(stun.enemy == 1) end
    assert(#h.errors == 0)
    local particles_before, damage_before = #h.particles, #h.damage
    h.advance(h.now + 0.5)
    assert(#h.particles == particles_before and #h.damage == damage_before, "finished tails do not restart after expiry")
    assert(h.cast(), "cast becomes available at its original unlock deadline")
end

-- The real scheduler advances in 50ms frames, despite the visual's 30ms request.
do
    local h = harness(5, {engine_tick = 0.05})
    assert(h.cast())
    local state = h.service.active()["42"]
    local field = h.of_kind("field")[1]
    h.advance(3.999)
    assert(field.destroys == 0 and field.releases == 0 and h.live_fields == 1)
    h.advance(4.05)
    assert(field.destroys == 1 and field.destroy_immediate == false and field.releases == 1
        and field.destroyed_at >= 4 and field.destroyed_at <= 4.050001)
    assert(h.service.active()["42"] == state and h.service.visual.active[state]
        and not h.cast(), "the ground's fade does not shorten the level-five gameplay lock")
    h.advance(5)
    assert(h.max_live_fields == 1 and h.live_fields == 0)
    h.advance(5.55)
    assert(#h.of_kind("flight") == 50 and #h.of_kind("impact") == 50 and #h.of_kind("field") == 1)
    assert(#h.damage == 10 and h.random_calls == 10 and h.max_live_flights <= 20 and h.live_flights == 0)
    for _, missile in ipairs(state.hail) do
        assert(near(missile.land_at - missile.flight_started_at, missile.travel_duration)
            and missile.travel_duration >= minimum_flight and missile.travel_duration <= maximum_flight,
            "50ms launch lateness must not accelerate any projectile")
        local found
        for _, particle in ipairs(h.of_kind("flight")) do
            if same(particle.controls[1], missile.position) then found = particle; break end
        end
        assert(found and near(found.controls[2].x, missile.height / missile.travel_duration))
    end
    assert(h.service.active()["42"] == nil and #h.errors == 0)
    for index, damage in ipairs(h.damage) do
        local earliest = state.wave_landings[math.floor((index - 1) / 2) + 1]
        assert(damage.at + 0.000001 >= earliest and damage.at <= earliest + 0.050001,
            "50ms damage scheduling cannot precede the earliest real shell deadline")
    end
    h.advance(5.8)
    assert_complete_landings(h)
end

-- Damage that kills a target must not apply attack slow or freeze afterward.
do
    local h = harness(5, {kill_second = true})
    assert(h.cast())
    assert(#h.damage == 0 and #h.buffs == 0 and #h.stuns == 0)
    h.advance(0.2)
    h.advance(h.service.active()["42"].wave_landings[1])
    assert(#h.damage == 2 and #h.buffs == 1 and #h.stuns == 1 and h.random_calls == 1)
    assert(h.buffs[1].enemy == 1 and h.stuns[1].enemy == 1)
end

for _, failure in ipairs({
    {kind = "field", control = 61}, {kind = "impact", control = 3},
    {kind = "flight", control = 3}, {kind = "flight", control = 1, after = 0.04},
    {kind = "field", create = true}, {kind = "impact", create = true},
    {kind = "flight", create = true}, {kind = "flight", destroy = true},
    {kind = "field", destroy = true},
}) do
    local h = harness(3, {failure = failure, zero_kind = failure.kind})
    assert(h.cast())
    h.advance(4.2)
    assert(failure.used and #h.errors == 1 and #h.damage == 6 and #h.buffs == 6 and #h.stuns == 3)
    assert(h.service.active()["42"] == nil and next(h.service.visual.active) == nil and h.live_flights == 0)
    for _, particle in ipairs(h.particles) do
        assert(particle.releases == 1, "visual errors preserve exactly one release for all allocated handles")
        if particle.failed then assert(particle.destroys == 1) end
        if particle.kind == "field" then
            assert(particle.destroy_immediate == (failure.kind == "field" and failure.control ~= nil),
                "partial field creation is discarded immediately; completed fields still stop naturally")
        end
    end
end

-- Every native landing layer fails independently: other layers and gameplay
-- must still run, and partially configured handles are cleaned exactly once.
for kind in pairs(landing_delays) do
    for _, stage in ipairs({"create", "control"}) do
        local failure = {kind = kind}
        if stage == "create" then failure.create = true else failure.control = 3 end
        local h = harness(3, {failure = failure, zero_kind = kind})
        assert(h.cast())
        h.advance(4.2)
        assert(failure.used and #h.errors == 1 and #h.damage == 6
            and #h.buffs == 6 and #h.stuns == 3 and #h.of_kind("impact") == 30)
        for other_kind in pairs(landing_delays) do
            local expected = other_kind == kind and stage == "create" and 29 or 30
            assert(#h.of_kind(other_kind) == expected,
                "one failed native layer cannot suppress any other missile or effect")
        end
        for _, particle in ipairs(h.particles) do
            assert(particle.releases == 1)
            if particle.failed then assert(particle.destroys == 1 and particle.destroy_immediate == true) end
        end
    end
end

-- No successful particle handle is required to deliver the final damage wave.
-- Explicit cancellation after unlock must still cancel that pending gameplay.
for _, level in ipairs({1, 5}) do
    for _, ending in ipairs({"natural", "reset", "clear", "invalid"}) do
        local h = harness(level, {fail_all_visuals = true})
        local count = level == 5 and 5 or 3
        assert(h.cast())
        local state = h.service.active()["42"]
        h.advance(count)
        assert(#h.particles == 0 and #h.damage == (count - 1) * 2
            and h.service.active()["42"] == nil and h.service.visual.active[state]
            and state.pending_impacts == 1,
            "the final damage wave survives unlock even when every visual allocation fails")
        if ending == "reset" then h.service.reset()
        elseif ending == "clear" then h.service.visual.clear()
        elseif ending == "invalid" then h.invalidate_attacker() end
        h.advance(count + 0.6)
        assert(#h.damage == (ending == "natural" and count or count - 1) * 2
            and next(h.service.visual.active) == nil and #h.particles == 0)
        if ending == "natural" then assert(state.pending_impacts == 0) end
    end
end

-- A cast started immediately at the old unlock deadline keeps both sets of
-- pending damage and delayed native landing layers attached to their own cast.
do
    local h = harness(1)
    assert(h.cast())
    local old_state = h.service.active()["42"]
    h.advance(3)
    assert(#h.damage == 4 and old_state.pending_impacts == 1 and h.cast())
    local new_state = h.service.active()["42"]
    assert(new_state ~= old_state and new_state.pending_impacts == 3)
    h.advance(3.6)
    assert(#h.damage == 6 and old_state.pending_impacts == 0
        and new_state.pending_impacts == 3 and h.service.active()["42"] == new_state)
    h.advance(4.6)
    assert(#h.damage == 8 and new_state.pending_impacts == 2,
        "old final damage cannot consume or replace the new cast's first wave")
    h.advance(7.8)
    assert(#h.damage == 12 and #h.of_kind("impact") == 60
        and next(h.service.visual.active) == nil and h.live_flights == 0 and h.live_fields == 0)
    assert_complete_landings(h)
end

-- Delayed native sparks outlive normal state retirement/recast, but clear,
-- reset and invalid owners must prevent an already queued callback from firing.
for _, ending in ipairs({"natural", "recast", "clear", "reset", "invalid"}) do
    local h = harness(1)
    local position = vector(100, 200, 64)
    h.service.visual.landing(h.context.attacker, position, 75)
    assert(#h.of_kind("impact") == 1 and #h.of_kind("linger_ground_sparks") == 0)
    for kind, delay in pairs(landing_delays) do
        if delay == 0 then assert(#h.of_kind(kind) == 1) end
    end
    if ending == "clear" then h.service.visual.clear()
    elseif ending == "reset" then h.service.reset()
    elseif ending == "invalid" then h.invalidate_attacker()
    elseif ending == "recast" then assert(h.cast()) end
    h.advance(0.199)
    assert(#h.of_kind("linger_ground_sparks") == 0)
    h.advance(0.2)
    local expected = ending == "natural" or ending == "recast"
    assert(#h.of_kind("linger_ground_sparks") == (expected and 1 or 0),
        "delayed ice debris must honor generation reset and owner validity without depending on an active cast")
    if expected then
        local sparks = h.of_kind("linger_ground_sparks")[1]
        assert(near(sparks.at, 0.2) and same(sparks.controls[0], position)
            and sparks.releases == 1 and sparks.destroys == 0)
    end
end

-- Actual reset cleans all hail and ignores old timers even when token 1 is reused.
do
    local h = harness(1)
    assert(h.cast())
    local old_visual, old_damage, old_release = h.queue[1], h.queue[2], h.queue[3]
    h.advance(0.2)
    local old_state = h.service.active()["42"]
    h.service.reset()
    assert(h.service.active()["42"] == nil and next(h.service.visual.active) == nil and h.live_flights == 0)
    for _, particle in ipairs(h.particles) do assert(particle.releases == 1) end
    assert(h.cast())
    local new_state = h.service.active()["42"]
    assert(new_state ~= old_state and new_state.token == old_state.token)
    local damage_before, particles_before = #h.damage, #h.particles
    assert(old_visual.callback() == false and old_damage.callback() == false)
    old_release.callback()
    assert(#h.damage == damage_before and #h.particles == particles_before and h.service.active()["42"] == new_state)
    h.advance(0.99)
    assert(#h.damage == damage_before, "old delayed damage must not affect a reset cast")
    h.advance(3.8)
    assert(#h.damage == 6 and #h.of_kind("impact") == 30 and h.service.active()["42"] == nil and #h.errors == 0)
    assert(h.live_fields == 1, "reset cast's field keeps its own four-second stop deadline")
    h.advance(4.4)
    assert(h.live_fields == 0 and next(h.service.visual.active) == nil)
    for _, particle in ipairs(h.particles) do assert(particle.releases == 1) end
    assert(h.of_kind("field")[1].destroy_immediate == true
        and h.of_kind("field")[2].destroy_immediate == false)
end

do
    local h = harness(1)
    assert(h.cast())
    h.advance(0.2)
    h.invalidate_attacker()
    h.advance(0.24)
    local particles_before = #h.particles
    assert(next(h.service.visual.active) == nil and h.live_flights == 0 and #h.of_kind("impact") == 0)
    assert(h.service.active()["42"] ~= nil, "visual cleanup must retain the original gameplay lock")
    h.advance(3)
    assert(#h.damage == 0 and #h.particles == particles_before and h.service.active()["42"] == nil)
    for _, particle in ipairs(h.particles) do assert(particle.releases == 1) end
    assert(h.of_kind("field")[1].destroy_immediate == true,
        "invalid owners immediately discard still-owned ground handles")
    assert(#h.errors == 0)
end

-- A severe hitch drops overdue cosmetic events instead of dumping explosions.
do
    local h = harness(1)
    assert(h.cast())
    local visual, delayed_damage, expiry = h.queue[1], h.queue[2], h.queue[3]
    h.queue, h.now = {}, 2.5
    visual.callback()
    assert(#h.of_kind("impact") == 0, "old in-flight balls must not dump late explosions")
    assert(#h.damage == 0 and h.max_live_flights <= 20)
    local particles_before = #h.particles
    h.now = 3
    expiry.callback()
    visual.callback()
    assert(#h.particles == particles_before and h.live_flights == 0 and h.live_fields == 1,
        "discarding overdue tails cannot cut the remaining ground lifetime")
    h.now = 4.2
    visual.callback()
    assert(next(h.service.visual.active) ~= nil and h.live_fields == 0,
        "pending gameplay ticks keep their state even after all cosmetic handles end")
    local field = h.of_kind("field")[1]
    assert(field.destroy_immediate == false and field.destroys == 1 and field.releases == 1,
        "a late visual update still requests the native fade rather than a hard cutoff")
    for _, particle in ipairs(h.of_kind("flight")) do
        assert(particle.destroy_immediate == true, "severely overdue shells must not play late native endcaps")
    end
    assert(type(delayed_damage.callback()) == "number")
    assert(type(delayed_damage.callback()) == "number")
    assert(delayed_damage.callback() == false and #h.damage == 6)
    visual.callback()
    assert(next(h.service.visual.active) == nil)
end

-- The public lock predicate unlocks without discarding pending damage;
-- explicit clear still cancels it and discards every owned particle handle.
do
    local h = harness(1)
    assert(h.cast())
    local old_damage = h.queue[2]
    h.advance(0.2)
    h.queue, h.now = {}, 3
    assert(not h.service.locked("42") and h.service.active()["42"] == nil and h.live_fields == 1)
    assert(type(old_damage.callback()) == "number" and #h.damage == 2,
        "the unlocked old cast retains its pending damage callback")
    h.service.visual.clear()
    assert(h.live_flights == 0 and next(h.service.visual.active) == nil)
    for _, particle in ipairs(h.particles) do assert(particle.releases == 1) end
    assert(h.live_fields == 0 and h.of_kind("field")[1].destroy_immediate == true)
    assert(old_damage.callback() == false and #h.damage == 2,
        "clearing the visual registry cancels old gameplay callbacks too")
end

-- Force legal long flights at the end of a cast: only the lock expires first.
-- Reset/recast must see tails and ground held only by the visual registry.
for _, ending in ipairs({"natural", "reset", "recast", "expired_lock"}) do
    local h = harness(1, {engine_tick = 0.05})
    assert(h.cast())
    local old_state = h.service.active()["42"]
    for _, missile in ipairs(old_state.hail) do
        if missile.launch_at >= 2 then missile.travel_duration = maximum_flight end
    end
    h.advance(2.95)
    if ending == "expired_lock" then
        h.now = 3
        assert(not h.service.locked("42"))
    end
    h.advance(3)
    local old_field = h.of_kind("field")[1]
    assert(h.service.active()["42"] == nil and old_state.cast_finished == true and h.live_fields == 1
        and old_field.destroys == 0 and old_field.releases == 0)
    assert(h.live_flights > 0 and h.service.visual.active[old_state],
        "already-launched tail missiles and the ground survive cast-lock expiry")
    local old_tail = {}
    for _, particle in ipairs(h.of_kind("flight")) do
        if particle.destroys == 0 then old_tail[#old_tail + 1] = particle end
    end
    local impacts_before = #h.of_kind("impact")
    if ending == "reset" then
        h.service.reset()
        assert(h.live_flights == 0 and next(h.service.visual.active) == nil,
            "reset must clear visual-only tails after the gameplay state has expired")
    elseif ending == "recast" then
        assert(h.cast(), "tail missiles do not extend the cast lock")
        assert(h.service.active()["42"] ~= old_state and h.live_fields == 2,
            "a newly available cast may overlap the old ground's remaining lifetime")
    end
    h.advance(3.55)
    assert((h.service.visual.active[old_state] ~= nil) == (ending ~= "reset"),
        "finishing the old tail does not discard its still-owned ground handle")
    assert(#h.of_kind("impact") == (ending == "reset" and impacts_before or 30),
        "all launched tails land once unless an explicit reset cancels them")
    for _, particle in ipairs(old_tail) do
        assert(particle.destroys == 1 and particle.releases == 1
            and particle.destroy_immediate == (ending == "reset"))
        if ending ~= "reset" then assert(particle.destroyed_at > 3) end
    end
    assert(#h.damage == (ending == "reset" and 4 or 6) and #h.errors == 0,
        "only an explicit reset cancels the old cast's post-unlock damage")
    h.advance(4.1)
    assert(h.service.visual.active[old_state] == nil and old_field.destroys == 1 and old_field.releases == 1
        and old_field.destroy_immediate == (ending == "reset"))
    if ending == "recast" then
        local new_field = h.of_kind("field")[2]
        assert(h.service.active()["42"] and h.live_fields == 1 and new_field.destroys == 0
            and new_field.releases == 0, "old ground's soft stop cannot clear the new cast or field")
        h.service.reset()
        assert(old_field.destroys == 1 and old_field.releases == 1 and new_field.destroy_immediate == true,
            "reset does not destroy the already released native fade a second time")
    end
end

print("ICE_CONE_NATIVE_PASS:70-percent-speed complete Silver Squall shells/endcaps plus30/50 full landing bursts and delayed debris; earliest-wave damage survives3/5s unlock and visual failures;4s ground soft-stop,50ms/reset/recast cleanup (native rendering not simulated)")
