-- Real producer/catalog/research/scheduler with native-like cyclic entities.
-- Pass the old v2 checkpoint to verify the previous candidate drops snapshots
-- and logs scheduler stack-overflow errors; current production must log zero.
package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local native_print = print
local scheduler_errors, error_examples = 0, {}
print = function(...)
    local line = tostring(select(1, ...))
    if line:find("[Scheduler] task failed:", 1, true) then
        scheduler_errors = scheduler_errors + 1
        if #error_examples < 3 then error_examples[#error_examples + 1] = line end
    elseif line:find("handler error", 1, true) then error(line) end
end
package.loaded["systems/player_context_service"] = { is_defeated = function() return false end }
local bus, events = require("core/event_bus"), require("core/events")
local scheduler, resource = require("core/scheduler"), require("systems/resource_system")
local research = require("bootstrap/research_technology_bootstrap")
local clock, mode = 0, {}
GameRules = { GetGameTime = function() return clock end, GetGameModeEntity = function() return mode end }
IsServer = function() return true end; IsInToolsMode = function() return true end; GetMapName = function() return "template_map" end
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = { mode = mode }
PlayerResource = { IsValidPlayerID = function(_, id) return id >= 0 and id < 4 end, GetTeam = function() return 2 end }
CustomNetTables = { SetTableValue = function() end }
bus.reset(); scheduler.clear()
local function cyclic_unit(index, shared)
    local value = { IsNull = function() return false end, entindex = function() return index end }
    value.self = value
    value.script_scope = { parent = value, native = { entity = value }, shared = shared }
    return value
end
local shared, buildings = {}, {}
for id = 0, 3 do
    local index = 12 + id
    buildings[index] = { entindex = index, player_id = id, team = 2,
        building_id = "building_advanced_research_lab", unit = cyclic_unit(index, shared) }
    shared[id] = buildings[index].unit
end
shared.shared = shared
buildings[16] = { entindex = 16, player_id = 0, team = 2, building_id = "main_city", level = 4 }
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function(p)
    return { ok = true, totals = { initial_wood = 1000000 + p.player_id * 1000,
        initial_gold = 500000, initial_population_cap = 100 } }
end)
bus.handle_request(events.BUILDING_QUERY_REQUEST, function(p) return buildings[p.entindex] end)
bus.handle_request(events.BUILDING_LIST_REQUEST, function()
    local result = {}; for _, b in pairs(buildings) do result[#result + 1] = b end; return { buildings = result }
end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function() return { snapshot = { rebirth_level = 10 } } end)
bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function() return { snapshot = { hero_summoned = 1 } } end)
local shop = assert(loadfile(arg[1] or "scripts/vscripts/systems/shop_system.lua"))()
package.loaded["systems/shop_system"] = shop
resource.init(); shop.init(); research.init()
for id = 0, 3 do bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = id, team = 2 }) end
for _, b in pairs(buildings) do bus.emit(events.BUILDING_CREATED, b) end
assert(shop.set_research_wallet_probe(true))
for id = 0, 3 do assert(bus.request(events.SHOP_OPEN_REQUEST,
    { player_id = id, mode = "research", source_entindex = 12 + id }).ok) end
local sent, latest, resources_emitted = 0, {}, 0
bus.subscribe(events.RESOURCE_CHANGED, function() resources_emitted = resources_emitted + 1 end)
bus.subscribe(events.SHOP_STATE_CHANGED, function(p)
    sent = sent + 1; assert(p.snapshot.player_id == p.player_id)
    assert(p.snapshot.research.source_entindex == 12 + p.player_id)
    latest[p.player_id] = p.snapshot
end)
for i = 1, 8 do
    clock = i / 10
    for id = 0, 3 do assert(bus.request(events.RESOURCE_ADD_REQUEST, { player_id = id, wood = 12, reason = "real_hit" }).ok) end
    scheduler.think()
end
clock = 0.9; scheduler.think()
local counts = shop.inspect_research_wallet_probe().counts
native_print("SHOP_NATIVE_IDENTITY_OBSERVATION events=" .. resources_emitted .. " private_payloads=" .. sent
    .. " scheduler_errors=" .. scheduler_errors .. " wallet_reuses=" .. tostring(counts.wallet_reuses or 0))
if scheduler_errors > 0 then native_print(error_examples[1]) end
assert(scheduler_errors == 0, "native-like self/shared scope caused scheduler error and dropped private snapshots")
assert(resources_emitted == 32 and sent > 0 and (counts.wallet_reuses or 0) > 0)
for id = 0, 3 do
    local account = bus.request(events.RESOURCE_GET_REQUEST, { player_id = id })
    assert(latest[id] and latest[id].resources.wood == account.wood, "latest private wallet remains synchronized")
end
-- A replacement entity with the same entindex, or changed owner/team metadata,
-- remains a structural mismatch and must never reuse a former source proof.
local before_full = shop.inspect_research_wallet_probe().counts.full_builds
buildings[12].unit = cyclic_unit(12, shared); buildings[12].player_id = 3
clock = 0.91; assert(bus.request(events.RESOURCE_ADD_REQUEST, { player_id = 0, wood = 17, reason = "real_hit" }).ok)
clock = 0.98; scheduler.think()
assert(shop.inspect_research_wallet_probe().counts.full_builds == before_full + 1)
assert(scheduler_errors == 0 and latest[0].resources.wood == bus.request(events.RESOURCE_GET_REQUEST, { player_id = 0 }).wood)
shop.set_research_wallet_probe(false)
native_print("SHOP_NATIVE_IDENTITY_PASS: cyclic/shared native identity, scalar source parity, real32resource events/latest private wallet, zero scheduler errors, replacement/owner invalidation, default-off restore")
