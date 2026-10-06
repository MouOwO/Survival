-- Actual chat parsing/dispatch and event bus; mock unrelated engine/services.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local chat, requests, notifications = nil, {}, {}
local current, pending, resources, unlocks = {}, {}, {}, {}
local loading = false
for _, name in ipairs({
    "debug/weapon_cheat_handlers", "debug/research_technology_test",
    "debug/dev_asset_preload", "debug/health_cheat", "debug/armor_engine_diagnostic",
    "systems/wave_system", "systems/player_context_service", "systems/building_system",
    "systems/rogue_reward_service", "systems/fishing_service",
    "systems/player_gameplay_stats_order_service", "systems/monster_corpse_lifecycle_service",
    "core/scheduler",
}) do package.loaded[name] = {} end
package.loaded["debug/attack_speed_cheat"] = {init = function() end}
package.loaded["core/logger"] = {info = function() end, warn = function() end}
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
    GetTeam = function() return 2 end,
    GetPlayer = function(_, id) return {id = id} end,
}
CustomGameEventManager = {
    RegisterListener = function() end,
    Send_ServerToPlayer = function() end,
}
ListenToGameEvent = function(name, handler)
    assert(name == "player_chat"); chat = handler
end
bus.subscribe(events.UI_NOTIFICATION, function(payload)
    notifications[#notifications + 1] = payload
end)
bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(payload)
    return current[payload.player_id] or {ok = false}
end)
bus.handle_request(events.HERO_SUMMON_REQUEST, function(payload)
    requests[#requests + 1] = payload
    assert(payload.debug_bypass == true, "numbered test commands retain debug access")
    assert(payload.hero_id == "hero_monkey_king" or payload.hero_id == "hero_blademaster")
    if loading then
        pending[payload.player_id] = payload
        return {ok = true, pending = true, hero_id = payload.hero_id}
    end
    current[payload.player_id] = {ok = true, hero_id = payload.hero_id}
    return current[payload.player_id]
end)
bus.handle_request(events.HERO_DELETE_REQUEST, function(payload)
    local id = payload.player_id
    local old, queued = current[id], pending[id]
    current[id], pending[id] = nil, nil
    if queued then queued.on_completed({ok = false, cancelled = true}) end
    return {ok = true, removed = old ~= nil, cancelled = queued ~= nil}
end)
bus.handle_request(events.RESOURCE_ADD_REQUEST, function(payload)
    assert(payload.gold == 100000000 and payload.wood == 100000000)
    resources[payload.player_id] = (resources[payload.player_id] or 0) + 1
    return {ok = true}
end)
bus.handle_request(events.SHOP_DEBUG_UNLOCK_REQUEST, function(payload)
    unlocks[payload.player_id] = (unlocks[payload.player_id] or 0) + 1
    return {ok = true}
end)
require("debug/cheat_command_service").init()
local function command(text, id) chat({playerid = id or 0, text = text}) end
command("addhero1")
assert(current[0].hero_id == "hero_monkey_king" and resources[0] == 1)
command("addhero2")
assert(current[0].hero_id == "hero_monkey_king" and #requests == 1,
    "numbered summon cannot silently replace an existing hero")
assert(notifications[#notifications].message:find("deletehero", 1, true))
command("deletehero")
command("-ADDHERO2")
assert(current[0].hero_id == "hero_blademaster" and resources[0] == 2)
assert(notifications[#notifications].message:find("剑圣", 1, true))
command("addhero1", 1)
command("deletehero")
assert(current[1].hero_id == "hero_monkey_king" and current[0] == nil)
command("deletehero")
command("addhero")
assert(current[0].hero_id == "hero_monkey_king", "legacy addhero remains supported")
command("deletehero")
loading = true
local before = resources[0]
command("addhero2")
assert(pending[0].hero_id == "hero_blademaster" and resources[0] == before)
assert(notifications[#notifications].message:find("剑圣", 1, true))
command("deletehero")
assert(pending[0] == nil and resources[0] == before)
assert(notifications[#notifications].level ~= "error", "cancellation is intentional")
command("addhero1")
local completion = pending[0]
current[0] = {ok = true, hero_id = completion.hero_id}
completion.on_completed(current[0])
assert(resources[0] == before + 1 and unlocks[0] == resources[0])
print("DEBUG_HERO_COMMANDS_PASS numbered heroes, legacy alias, delete/retry, owner isolation, async completion/cancellation and preserved test environment")
