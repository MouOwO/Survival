package.path = "scripts/vscripts/?.lua;" .. package.path
local timers, attempts, created, reset, ready = {}, 0, 0, 0, 0
local failures, permanent, defeated = 0, false, false
package.loaded["core/scheduler"] = {
    every = function(_, fn, key) timers[key] = fn end,
    cancel = function(key) timers[key] = nil end,
}
package.loaded["visual/model_scale"] = {apply = function() end}
package.loaded["systems/builder_presentation_service"] = {init = function() end, apply = function() end}
package.loaded["core/modifier_registry"] = {ensure = function() end}
package.loaded["config/generated/builder_definitions"] = {by_id = {default_builder = {
    enabled = true, unit_name = "builder", model_name = "model", model_scale = 1,
}}}
package.loaded["systems/rich_region_service"] = {
    retry_failed_initialization = function() reset = reset + 1 end,
    attach_builder = function() return true end, detach_builder = function() end,
}
Vector = function(x,y,z) return {x=x,y=y,z=z} end
local function unit()
    local u = {IsNull = function(self) return self.removed == true end,
        entindex = function() return 100 + created end, GetUnitName = function() return "builder" end,
        GetAbsOrigin = function() return Vector(14000, 13000, 256) end}
    for _, name in ipairs({"SetPlayerID", "SetOwner", "SetControllableByPlayer", "SetBaseMoveSpeed",
        "SetModel", "SetOriginalModel", "SetHullRadius", "SetAbsOrigin", "Stop"}) do u[name] = function() end end
    return u
end
package.loaded["systems/player_context_service"] = {
    is_defeated = function() return defeated end,
    resolve_builder_spawn = function()
        attempts = attempts + 1
        if permanent then return nil, "mode_player_outside_bounds" end
        if attempts <= failures then return nil, "mode_player_landing_outside_cells:mode_cold_player_0_spawn" end
        return {position=Vector(14000,13000,256), mode="cold", slot_id="east", marker="cold", source="marker"}
    end,
    register_unit = function() return true end, unregister_unit = function() end,
}
PlayerResource = {GetPlayer = function() return {} end}
CreateUnitByName = function() created = created + 1; return unit() end
UTIL_Remove = function(u) u.removed = true end
local bus, events = require("core/event_bus"), require("core/events")
local service = require("systems/builder_service")
local payload = {player_id=0, hero=unit(), team=2}
local key = "builder_spawn_retry:0"
local function start()
    bus.reset(); timers = {}; attempts, created, reset, ready = 0, 0, 0, 0
    service.init(); bus.subscribe(events.BUILDER_READY, function() ready = ready + 1 end)
end
local function tick()
    local fn = assert(timers[key]); if fn() == false then timers[key] = nil end
end
failures = 2; start()
bus.emit(events.HERO_READY, payload); bus.emit(events.HERO_READY, payload)
assert(attempts == 1 and created == 0 and timers[key], "duplicate readiness shares one pending spawn")
tick(); tick()
assert(created == 1 and ready == 1 and reset == 2 and not timers[key], "transient native readiness recovers once")
bus.emit(events.HERO_READY, payload); assert(created == 1)
failures = 100; start(); bus.emit(events.HERO_READY, payload)
for _ = 1, 4 do tick() end
assert(attempts == 5 and created == 0 and not timers[key], "retry budget is bounded")
start(); bus.emit(events.HERO_READY, payload); bus.emit(events.PLAYER_DISCONNECTED, {player_id=0})
assert(not timers[key], "disconnect cancels pending spawn")
start(); bus.emit(events.HERO_READY, payload); bus.reset(); service.init(); assert(not timers[key])
permanent = true; start(); bus.emit(events.HERO_READY, payload); assert(not timers[key])
permanent = false; defeated = true; start(); bus.emit(events.HERO_READY, payload)
assert(attempts == 0 and not timers[key] and created == 0)
print("BUILDER_SPAWN_RETRY_PASS: native readiness recovery, duplicate suppression, four retries, disconnect/init cancellation, permanent rejection and defeat")
