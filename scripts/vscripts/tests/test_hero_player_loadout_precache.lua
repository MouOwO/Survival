package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local catalog_ready = true
local definitions = require("config/generated/hero_definitions")
package.loaded["systems/asset_preload_service"] = {
    STATE = {READY = "ready", LOADING = "loading"},
    status = function() return {status = catalog_ready and "ready" or "loading"} end,
    queue = function(_, options) options.on_ready(); return true, "queued" end,
}
local requests, completed, failures = {}, 0, 0
PrecacheUnitByNameAsync = function(name, callback, player_id)
    requests[#requests + 1] = {name = name, callback = callback, player_id = player_id}
end
local service = require("systems/hero_asset_preload_service")
service.init()
assert(not service.is_ready("hero_doom", 0), "map costume alone cannot make a player's hero ready")
local function request(id, player)
    assert(service.request(id, {player_id = player,
        on_ready = function() completed = completed + 1 end,
        on_failed = function() failures = failures + 1 end}))
end
request("hero_doom", 0); request("hero_doom", 0); request("hero_doom", 1)
assert(#requests == 2, "same player loadout is coalesced; different players are independent")
assert(requests[1].name == "npc_dota_hero_doom_bringer" and requests[1].player_id == 0)
assert(requests[2].player_id == 1 and not service.is_ready("hero_doom", 1))
requests[1].callback()
assert(completed == 2 and service.is_ready("hero_doom", 0) and not service.is_ready("hero_doom", 1))
requests[1].callback(); assert(completed == 2, "duplicate native callbacks cannot summon twice")
requests[2].callback(); assert(completed == 3)
request("hero_doom", 0); assert(#requests == 2 and completed == 4)
for _, row in ipairs(definitions.rows) do
    request(row.hero_id, 3)
    assert(requests[#requests].name == row.unit_name and requests[#requests].player_id == 3)
    requests[#requests].callback(); assert(service.is_ready(row.hero_id, 3))
end
PrecacheUnitByNameAsync = function() error("engine load failed") end
request("hero_axe", 2); assert(failures == 1 and not service.is_ready("hero_axe", 2))
PrecacheUnitByNameAsync = function(name, callback, player_id)
    requests[#requests + 1] = {name = name, callback = callback, player_id = player_id}
end
request("hero_axe", 2)
local old = requests[#requests].callback
local before = completed
service.init(); old()
assert(completed == before and not service.is_ready("hero_axe", 2), "old session callback cannot ready a new match")
print("HERO_PLAYER_LOADOUT_PRECACHE_PASS: all six heroes, per-player isolation, completion gate, deduplication, retry, reset")
