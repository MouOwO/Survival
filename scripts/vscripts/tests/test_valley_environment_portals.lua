package.path = "scripts/vscripts/?.lua;" .. package.path
local pending = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, key)
        pending[#pending + 1] = { delay = delay, callback = callback, key = key }
    end,
}
local function run_pending()
    local queued = pending
    pending = {}
    for _, task in ipairs(queued) do task.callback() end
end
local function vector(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
    })
end
local function near(a, b) assert(math.abs(a - b) < 1e-8, tostring(a) .. " ~= " .. tostring(b)) end
Vector = vector
PATTACH_ABSORIGIN_FOLLOW, PATTACH_POINT_FOLLOW, PATTACH_WORLDORIGIN = 1, 2, 3
local world, map, mode = {}, "template_map", nil
GameRules = { GetGameModeEntity = function() return world end }
GetMapName = function() return map end
local players, connection_states, engine_listeners, listener_serial = {}, {}, {}, 0
DOTA_MAX_TEAM_PLAYERS = 24
DOTA_CONNECTION_STATE_CONNECTED = 2
PlayerResource = {
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
    GetPlayer = function(_, id) return players[id] end,
    GetConnectionState = function(_, id) return connection_states[id] or 0 end,
}
ListenToGameEvent = function(name, callback)
    assert(name == "player_connect_full")
    listener_serial = listener_serial + 1
    engine_listeners[listener_serial] = {callback = callback, world = world, name = name}
    return listener_serial
end
StopListeningToGameEvent = function(id)
    assert(engine_listeners[id], "only unsubscribe a live engine listener")
    assert(engine_listeners[id].world == world, "never unsubscribe another world's recycled listener ID")
    engine_listeners[id] = nil
end
local function connect(id)
    players[id] = players[id] or {}
    connection_states[id] = DOTA_CONNECTION_STATE_CONNECTED
    local count = 0
    for _, listener in pairs(engine_listeners) do
        if listener.world == world and listener.name == "player_connect_full" then
            count = count + 1
            listener.callback({ PlayerID = id })
        end
    end
    assert(count == 1, "hot reload must leave exactly one player-connect listener")
end
package.loaded["systems/match_setup_service"] = { get_mode = function() return mode end }
local positions = {
    standard = { vector(88, 4096, 777), vector(-1024, 2984, 777),
        vector(-2136, 4096, 777), vector(-1024, 5208, 777) },
    rich = {}, cold = {}, scourge = {},
}
for index, name in ipairs({"rich", "cold", "scourge"}) do
    for lane = 1, 4 do positions[name][lane] = vector(index * 10000 + lane * 200, lane * -1000, 999) end
end
GetGroundHeight = function(position)
    -- Marker Z is intentionally wrong: portal clearance must follow terrain.
    return position.x > 10000 and 256 or 128
end
local expected = { {1, 0, 0}, {0, -1, 270}, {-1, 0, 180}, {0, 1, 90} }
local missing, searches, missing_rich = nil, {}, false
local rich_center = vector(33333, -44444, 9999)
Entities = { FindByName = function(_, _, name)
    searches[#searches + 1] = name
    if name == "rich_start" then
        if not missing_rich then return { GetAbsOrigin = function() return rich_center end } end
        return nil
    end
    local name_mode, zero_lane = name:match("^mode_(%a+)_monster_(%d)_spawn$")
    local lane = tonumber(name:match("^monsterborn_player(%d)$"))
    if zero_lane then lane = tonumber(zero_lane) + 1 end
    if lane and lane ~= missing then
        local point = assert(positions[name_mode or "standard"])[lane]
        return { GetAbsOrigin = function() return point end }
    end
    if name:find("^valley_decor_v1_fx_") then return { old = true } end
end }
local props, particles, precached = {}, {}, { particle = {} }
local stops, destroyed, removed = 0, 0, 0
local fail_create
SpawnEntityFromTableSynchronous = function(class, kv)
    assert(class == "prop_dynamic" and kv.solid == 0, "portal must not block units")
    assert(kv.DefaultAnim == "au_portal_chanelling")
    assert(kv.model == "models/heroes/abyssal_underlord/abyssal_underlord_portal_model.vmdl")
    local prop = { kv = kv, world = world }
    function prop:IsNull() return self.removed == true end
    function prop:SetAbsOrigin(value) self.position = value end
    function prop:SetAngles(pitch, yaw, roll)
        assert(roll == 0)
        self.pitch, self.yaw = pitch, yaw
    end
    props[#props + 1] = prop
    return prop
end
UTIL_Remove = function(prop)
    assert(not prop.removed and prop.world == world, "never remove another world's handles")
    prop.removed = true; removed = removed + 1
end
DoEntFireByInstanceHandle = function(entity, command, value)
    if entity.old then assert(command == "Stop"); stops = stops + 1
    else assert(command == "SetAnimation" and value == "au_portal_chanelling") end
end
PrecacheResource = function(kind, path)
    if kind == "particle" then precached.particle[path] = true else precached[kind] = path end
end
local native_effect = "particles/units/heroes/heroes_underlord/abbysal_underlord_portal_ambient.vpcf"
local rich_effect = "particles/survival_environment/rich_portal/ambient.vpcf"
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        if fail_create then error("injected create failure") end
        assert(path == native_effect or path == rich_effect, "use reviewed portal resources only")
        assert(attach == PATTACH_WORLDORIGIN and owner == nil,
            "static spawn effects must not inherit a dormant prop's visibility or attachment")
        local id = #particles + 1
        particles[id] = { path = path, owner = owner, cp = {}, bindings = {}, orientation = {}, world = world }
        return id
    end,
    SetParticleControl = function(_, id, cp, value) particles[id].cp[cp] = value end,
    SetParticleAlwaysSimulate = function(_, id) particles[id].always_simulate = true end,
    SetParticleShouldCheckFoW = function(_, id, check) particles[id].check_fow = check end,
    SetParticleControlEnt = function()
        error("spawn landmarks must not depend on a prop attachment being evaluated")
    end,
    SetParticleControlOrientation = function(_, id, cp, forward, right, up)
        near(forward.x * right.x + forward.y * right.y + forward.z * right.z, 0)
        near(forward.x * up.x + forward.y * up.y + forward.z * up.z, 0)
        near(right.x * up.x + right.y * up.y + right.z * up.z, 0)
        for _, axis in ipairs({forward, right, up}) do near(axis.x^2 + axis.y^2 + axis.z^2, 1) end
        particles[id].orientation[cp] = { forward = forward, right = right, up = up }
    end,
    DestroyParticle = function(_, id, immediate)
        local p = particles[id]
        assert(immediate and not p.destroyed and p.world == world, "never destroy another world's indices")
        p.destroyed = true; destroyed = destroyed + 1
    end,
    ReleaseParticleIndex = function(_, id)
        assert(particles[id].destroyed and not particles[id].released)
        particles[id].released = true
    end,
}
local bus, events = require("core/event_bus"), require("core/events")
local service = require("systems/valley_environment_service")
local function check_last_four(name)
    local flat = name ~= "standard"
    for lane, direction in ipairs(expected) do
        local prop, particle = props[#props - 4 + lane], particles[#particles - 4 + lane]
        local marker, axes = positions[name][lane], particle.orientation[0]
        assert(particle.path == native_effect)
        assert(particle.always_simulate and particle.check_fow == false,
            "static spawn landmarks must remain visible after off-screen sleep or unit-vision culling")
        assert(prop.yaw == direction[3] and prop.pitch == (flat and -90 or 0))
        assert(prop.kv.angles == string.format("%d %d 0", prop.pitch, prop.yaw))
        local attachment = assert(particle.cp[1])
        -- Compute the real model attachment's transformed local Z, rather
        -- than accepting a centered fallback while the actual model is offset.
        local model_up = flat and vector(-direction[1], -direction[2], 0) or vector(0, 0, 1)
        local actual = vector(prop.position.x + model_up.x * 97.362,
            prop.position.y + model_up.y * 97.362, prop.position.z + model_up.z * 97.362)
        near(actual.x, marker.x); near(actual.y, marker.y)
        near(actual.z, GetGroundHeight(marker) + 12 + (flat and 0 or 97.362))
        near(attachment.x, actual.x); near(attachment.y, actual.y)
        near(attachment.z, actual.z)
        near(particle.orientation[1].forward.x, axes.forward.x)
        near(particle.orientation[1].forward.y, axes.forward.y)
        near(particle.orientation[1].forward.z, axes.forward.z)
        near(particle.orientation[1].up.x, model_up.x)
        near(particle.orientation[1].up.y, model_up.y)
        near(particle.orientation[1].up.z, model_up.z)
        near(axes.forward.z, flat and 1 or 0)
        if not flat then near(axes.forward.x, direction[1]); near(axes.forward.y, direction[2]) end
        for _, cp in ipairs({0, 2}) do
            near(particle.orientation[cp].forward.z, axes.forward.z)
            near(particle.orientation[cp].up.x, model_up.x)
            near(particle.orientation[cp].up.y, model_up.y)
            near(particle.orientation[cp].up.z, model_up.z)
            near(particle.orientation[cp].right.x, direction[2])
            near(particle.orientation[cp].right.y, -direction[1])
            near(particle.cp[cp].x, prop.position.x); near(particle.cp[cp].z, prop.position.z)
        end
        assert(particle.cp[4].x == 0 and particle.cp[61].x == 0 and particle.cp[62].x == 0)
        assert(marker.z == (flat and 999 or 777), "must not move the gameplay spawn marker")
    end
end
local function check_rich()
    local particle = particles[#particles]
    assert(particle.path == rich_effect and particle.owner == nil)
    assert(particle.always_simulate and particle.check_fow == false)
    for _, cp in ipairs({0, 1, 2}) do
        local position = assert(particle.cp[cp], "rich portal must explicitly anchor every spatial control point")
        near(position.x, rich_center.x); near(position.y, rich_center.y)
        near(position.z, GetGroundHeight(rich_center) + 12)
        near(particle.orientation[cp].forward.z, 1)
    end
    assert(particle.cp[4].x == 0 and particle.cp[61].x == 0 and particle.cp[62].x == 0)
    assert(rich_center.z == 9999, "rich portal must not move the mode's gameplay marker")
end
local function live_counts()
    local live_props, live_particles = 0, 0
    for _, prop in ipairs(props) do
        if prop.world == world and not prop.removed then live_props = live_props + 1 end
    end
    for _, particle in ipairs(particles) do
        if particle.world == world and not particle.destroyed then live_particles = live_particles + 1 end
    end
    return live_props, live_particles
end
local function assert_live(expected_props, expected_particles)
    local actual_props, actual_particles = live_counts()
    assert(actual_props == expected_props and actual_particles == expected_particles,
        string.format("live props/particles %d/%d ~= %d/%d", actual_props, actual_particles,
            expected_props, expected_particles))
end
local function ready(event, id) bus.emit(event, {player_id = id}) end
service.precache({})
assert(precached.model and precached.particle[native_effect] and precached.particle[rich_effect])
-- Particle creation before the first client has a recipient can produce a
-- valid server handle and visible model while losing all client emitters.
players[0] = {} -- A player entity during loading is not yet a connected recipient.
service.init(); run_pending()
assert(#props == 0 and #particles == 0 and stops == 0,
    "initialization without a connected player must not spend the first particle creation")
mode = "cold"; bus.emit(events.WAVE_CHANGED, {reason="mode_selected"})
assert(#particles == 0, "mode changes must also wait for a client recipient")
mode = nil
connect(0)
assert(#particles == 0, "full-connect must defer creation until its recipient is ready")
near(pending[#pending].delay, 0.2)
run_pending()
assert(#props == 4 and #particles == 4 and stops == 4)
check_last_four("standard"); assert_live(4, 4)
local before = #particles
bus.emit(events.WAVE_CHANGED, {reason="countdown_tick"})
bus.emit(events.BUILDER_READY, {})
bus.emit(events.HERO_READY, {})
assert(#particles == before, "ordinary wave and unowned readiness events must not recreate portals")
ready(events.BUILDER_READY, 0); run_pending()
assert(#particles == before + 4, "first player readiness must recover an earlier connect event")
before = #particles
ready(events.BUILDER_READY, 0); ready(events.HERO_READY, 0); run_pending()
assert(#particles == before, "builder and hero readiness share one refresh per player")
players[1] = {}; connection_states[1] = DOTA_CONNECTION_STATE_CONNECTED
ready(events.HERO_READY, 1); run_pending()
assert(#particles == before + 4, "a new player's readiness must refresh even in the same mode")
before = #particles
connect(2); run_pending()
assert(#particles == before + 4, "joining the same mode must deliver persistent landmarks to the new client")
before = #particles
connect(0); run_pending()
assert(#particles == before + 4, "reconnecting an existing player must re-deliver unchanged-mode particles")
assert_live(4, 4)
local before_props = #props
before = #particles
mode = "rich"; bus.emit(events.WAVE_CHANGED, {reason="mode_selected"})
assert(#props == before_props and #particles == before + 1,
    "rich replaces the four lane assemblies with one model-free center effect")
check_rich(); assert_live(0, 1)
for _, name in ipairs(searches) do
    assert(not name:match("^mode_rich_monster_"), "rich art must use rich_start instead of four monster lane markers")
end
before = #particles
bus.emit(events.WAVE_CHANGED, {reason="countdown_tick"}); bus.emit(events.BUILDER_READY, {})
assert(#particles == before, "normal wave and builder events must not recreate particle effects")
mode = "cold"; bus.emit(events.BUILDER_READY, {})
assert(#particles == before + 4); check_last_four("cold"); assert_live(4, 4)
mode = "scourge"; bus.emit(events.WAVE_CHANGED, {})
check_last_four("scourge"); assert_live(4, 4)
service.clear(); service.clear()
assert_live(0, 0)
local old_removed, old_destroyed = removed, destroyed
service.clear()
assert(removed == old_removed and destroyed == old_destroyed, "cleanup is idempotent")
missing, searches = 2, {}
assert(service.apply() == 3, "missing advanced marker must not borrow a normal lane")
for _, name in ipairs(searches) do assert(not name:match("^monsterborn_player")) end
service.clear(); missing = nil
mode, missing_rich, searches = "rich", true, {}
before = #props
assert(service.apply() == 0, "a missing rich center must not create lane or fallback portals")
assert(#props == before); assert_live(0, 0)
for _, name in ipairs(searches) do assert(not name:match("^mode_rich_monster_") and not name:match("^monsterborn_player")) end
mode, missing_rich = "cold", false
fail_create = true
assert(service.apply() == 0 and props[#props].removed, "failed particle must clean up model")
fail_create = nil
service.init()
local previous = pending[#pending].callback
service.init()
before = #props
previous(); assert(#props == before, "stale init callback must not create portals")
run_pending(); assert(#props == before + 4)
-- An actual module reload must retire the effects and subscriptions owned by
-- the earlier module instance without allowing its queued callback to reapply.
service.init(); previous = pending[#pending].callback
package.loaded["systems/valley_environment_service"] = nil
service = require("systems/valley_environment_service")
service.init(); before = #props
previous(); assert(#props == before)
run_pending(); assert(#props == before + 4)
before = #particles
mode = "rich"; bus.emit(events.WAVE_CHANGED, {})
assert(#particles == before + 1, "hot reload must leave only one active refresh subscriber")
before = #particles
connect(0); run_pending()
assert(#particles == before + 1, "hot reload must also retire the old engine connect listener")
old_removed, old_destroyed = removed, destroyed
connect(0)
local recycled_listener
for id, listener in pairs(engine_listeners) do
    if listener.name == "player_connect_full" then recycled_listener = id end
end
world = {}; players = {}; connection_states = {}
-- Engine event registrations die with their map. Their numeric IDs may then
-- belong to another system: init must discard old ownership without stopping
-- that new world's reused ID, just as it discards old particles and props.
engine_listeners = { [recycled_listener] = {world = world, name = "foreign_new_world_listener"} }
listener_serial = recycled_listener
service.clear(); service.init(); run_pending()
assert(engine_listeners[recycled_listener], "new-world init must preserve a recycled foreign listener")
assert(removed == old_removed and destroyed == old_destroyed, "new world must discard old handles")
assert_live(0, 0)
connect(0); run_pending(); assert_live(0, 1); check_rich()
bus.reset(); service.init(); run_pending()
mode = "cold"; before = #props; bus.emit(events.WAVE_CHANGED, {})
assert(#props == before + 4, "init must resubscribe after event bus reset")
check_last_four("cold"); service.clear()
map = "other_map"
assert(service.apply() == 0)
mode, map = nil, "valley_decor_review"
assert(service.apply() == 4); check_last_four("standard"); service.clear()
print("VALLEY_UNDERLORD_PORTALS_PASS recipient-ready initialization; joins and reconnects; first-player readiness; upright standard; model-free rich center; 8 advanced lane portals; cleanup; hot reload; worlds")
