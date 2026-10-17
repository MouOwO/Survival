-- Full producer/catalog/evaluator/research/scheduler regression. Engine APIs
-- are isolated stubs; all account, cost, queue and projection logic is real.
package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local native_print = print
print = function(...)
    local line = tostring(select(1, ...))
    if line:find("handler error", 1, true) or line:find("task failed", 1, true) then error(line) end
end
package.loaded["systems/player_context_service"] = { is_defeated = function() return false end }
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local resource = require("systems/resource_system")
local research = require("bootstrap/research_technology_bootstrap")
local names = require("research/research_event_names")
local config = require("config/research_technology_config")
local catalog = require("systems/shop_catalog")
local native_build = catalog.build_snapshot
local clock, mode, tools, map, buildings, totals, progression, inventories, summon
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function encode(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}; for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
    local result = {}; for _, key in ipairs(keys) do result[#result + 1] = encode(key) .. "=" .. encode(value[key]) end
    return "{" .. table.concat(result, ";") .. "}"
end
local function check_equal(a, b, label)
    assert(encode(a) == encode(b), "complete payload mismatch: " .. label)
end
local function unit(id)
    return { IsNull = function() return false end, entindex = function() return id end }
end
local function fixture(source_path, enabled)
    bus.reset(); scheduler.clear(); clock, tools, map = 0, true, "template_map"
    mode = {}; GameRules = { GetGameTime = function() return clock end,
        GetGameModeEntity = function() return mode end }
    IsServer = function() return true end; IsInToolsMode = function() return tools end
    GetMapName = function() return map end
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = { mode = mode }
    PlayerResource = { IsValidPlayerID = function(_, id) return id >= 0 and id < 4 end,
        GetTeam = function() return 2 end, GetPlayer = function(_, id) return { id = id } end }
    CustomNetTables = { SetTableValue = function() end }
    totals, progression, inventories, summon = {}, {}, {}, {}
    for id = 0, 3 do
        totals[id] = { initial_wood = 1000000 + id * 1000, initial_gold = 500000,
            initial_population_cap = 100, technology_cost_refund_pct = id * 3 }
        progression[id], inventories[id], summon[id] = 10 - id, { ["owned_" .. id] = id + 1 }, true
    end
    buildings = { [12] = { entindex = 12, building_id = "building_advanced_research_lab",
        player_id = 0, team = 2, unit = unit(12) },
        [13] = { entindex = 13, building_id = "building_advanced_research_lab",
        player_id = 1, team = 2, unit = unit(13) },
        [14] = { entindex = 14, building_id = "main_city", player_id = 0, team = 2, level = 4 } }
    bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function(p) return { ok = true, totals = totals[p.player_id] } end)
    bus.handle_request(events.BUILDING_QUERY_REQUEST, function(p) return buildings[p.entindex] end)
    bus.handle_request(events.BUILDING_LIST_REQUEST, function()
        local list = {}; for _, b in pairs(buildings) do list[#list + 1] = b end; return { buildings = list }
    end)
    bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function(p) return { snapshot = { rebirth_level = progression[p.player_id] } } end)
    bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function(p) return { snapshot = { hero_summoned = summon[p.player_id] and 1 or 0 } } end)
    bus.handle_request(events.PLAYER_ENTITLEMENT_GET_REQUEST, function(p) return { snapshot = { vip = p.player_id % 2 } } end)
    bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, function(p) return { snapshot = { counts = inventories[p.player_id] } } end)
    local shop = assert(loadfile(source_path or "scripts/vscripts/systems/shop_system.lua"))()
    package.loaded["systems/shop_system"] = shop
    resource.init(); shop.init(); research.init()
    for id = 0, 3 do bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = id, team = 2 }) end
    for _, b in pairs(buildings) do bus.emit(events.BUILDING_CREATED, b) end
    if enabled then assert(shop.set_research_wallet_probe and shop.set_research_wallet_probe(true)) end
    local trace, counts, event_count = {}, {}, 0
    catalog.build_snapshot = function(id, context)
        counts[id] = (counts[id] or 0) + 1; return native_build(id, context)
    end
    bus.subscribe(events.RESOURCE_CHANGED, function() event_count = event_count + 1 end)
    bus.subscribe(events.SHOP_STATE_CHANGED, function(p) trace[#trace + 1] = { time = clock, player_id = p.player_id, snapshot = copy(p.snapshot) } end)
    local function tick(t) clock = t; scheduler.think() end
    local function add(id, amount)
        assert(bus.request(events.RESOURCE_ADD_REQUEST, { player_id = id, wood = amount or 12, reason = "lumberjack_hit" }).ok)
    end
    local function open(id, source, kind)
        local response = bus.request(events.SHOP_OPEN_REQUEST, { player_id = id, mode = kind or "research", source_entindex = source or 12 })
        assert(response.ok); trace[#trace + 1] = { open = id, response = copy(response) }; return response.snapshot
    end
    local function flush(t, id) clock = t; add(id or 0); tick(t + 0.1) end
    return { shop = shop, trace = trace, counts = counts, tick = tick, add = add, open = open, flush = flush,
        events = function() return event_count end }
end

local function scenario(path, enabled)
    local f = fixture(path, enabled)
    -- Four real wallets produce 4,000 events while the drawers are closed.
    for i = 1, 1000 do clock = i / 100; for id = 0, 3 do f.add(id) end; scheduler.think() end
    assert(next(f.counts) == nil, "closed drawers must not build catalogs")
    assert(f.events() == 4000)
    for id = 0, 3 do f.open(id) end
    local initial = copy(f.counts)
    local steady_started = os.clock()
    for i = 1, 1000 do clock = 20 + i / 100; for id = 0, 3 do f.add(id) end; scheduler.think() end
    f.tick(30.1)
    local steady_cpu = os.clock() - steady_started
    local steady = {}; for id = 0, 3 do steady[id] = f.counts[id] - initial[id] end
    assert(f.events() == 8000, "real producer burst count")
    -- A structural invalidation followed by resources in the same 50 ms batch
    -- keeps the old outgoing reason and must still rebuild authoritative rows.
    clock = 31
    assert(bus.request(names.LEVEL_SET_REQUESTED, { player_id = 0, tech_id = "ARS-06", level = 1 }).ok)
    f.add(0); f.tick(31.1)
    local last = f.trace[#f.trace].snapshot
    local changed = false
    for _, entry in ipairs(last.changed_entries or {}) do
        if entry.technology_group == "researcher_super_tower_range" and entry.technology_level == 1 then changed = true end
    end
    assert(changed and last.reason == "resource_changed", "mixed batch retains actual technology change")
    assert(research.repository():GetLevel(1, "ARS-06") == 0, "private technology is not inherited by teammate")
    -- Silent dependency changes are discovered by the same authoritative
    -- context reads, not only by a favorable order of notifications.
    progression[0] = 0; f.flush(31.2); progression[0] = 10; f.flush(31.4)
    inventories[0].another_owned_item = 3; f.flush(31.6)
    summon[0] = false; f.flush(31.8); summon[0] = true; f.flush(32)
    totals[0].technology_wood_cost_refund_pct = 50; f.flush(32.2)
    totals[0].technology_gold_cost_refund_pct = 40; f.flush(32.4)
    totals[0].technology_cost_refund_pct = 25; f.flush(32.6)
    -- Team building invalidation and private owner invalidation are distinct.
    local team_before = copy(f.counts)
    clock = 33; buildings[14].level = 3; bus.emit(events.BUILDING_CHANGED, buildings[14]); f.add(0); f.tick(33.1)
    for id = 0, 3 do assert(f.counts[id] == team_before[id] + 1, "team structural invalidation rebuilds all opened drawers") end
    clock = 33.2; buildings[14].level = 4; bus.emit(events.BUILDING_CHANGED, buildings[14]); f.add(1); f.tick(33.3)
    local p1_before = f.counts[1]
    clock = 33.4; progression[0] = 9; bus.emit(events.HERO_PROGRESSION_CHANGED, { player_id = 0 }); f.add(0); f.tick(33.5)
    assert(f.counts[1] == p1_before, "private event cannot schedule another owner's drawer")
    -- Shared advanced source, switching drawers, close/reopen and unknown modes.
    f.open(0, 13); f.flush(33.7)
    assert(bus.request(events.SHOP_CLOSE_REQUEST, { player_id = 0 }).ok)
    local n = f.counts[0]; f.flush(34); assert(f.counts[0] == n)
    f.open(0); f.flush(34.2)
    f.open(0, nil, "shop"); f.flush(34.4); f.open(0)
    f.open(0, nil, "challenge"); f.flush(34.6); f.open(0)
    -- A new/future row dependency cannot become silently cacheable.
    local entry = catalog.find_technology_entry("researcher_super_tower_range", 2)
    entry.definition.future_wallet_condition = "wood>999999999"
    f.flush(35)
    local future_before = f.counts[0]; f.flush(35.2)
    assert(f.counts[0] == future_before + 1, "unknown selected condition cannot be cached after its first full rebuild")
    entry.definition.future_wallet_condition = nil; f.flush(35.4)
    entry.stock_max = 1; f.flush(35.6); f.flush(35.8); entry.stock_max = 0; f.flush(36)
    entry.purchase_cooldown_seconds = 3; f.flush(36.2); f.flush(36.4); entry.purchase_cooldown_seconds = 0; f.flush(36.6)
    local future = copy(entry)
    future.entryid, future.contentid, future.definition.technology_group = "future:research", "future_research", "future_research"
    future.definition.level = 1
    local all = catalog.entries(); all[#all + 1] = future
    f.flush(36.65)
    local unknown_before = f.counts[0]; f.flush(36.66)
    assert(f.counts[0] == unknown_before + 1, "unknown entry/source retains the complete catalog path")
    all[#all] = nil
    -- Existing effect/price configuration changes must repair in the same
    -- resource flush, even without structural notifications or elapsed TTL.
    local definition = config.by_legacy_group.researcher_super_tower_range
    local old_effect = definition.effects[1].display_values_by_level[2]
    definition.effects[1].display_values_by_level[2] = old_effect + 17
    f.flush(36.7); definition.effects[1].display_values_by_level[2] = old_effect; f.flush(36.8)
    -- Paid active research, waiting queue, elapsed timer, cancellation and
    -- idempotent refunds use the unchanged formal transaction service.
    clock = 37
    local first = bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, { player_id = 0, source_entindex = 12,
        technology_group = "researcher_lumberjack_attack_growth", source = "research_lab_ability", request_id = "paid-1" })
    assert(first.ok, "formal research start: " .. encode(first))
    local second = bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, { player_id = 0, source_entindex = 12,
        technology_group = "researcher_lumberjack_attack_growth", source = "research_lab_ability", request_id = "paid-2" })
    assert(second.ok)
    f.tick(37.1); f.flush(37.3); f.flush(37.5)
    local before_refund = bus.request(events.RESOURCE_GET_REQUEST, { player_id = 0 }).wood
    clock = 37.8
    local cancel = bus.request(events.TECHNOLOGY_RESEARCH_CANCEL_REQUEST, { player_id = 0, source_entindex = 12,
        job_id = first.job_id, request_id = "cancel-paid" })
    assert(cancel.ok and cancel.refunded)
    assert(bus.request(events.TECHNOLOGY_RESEARCH_CANCEL_REQUEST, { player_id = 0, source_entindex = 12,
        job_id = first.job_id, request_id = "cancel-paid" }).ok)
    local trace = f.trace
    trace[#trace + 1] = { cancel = copy(cancel), wallet_delta = bus.request(events.RESOURCE_GET_REQUEST, { player_id = 0 }).wood - before_refund }
    f.tick(37.9); f.flush(38.2); f.tick(39.9); f.flush(40.1)
    -- Current owner/source identity is checked even without an event.
    buildings[12].player_id = 3; f.flush(40.3)
    local old_unit = buildings[12].unit; buildings[12].unit = unit(12); f.flush(40.5)
    buildings[12].unit = old_unit
    buildings[12].unit = nil; f.flush(40.6); f.flush(40.7); buildings[12].unit = old_unit
    buildings[12].player_id = nil; f.flush(40.8); buildings[12].player_id = 3
    clock = 41; bus.emit(events.PLAYER_DEFEATED, { player_id = 0 }); f.add(0); f.tick(41.1)
    local report = f.shop.inspect_research_wallet_probe and f.shop.inspect_research_wallet_probe() or {}
    catalog.build_snapshot = native_build
    return { trace = f.trace, steady = steady, report = report, steady_cpu = steady_cpu }
end

local before = scenario(arg[1], false)
local default = scenario(nil, false)
-- Running with --negative-control uses the same real chain with the fast
-- route disabled: all payload checks still pass, but reduction must fail.
local after = scenario(nil, arg[2] ~= "--negative-control")
check_equal(before.trace, default.trace, "old source versus default-off candidate")
check_equal(before.trace, after.trace, "all four-owner complete real payloads")
for id = 0, 3 do
    assert(after.steady[id] < before.steady[id] / 2, "catalog reduction must actually be covered for owner " .. id)
end
assert((after.report.counts.wallet_reuses or 0) > 0, "candidate actually executed")

-- Authority / state generation never survives game world, mode, bus or init.
local f = fixture(nil, false)
assert(f.shop.inspect_research_wallet_probe().enabled == false)
tools = false; assert(not f.shop.set_research_wallet_probe(true)); tools = true
IsServer = function() return false end; assert(not f.shop.set_research_wallet_probe(true))
IsServer = function() return true end
map = "other_map"; assert(not f.shop.set_research_wallet_probe(true)); map = "template_map"
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = nil; assert(not f.shop.set_research_wallet_probe(true))
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = { mode = mode }
assert(f.shop.set_research_wallet_probe(true)); f.open(0); f.flush(0.2)
assert(f.shop.inspect_research_wallet_probe().enabled)
local expires_before = f.counts[0]; f.flush(1.3)
assert(f.counts[0] == expires_before + 1, "one-second original-path recovery boundary")
assert(f.shop.set_research_wallet_probe(false)); assert(not f.shop.inspect_research_wallet_probe().enabled)
assert(f.shop.set_research_wallet_probe(true))
mode = {}; assert(not f.shop.inspect_research_wallet_probe().enabled)
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = { mode = mode }; assert(f.shop.set_research_wallet_probe(true))
bus.reset(); assert(not f.shop.inspect_research_wallet_probe().enabled)
f.shop.init(); assert(not f.shop.inspect_research_wallet_probe().enabled)
catalog.build_snapshot = native_build
local unknown_output = fixture(nil, true)
local producer = catalog.build_snapshot
catalog.build_snapshot = function(id, context)
    local result = producer(id, context); result.future_wallet_rule = context.resources.wood
    return result
end
unknown_output.open(0)
assert(unknown_output.shop.inspect_research_wallet_probe().proof_count == 0, "unknown snapshot dependency is not certified")
unknown_output.flush(0.1)
local unknown_builds = unknown_output.counts[0]; unknown_output.flush(0.3)
assert(unknown_output.counts[0] == unknown_builds + 1, "unknown projection uses original path every wallet flush")
catalog.build_snapshot = native_build
local function list(t) local values = {}; for id = 0, 3 do values[#values + 1] = t[id] end; return table.concat(values, ",") end
native_print("SHOP_RESEARCH_WALLET_PROBE_PASS real_events=8000 steady_events=4000 baseline_builds=" .. list(before.steady)
    .. " candidate_builds=" .. list(after.steady) .. " private_payloads=" .. #after.trace
    .. " wallet_reuses=" .. tostring(after.report.counts.wallet_reuses)
    .. " pure_lua_baseline_cpu_s=" .. tostring(before.steady_cpu)
    .. " pure_lua_candidate_cpu_s=" .. tostring(after.steady_cpu)
    .. " full_payloads_equal=true default_off=true")
