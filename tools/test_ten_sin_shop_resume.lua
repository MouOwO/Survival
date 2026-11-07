-- Real shop/catalog/evaluator/grant/resource modules. The encounter service's
-- authoritative query/start boundary is simulated; its eligibility/lifecycle
-- tests remain in test_challenge_shared_encounters/test_challenge_pacing.
package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
if arg and arg[1] then
    local source_path = arg[1]
    package.preload["systems/shop_system"] = function() return assert(loadfile(source_path))() end
end
local output = print
print = function(...)
    local line = tostring(select(1, ...))
    if line:find("handler error", 1, true) or line:find("task failed", 1, true) then error(line) end
end
package.loaded["systems/player_context_service"] = { is_defeated = function() return false end }
-- No Steam/auth in this isolated native fixture; real admission has its own suite.
package.loaded["core/test_access_policy"] = {
    enforce = function(id) return id == 0 or id == 1 end,
    allowed = function(id) return id == 0 or id == 1 end,
    enabled = function() return false end,
}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local resource = require("systems/resource_system")
local catalog = require("systems/shop_catalog")
local native_build = catalog.build_snapshot
local native_request = bus.request
local checks, clock, queries, starts, spends, reentries, builds = 0, 0, 0, 0, 0, 0, 0
local sessions, owned, fail_start, counts, last_start = {}, {}, false, {}, nil
local TEN, OTHER, REBIRTH = "encounter_challenge_11", "encounter_challenge_01", "encounter_rebirth_01"
local function check(value, label) checks = checks + 1; assert(value, label) end
local function eq(value, expected, label) check(value == expected, label .. ": " .. tostring(value)) end
bus.request = function(name, payload)
    if name == events.RESOURCE_TRY_SPEND_REQUEST then spends = spends + 1 end
    return native_request(name, payload)
end
catalog.build_snapshot = function(id, context)
    builds = builds + 1; counts = context.purchased_count
    return native_build(id, context)
end
local function request(name, payload)
    local result, reason = bus.request(name, payload)
    assert(result, tostring(reason)); return result
end
local function wallet(id)
    return request(events.RESOURCE_GET_REQUEST, { player_id = id })
end
local function funding(id, wood)
    local current = wallet(id)
    check(request(events.RESOURCE_TRY_SPEND_REQUEST, {
        player_id = id, wood = current.wood, gold = current.gold, reason = "fixture_reset",
    }).ok, "fixture resource reset")
    if wood > 0 then check(request(events.RESOURCE_ADD_REQUEST, {
        player_id = id, wood = wood, gold = 0, reason = "fixture_fund",
    }).ok, "fixture resource add") end
end
local function key(id, encounter) return tostring(id) .. ":" .. encounter end
local function session(id, encounter, value) sessions[key(id, encounter)] = value end
local function entry_for(encounter)
    for _, entry in ipairs(catalog.entries()) do
        if entry.encounter_id == encounter then return entry end
    end
    error("real encounter entry missing: " .. encounter)
end
local function open(id)
    local result = request(events.SHOP_OPEN_REQUEST, { player_id = id, mode = "challenge" })
    check(result.ok, "open actual shop")
    local result_by_encounter = {}
    for _, item in ipairs(result.snapshot.entries) do
        for _, encounter in ipairs({TEN, OTHER, REBIRTH}) do
            if item.entry_id == entry_for(encounter).entryid then result_by_encounter[encounter] = item end
        end
    end
    return result_by_encounter
end
local function purchase(id, encounter, extra)
    local payload = { player_id = id, entry_id = entry_for(encounter).entryid }
    for name, value in pairs(extra or {}) do payload[name] = value end
    return request(events.SHOP_PURCHASE_REQUEST, payload)
end
local function bought(id, encounter)
    return counts[id] and counts[id][entry_for(encounter).entryid] or 0
end
local function fixture()
    bus.reset(); scheduler.clear(); clock = 0; sessions = {}; fail_start = false
    queries, starts, spends, reentries, builds = 0, 0, 0, 0, 0
    owned = { [0] = { weapon_legend_abyss_1 = 1 }, [1] = { weapon_legend_abyss_1 = 1 } }
    local handles = { [0] = {}, [1] = {} }
    GameRules = { GetGameTime = function() return clock end, GetGameModeEntity = function() return {} end }
    Time = function() return clock end; IsServer = function() return true end
    IsInToolsMode = function() return false end; GetMapName = function() return "template_map" end
    PlayerResource = { IsValidPlayerID = function(_, id) return handles[id] ~= nil end,
        GetTeam = function() return 2 end, GetPlayer = function(_, id) return handles[id] end }
    CustomNetTables = { SetTableValue = function() end }
    local buildings = {
        {entindex=14,building_id="main_city",player_id=0,team=2,level=4},
        {entindex=15,building_id="hero_altar",player_id=0,team=2,level=1},
    }
    bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function()
        return {ok=true,totals={initial_wood=0,initial_gold=0,initial_population_cap=100}}
    end)
    bus.handle_request(events.BUILDING_LIST_REQUEST, function() return {buildings=buildings} end)
    bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function() return {snapshot={rebirth_level=0}} end)
    bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function() return {snapshot={hero_summoned=1}} end)
    bus.handle_request(events.PLAYER_ENTITLEMENT_GET_REQUEST, function() return {snapshot={vip=1}} end)
    bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, function(p) return {snapshot={counts=owned[p.player_id]}} end)
    bus.handle_request(events.MONSTER_ENCOUNTER_QUERY_REQUEST, function(p)
        queries = queries + 1
        return sessions[key(p.player_id,p.encounter_id)] or {ok=true,active=false,resume_without_charge=false}
    end)
    bus.handle_request(events.MONSTER_ENCOUNTER_START_REQUEST, function(p)
        starts = starts + 1; last_start = p
        if fail_start then return {ok=false,error="teleport_failed"} end
        session(p.player_id,p.encounter_id,{ok=true,active=true,resume_without_charge=false})
        return {ok=true,encounter_id=p.encounter_id}
    end)
    bus.handle_request(events.MONSTER_ENCOUNTER_REENTER_REQUEST, function(p)
        reentries = reentries + 1; return {ok=true,encounter_id=p.encounter_id}
    end)
    package.loaded["systems/shop_system"] = nil
    resource.init(); require("systems/shop_system").init()
    for id=0,1 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,team=2}) end
    for _, building in ipairs(buildings) do bus.emit(events.BUILDING_CREATED, building) end
    funding(0,0); funding(1,0); spends=0
end

fixture()
session(0,TEN,{ok=true,active=false,resume_without_charge=true})
local ui = open(0)[TEN]
check(ui ~= nil, "real ten-sin entry exists")
eq(ui.wood_cost,0,"qualified completed UI wood")
eq(ui.gold_cost,0,"qualified completed UI gold")
eq(ui.purchasable,1,"qualified zero-balance UI remains enabled")
eq(ui.owned_count,0,"no purchase fabricated by projection")
local q0,b0,s0 = queries,builds,spends
local resumed = purchase(0,TEN)
check(resumed.ok and resumed.resumed_without_charge,"qualified completed session resumes")
eq(queries-q0,1,"one existing authority query on free path")
eq(builds-b0,0,"no full shop build on free path")
eq(spends-s0,0,"free continuation never calls spend")
eq(starts,1,"one actual grant -> encounter start")
eq(wallet(0).wood,0,"zero balance unchanged")
eq(bought(0,TEN),0,"continuation does not count as duplicate purchase")
eq(last_start.player_id,0,"start remains requesting player")
eq(last_start.resume_without_charge,nil,"no client/server flag copied into grant payload")
eq(sessions[key(0,TEN)].resume_without_charge,false,"successful new session consumes authority flag")
check(purchase(0,TEN).ok,"existing active free reentry retained")
eq(bought(0,TEN),0,"active reentry still does not count duplicate purchase")

fixture(); session(0,TEN,{ok=true,active=false,resume_without_charge=true}); open(0)
fail_start=true; s0=spends
local failed=purchase(0,TEN)
eq(failed.ok,false,"failed entrance returned")
eq(failed.error,"teleport_failed","actual grant error retained")
eq(spends-s0,0,"failed free entrance never charges")
eq(bought(0,TEN),0,"failed continuation never counts")
eq(sessions[key(0,TEN)].resume_without_charge,true,"failure preserves server qualification")
fail_start=false; check(purchase(0,TEN).ok,"failure can retry free")

-- Same team does not share personal completion credit. Client flags ignored.
fixture(); session(0,TEN,{ok=true,active=false,resume_without_charge=true})
local other_ui=open(1)[TEN]
eq(other_ui.wood_cost,entry_for(TEN).woodcost,"other player retains entry cost")
eq(other_ui.purchasable,0,"other player zero balance denied")
local forged=purchase(1,TEN,{resume_without_charge=true,active=true,session_player_id=0})
eq(forged.ok,false,"forged client eligibility denied")
eq(starts,0,"forged eligibility cannot call encounter start")
eq(sessions[key(0,TEN)].resume_without_charge,true,"other player cannot consume qualification")
funding(1,entry_for(TEN).woodcost); s0=spends
check(purchase(1,TEN).ok,"other player can pay normal initial cost")
eq(spends-s0,1,"initial entry invokes real spend once")
eq(wallet(1).wood,0,"full initial entry cost charged")
open(1); eq(bought(1,TEN),1,"ordinary paid entry counts one purchase")

-- Strict server booleans, failed query, unrelated encounter and no encounter.
for _, current in ipairs({{ok=true,active=false},{ok=true,active=false,resume_without_charge=1},
    {ok=true,active=false,resume_without_charge="true"},{ok=false,active=false,resume_without_charge=true}}) do
    fixture();session(0,TEN,current);eq(open(0)[TEN].wood_cost,entry_for(TEN).woodcost,"unqualified UI cost retained")
    eq(purchase(0,TEN,{resume_without_charge=true}).ok,false,"only strict trusted qualification can waive cost")
    eq(starts,0,"unqualified does not start")
end
fixture();session(0,OTHER,{ok=true,active=false,resume_without_charge=true})
eq(open(0)[OTHER].wood_cost,entry_for(OTHER).woodcost,"other completed challenge flag ignored")
eq(purchase(0,OTHER).ok,false,"other completed challenge remains paid")
session(0,OTHER,{ok=true,active=true});eq(open(0)[OTHER].wood_cost,0,"other active challenge still free")
check(purchase(0,OTHER).ok,"other active challenge reentry retained")

fixture();owned[0]={weapon_legend_abyss_10=1}
local complete_ui=open(0)[TEN]
eq(complete_ui.purchasable,0,"ten levels complete stays disabled")
eq(purchase(0,TEN,{resume_without_charge=true}).ok,false,"completion cannot be bypassed by payload")
eq(starts,0,"completed player cannot launch a stage")

fixture();session(0,REBIRTH,{ok=true,active=true,resume_without_charge=true})
local rebirth_ui=open(0)[REBIRTH]
eq(rebirth_ui.wood_cost,entry_for(REBIRTH).woodcost,"active rebirth still displays paid entry")
eq(purchase(0,REBIRTH,{resume_without_charge=true}).ok,false,"zero-balance rebirth remains denied")
funding(0,entry_for(REBIRTH).woodcost);s0=spends
local paid=purchase(0,REBIRTH)
check(paid.ok and paid.rebirth_reentered,"rebirth uses original paid reentry branch")
eq(spends-s0,1,"rebirth still charges exactly once")
eq(reentries,1,"rebirth still uses ownership reenter route")
eq(starts,0,"rebirth does not enter ordinary free grant path")
eq(wallet(0).wood,0,"rebirth fee deducted")

catalog.build_snapshot=native_build;bus.request=native_request
output("TEN_SIN_SHOP_RESUME_PASS checks="..checks.." free_purchase_queries=1 builds=0 spends=0 starts=1; native encounter boundary simulated, no live transactions")
