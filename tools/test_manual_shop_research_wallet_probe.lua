package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local native_print = print
print = function(...)
    local line = tostring(select(1, ...))
    if line:find("handler error", 1, true) or line:find("task failed", 1, true) then error(line) end
end
package.loaded["systems/player_context_service"] = { is_defeated = function() return false end }
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local shop = require("systems/shop_system")
local resource = require("systems/resource_system")
local research = require("bootstrap/research_technology_bootstrap")
local catalog = require("systems/shop_catalog")
local clock, wall, mode, thinkers, tools, actual_state, buildings, outside_events, fail_query
local function fixture()
    bus.reset(); scheduler.clear(); clock, wall, tools, actual_state, fail_query = 0, 0, true, 10, nil
    thinkers = {}; mode = { SetContextThink = function(_, name, fn) thinkers[name] = fn end }
    GameRules = { GetGameTime = function() return clock end, GetGameModeEntity = function() return mode end,
        State_Get = function() return actual_state end }
    DOTA_GAMERULES_STATE_GAME_IN_PROGRESS = 10
    Plat_FloatTime = function() return wall end
    IsServer = function() return true end; IsInToolsMode = function() return tools end; GetMapName = function() return "template_map" end
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = { mode = mode }
    PlayerResource = { IsValidPlayerID = function(_, id) return id >= 0 and id < 4 end, GetTeam = function() return 2 end }
    CustomNetTables = { SetTableValue = function() end }
    buildings = {}; for id = 0, 3 do
        local index = 12 + id
        buildings[index] = { entindex = index, building_id = "building_advanced_research_lab", player_id = id, team = 2,
            unit = { IsNull = function() return false end, entindex = function() return index end } }
    end
    buildings[16] = { entindex = 16, building_id = "main_city", player_id = 0, team = 2, level = 4 }
    bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function(p)
        return { ok = true, totals = { initial_wood = 1000000 + p.player_id * 1000, initial_gold = 500000,
            initial_population_cap = 100, technology_cost_refund_pct = p.player_id * 2 } }
    end)
    bus.handle_request(events.BUILDING_QUERY_REQUEST, function(p) return p.entindex ~= fail_query and buildings[p.entindex] or nil end)
    bus.handle_request(events.BUILDING_LIST_REQUEST, function()
        local result = {}; for _, item in pairs(buildings) do result[#result + 1] = item end; return { buildings = result }
    end)
    bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function(p) return { snapshot = { rebirth_level = 10 - p.player_id } } end)
    bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function() return { snapshot = { hero_summoned = 1 } } end)
    resource.init(); shop.init(); research.init()
    for id = 0, 3 do bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = id, team = 2 }) end
    for _, b in pairs(buildings) do bus.emit(events.BUILDING_CREATED, b) end
    outside_events = 0; bus.subscribe(events.RESOURCE_CHANGED, function() outside_events = outside_events + 1 end)
    return assert(loadfile("scripts/vscripts/tests/manual_shop_research_wallet_probe.lua"))()
end
local function tick(t, produce)
    clock, wall = t, t
    -- Only this isolated test driver generates real producer requests. The
    -- manual native module never generates or synthesizes resource events.
    if produce then for id = 0, 3 do assert(bus.request(events.RESOURCE_ADD_REQUEST,
        { player_id = id, wood = 12, reason = "natural_test_hit" }).ok) end end
    scheduler.think()
    local pending = {}; for _, fn in pairs(thinkers) do pending[#pending + 1] = fn end
    for _, fn in ipairs(pending) do fn() end
end
local function closed()
    for id = 0, 3 do assert(shop._advanced_research_for_test.state().opened_players[id] == nil) end
end
local diagnostic = fixture()
local request_identity, catalog_identity = bus.request, catalog.build_snapshot
assert(next(thinkers) == nil, "require is inert")
tools = false; assert(not diagnostic.start()); tools = true
actual_state = 11; assert(not diagnostic.start()); actual_state = 10
assert(bus.request == request_identity and catalog.build_snapshot == catalog_identity)
local before = bus.request(events.RESOURCE_GET_REQUEST, { player_id = 0 })
assert(diagnostic.start()); assert(not diagnostic.start(), "bounded single active run")
assert(before.wood == bus.request(events.RESOURCE_GET_REQUEST, { player_id = 0 }).wood, "start never changes resources")
for i = 1, 202 do tick(i / 10, true) end
local report = diagnostic.inspect()
assert(report.completed and report.coverage_pass and report.product_stability_proven and not report.running)
assert(report.off_full_catalog_builds:find("unmeasured", 1, true))
assert(report.probe_counts.counts.wallet_reuses > 0 and report.probe_disabled)
assert(#report.raw_payloads == 64 and report.raw_omitted > 0, "bounded full raw capture")
for id = 0, 3 do
    local pair = report.comparisons[id]
    assert(pair.complete_product_fields_equal and not pair.business_changed, "actual complete nonwallet product parity")
    assert(pair.natural_resource_events_off > 0 and pair.natural_resource_events_on > 0)
    assert(report.closed[id] and report.sources[id] == 12 + id, "exact own source and public close")
end
assert(next(thinkers) == nil and bus.request == request_identity and catalog.build_snapshot == catalog_identity)
closed(); assert(not shop.inspect_research_wallet_probe().enabled)
local raw = #report.raw_payloads; tick(21, true)
assert(#diagnostic.inspect().raw_payloads == raw and outside_events == 812, "only own listeners removed")

diagnostic = fixture()
assert(bus.request(events.SHOP_OPEN_REQUEST, { player_id = 0, mode = "research", source_entindex = 12 }).ok)
assert(not diagnostic.start(), "existing UI context is never overwritten")
assert(shop._advanced_research_for_test.state().opened_players[0] == "research")

diagnostic = fixture(); assert(shop.set_research_wallet_probe(true))
assert(not diagnostic.start(), "existing candidate probe is never stolen")
assert(shop.inspect_research_wallet_probe().enabled); shop.set_research_wallet_probe(false)

diagnostic = fixture(); assert(diagnostic.start()); tick(10.1, true)
bus.emit(events.SHOP_STATE_CHANGED, { player_id = 0, snapshot = { full = 1, player_id = 1,
    entries = {}, sequence = 999, research = { source_entindex = 12 } } })
report = diagnostic.stop("negative_private_owner")
assert(report.errors.payload_owner_mismatch and report.errors.private_owner_mismatch and not report.coverage_pass)
closed()

diagnostic = fixture(); assert(diagnostic.start()); tick(10.1, true)
assert(shop.inspect_research_wallet_probe().enabled)
assert(bus.request(events.SHOP_OPEN_REQUEST, { player_id = 0, mode = "research", source_entindex = 13 }).ok)
tick(10.4)
report = diagnostic.inspect(); assert(report.reason == "drawer_context_changed")
assert(report.concurrent_context_preserved[0] and shop._advanced_research_for_test.state().research_source_entindex_by_player[0] == 13)
assert(not shop.inspect_research_wallet_probe().enabled)
for id = 1, 3 do assert(report.closed[id]) end

diagnostic = fixture(); assert(diagnostic.start()); local previous_state = shop._advanced_research_for_test.state()
mode = { SetContextThink = function() error("new world must never be touched") end }
tick(0.3); report = diagnostic.inspect()
assert(report.reason == "world_or_game_changed" and report.restore_world_matched == false)
for id = 0, 3 do assert(previous_state.opened_players[id] == "research", "old lease cannot overwrite new world") end

diagnostic = fixture(); assert(diagnostic.start()); tick(10.1, true); actual_state = 11; tick(10.4)
report = diagnostic.inspect(); assert(report.reason == "game_state_changed" and report.probe_disabled)
closed()

diagnostic = fixture(); assert(diagnostic.start()); clock, wall = 1, 121
for _, fn in pairs(thinkers) do fn() end
report = diagnostic.inspect(); assert(report.reason == "wall_timeout"); closed()

diagnostic = fixture(); assert(diagnostic.start()); tick(10.1, true)
local names = require("research/research_event_names")
assert(bus.request(names.LEVEL_SET_REQUESTED, { player_id = 0, tech_id = "ARS-01", level = 1 }).ok)
for i = 102, 202 do tick(i / 10, true) end
report = diagnostic.inspect()
assert(report.comparisons[0].business_changed and not report.comparisons[0].complete_product_fields_equal)
assert(not report.product_stability_proven, "business change cannot be reported as stable payload proof")
assert(not report.errors.unexplained_product_change, "actual technology change is marked separately")

diagnostic = fixture()
fail_query = 14 -- Native source vanishes between list/preflight and public open.
assert(not diagnostic.start()); report = diagnostic.inspect()
assert(report.reason == "public_open_failed_2" and report.closed[0] and report.closed[1]); closed()
native_print("MANUAL_SHOP_RESEARCH_WALLET_PROBE_PASS: inert, real four-owner backend parity, natural-only resources, bounded raw/20game+120wall, private owner/source/gray, transaction-event classification, guarded public restore, concurrent/new-world preservation, own-listener cleanup")
