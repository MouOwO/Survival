-- Real ability/research/shop event consumers and event bus. Only engine time,
-- transport, and expensive view-model/research/catalog dependencies are mocked.
-- Resource transactions and real FPS are outside this focused scheduling test.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local research_events = require("research/research_event_names")
local now, tasks, scheduled, writes, wallet = 0, {}, {}, {}, {}
local original_print, event_errors = print, {}
print = function(message, ...)
    if tostring(message):find("[EventBus] handler error", 1, true) then
        event_errors[#event_errors + 1] = tostring(message)
    else original_print(message, ...) end
end
package.loaded["core/scheduler"] = {
    after = function(delay, callback, id)
        scheduled[id] = (scheduled[id] or 0) + 1
        tasks[id] = {at = now + delay, callback = callback}
    end,
    cancel = function(id) tasks[id] = nil end,
    every = function() error("resource consumers must not poll") end,
}
local function run(id, at)
    now = at
    local task = assert(tasks[id], "missing scheduled task: " .. id)
    assert(task.at <= now + 1e-9, "task executed before deadline")
    tasks[id] = nil
    task.callback()
end
GameRules = {GetGameTime = function() return now end}
DOTA_MAX_TEAM_PLAYERS = 3
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 or id == 1 or id == 2 end,
    GetTeam = function(_, id) return id == 2 and 3 or 2 end,
}
CustomNetTables = {SetTableValue = function(_, name, key, value)
    writes[#writes + 1] = {name = name, key = key, value = value}
end}
local function reset()
    bus.reset()
    now, tasks, scheduled, writes = 0, {}, {}, {}
    wallet = {[0] = 10, [1] = 80, [2] = 900}
    bus.handle_request(events.RESOURCE_GET_REQUEST, function(payload)
        return {wood = wallet[payload.player_id], gold = 20, version = wallet[payload.player_id]}
    end)
end
local function resource(id, stale_amount)
    bus.emit(events.RESOURCE_CHANGED, {player_id = id, team = PlayerResource:GetTeam(id),
        wood = stale_amount or -1, version = -1})
end
local function find_value(name, key)
    for i = #writes, 1, -1 do
        if writes[i].name == name and writes[i].key == key then return writes[i].value end
    end
end
local function count(name, key)
    local n = 0
    for _, row in ipairs(writes) do if row.name == name and (not key or row.key == key) then n = n + 1 end end
    return n
end

-- Ability service: the actual for_each helper walks actual mock ability slots.
package.loaded["config/generated/hero_skill_definitions"] = {rows = {}}
package.loaded["config/hero_passive_skill_definitions"] = {by_id = {}}
package.loaded["config/generated/builder_ability_stages"] = {rows = {}}
package.loaded["ui/hero_skill_tooltip_view_model"] = {}
package.loaded["ui/ability_runtime_builder"] = {build = function(_, state, resources)
    return {available = 1, observed_wood = resources.wood, observed_level = state.level}
end}
local function unit(id, owner)
    local ability = {IsNull = function() return false end, GetAbilityName = function() return "mock_spell" end,
        entindex = function() return id + 1000 end}
    return {IsNull = function(self) return self.invalid == true end, entindex = function() return id end,
        GetTeamNumber = function() return PlayerResource:GetTeam(owner) end,
        GetPlayerOwnerID = function() return owner end, GetAbilityCount = function() return 1 end,
        GetAbilityByIndex = function() return ability end, FindAbilityByName = function() return ability end}
end
local ability_service = require("ui/ability_runtime_service")
reset(); ability_service.init()
local a, b, c = unit(10, 0), unit(11, 1), unit(12, 2)
for _, u in ipairs({a, b, c}) do
    bus.emit(events.BUILDING_CREATED, {unit = u, building_id = "mock_building", level = 1})
end
assert(#writes == 6, "structure creation publishes immediately")
writes = {}
resource(0)
local id = "ability_resource_refresh_player:0"
local first = tasks[id]
for i = 1, 9 do now = i * 0.01; wallet[0] = 10 + i; resource(0) end
assert(scheduled[id] == 1 and tasks[id] == first and first.at == 0.1 and #writes == 0)
wallet[0] = 123 -- No accompanying event: delayed work must read authoritative wallet.
run(id, 0.1)
assert(count("survival_ability_runtime") == 2 and find_value("survival_ability_runtime", "1010").observed_wood == 123)
assert(not find_value("survival_ability_runtime", "1011") and not find_value("survival_ability_runtime", "1012"))

writes = {}; resource(0)
bus.emit(events.BUILDING_CHANGED, {unit = a, building_id = "mock_building", level = 7})
assert(find_value("survival_ability_runtime", "1010").observed_level == 7, "structure changes stay synchronous")
run(id, 0.2)
assert(find_value("survival_ability_runtime", "1010").observed_level == 7)
writes = {}; resource(0)
bus.emit(events.BUILDING_DESTROYED, {entindex = 10})
assert(find_value("survival_ability_runtime", "1010").removed == 1)
writes = {}; run(id, 0.3)
assert(#writes == 0, "queued refresh cannot revive destroyed unit state")

bus.emit(events.BUILDING_CREATED, {unit = a, building_id = "mock_building"})
resource(0)
local stale = tasks[id].callback
bus.reset()
bus.handle_request(events.RESOURCE_GET_REQUEST, function(payload) return {wood = wallet[payload.player_id]} end)
ability_service.init()
assert(tasks[id] == nil, "init cancels resource task")
bus.emit(events.BUILDING_CREATED, {unit = a, building_id = "mock_building"})
writes = {}; stale()
assert(#writes == 0, "old generation cannot publish newly registered units")
resource(0); run(id, 0.4)
assert(#writes == 2)

-- Research bootstrap: mocked domain service still fetches wallet via its real
-- injected get_resources callback; team propagation is not resource ownership.
package.loaded["research/research_technology_repository"] = {new = function()
    return {GetAllLevels = function() return {} end, GetLegacyLevels = function() return {} end,
        SetLevel = function() return true end}
end}
package.loaded["research/research_effect_service"] = {new = function()
    return {Get = function() return {} end, Recalculate = function() return {} end}
end}
local service_generation = 0
package.loaded["research/research_technology_service"] = {new = function(options)
    service_generation = service_generation + 1
    local current = service_generation
    return {BuildClientSnapshot = function(_, player_id)
        return {wood = options.get_resources(player_id).wood, generation = current}
    end}
end}
local research = require("bootstrap/research_technology_bootstrap")
reset(); research.init()
resource(0)
id = "research_resource_refresh_0"
first = tasks[id]
for i = 1, 9 do now = i * 0.01; resource(0) end
assert(scheduled[id] == 1 and tasks[id] == first and first.at == 0.1)
wallet[0] = 345
run(id, 0.1)
assert(#writes == 1 and writes[1].key == "0" and writes[1].value.wood == 345)
writes = {}; resource(0)
bus.emit(events.HERO_READY, {player_id = 0})
assert(#writes == 1, "hero readiness is not delayed by resource queue")
local set_result = bus.request(research_events.LEVEL_SET_REQUESTED, {player_id = 0, tech_id = "mock", level = 1})
assert(set_result and set_result.ok and find_value("survival_research", "1"), "research team propagation remains immediate")
stale = tasks[id].callback
bus.reset()
bus.handle_request(events.RESOURCE_GET_REQUEST, function(payload) return {wood = wallet[payload.player_id]} end)
research.init(); writes = {}; stale()
assert(#writes == 0 and tasks[id] == nil)
resource(1); run("research_resource_refresh_1", 0.2)
assert(#writes == 1 and writes[1].key == "1" and writes[1].value.generation == 2)

-- Shop: real open/close/patch/queue path, minimal catalog with no purchases.
package.loaded["systems/shop_catalog"] = {
    entries = function() return {} end,
    build_snapshot = function(player_id, context)
        return {player_id = player_id, sequence = context.sequence, reason = context.reason,
            resources = context.resources, entries = {}, categories = {}, ui_mode = context.ui_mode,
            schema_version = 1, config_version = 1}
    end,
}
package.loaded["systems/shop_grant_service"] = {}
package.loaded["config/generated/challenge_definitions"] = {rows = {}}
package.loaded["config/generated/rebirth_challenges"] = {rows = {}}
package.loaded["config/research_technology_config"] = {by_legacy_group = {}}
package.loaded["debug/technology_cheat_handler"] = {register = function() end}
local shop = require("systems/shop_system")
local shop_sent = {}
local function observe_shop()
    bus.subscribe(events.SHOP_STATE_CHANGED, function(payload) shop_sent[#shop_sent + 1] = payload end)
end
local function open(player_id)
    local result, err = bus.request(events.SHOP_OPEN_REQUEST, {player_id = player_id})
    assert(result and result.ok, tostring(err))
    return result.snapshot
end
reset(); shop.init(); observe_shop()
assert(open(0).full == 1 and open(1).full == 1)
resource(0)
id = "shop_snapshot_push_0"
first = tasks[id]
for i = 1, 4 do now = i * 0.01; wallet[0] = i * 100; resource(0) end
assert(scheduled[id] == 1 and tasks[id] == first and first.at == 0.05,
    "shop burst must not continually reset the first scheduled deadline")
wallet[0] = 678
run(id, 0.05)
assert(#shop_sent == 1 and shop_sent[1].player_id == 0 and shop_sent[1].snapshot.resources.wood == 678)
assert(not tasks.shop_snapshot_push_1, "same-team independent wallet must not invalidate other shop")
resource(0)
assert(bus.request(events.SHOP_CLOSE_REQUEST, {player_id = 0}).ok)
assert(tasks[id] == nil)
resource(0)
assert(tasks[id] == nil, "closed shop must not schedule projection")
open(0); resource(0)
stale = tasks[id].callback
bus.reset()
bus.handle_request(events.RESOURCE_GET_REQUEST, function(payload) return {wood = wallet[payload.player_id]} end)
shop.init(); observe_shop(); open(0)
local previous_count = #shop_sent
wallet[0] = 900
stale()
assert(#shop_sent == previous_count and tasks[id] == nil, "stale shop task cannot publish new session")
resource(0); run(id, 0.1)
assert(#shop_sent == previous_count + 1 and shop_sent[#shop_sent].snapshot.resources.wood == 900)
assert(#event_errors == 0, table.concat(event_errors, "\n"))
print("RESOURCE_UI_COALESCING_PASS: ability/research/shop burst/latest wallet/owner isolation/fixed deadline/structural updates/destruction/generation/closed shop")
