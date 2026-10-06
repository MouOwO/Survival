-- Real event bus, scheduler, tooltip builder and weapon snapshot service.
-- Only engine output and authoritative gameplay-service boundaries are mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local tooltip = require("ui/tooltip_view_model")
local time, writes, sends, builds, reads = 0, {}, {}, 0, 0
local outputs, heroes, data = {}, {}, {}
local read_hook, write_hook
GameRules = { GetGameTime = function() return time end }
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
    GetPlayer = function(_, id) return { id = id } end,
}
CustomNetTables = { SetTableValue = function(_, name, key, value)
    if key == "root" then return end
    writes[#writes + 1] = { name = name, id = tonumber(key), value = value }
    outputs[key] = outputs[key] or {}
    outputs[key][name] = value
    if write_hook then local hook = write_hook; write_hook = nil; hook(name, key, value) end
end }
CustomGameEventManager = { Send_ServerToPlayer = function(_, player, name, value)
    assert(name == "ui_weapon_synthesis_snapshot")
    sends[#sends + 1] = { id = player.id, value = value }
end }
local original_tooltip = tooltip.weapon_snapshot
tooltip.weapon_snapshot = function(...)
    builds = builds + 1
    return original_tooltip(...)
end
local function reset_counts() writes, sends, builds, reads = {}, {}, 0, 0 end
local function advance(seconds)
    time = time + seconds
    scheduler.think()
end
local function emit_growth(id, reason)
    bus.emit(events.WEAPON_GROWTH_CHANGED, { player_id = id, reason = reason or "attack_landed" })
end
local function grow(id, amount, reason)
    data[id].growth = data[id].growth + amount
    emit_growth(id, reason)
end
local function latest(id)
    return outputs[tostring(id)] and outputs[tostring(id)].survival_weapon_snapshot
end
bus.reset(); scheduler.clear()
for _, id in ipairs({ 0, 1 }) do
    data[id] = { content = "test_weapon_" .. id, growth = 0 }
    heroes[id] = {}
end
bus.handle_request(events.WEAPON_EQUIPMENT_GET_REQUEST, function(payload)
    reads = reads + 1
    local result = { ok = true, snapshot = { player_id = payload.player_id,
        main_hand_content_id = data[payload.player_id].content } }
    if read_hook then local hook = read_hook; read_hook = nil; hook() end
    return result
end)
bus.handle_request(events.WEAPON_GROWTH_GET_REQUEST, function(payload)
    reads = reads + 1
    return { ok = true, snapshot = { growth_attack = data[payload.player_id].growth,
        stage_attack_count = data[payload.player_id].growth, stage_attack_target = 1000 } }
end)
bus.handle_request(events.EQUIPMENT_INSTANCE_GET_REQUEST, function(payload)
    reads = reads + 1
    return { ok = true, instances = { [data[payload.player_id].content] = { quantity = 1 } } }
end)
bus.handle_request(events.EQUIPMENT_GROWTH_GET_REQUEST, function()
    reads = reads + 1
    return { ok = true, progress = {} }
end)
local service = require("ui/weapon_synthesis_snapshot_service")
service.init()
for _, id in ipairs({ 0, 1 }) do
    bus.emit(events.HERO_SUMMONED, { player_id = id, unit = heroes[id] })
end
reset_counts()

for _ = 1, 100 do grow(0, 1) end
assert(data[0].growth == 100, "UI batching must never defer gameplay growth")
assert(#writes == 0 and #sends == 0 and reads == 0 and builds == 0)
assert(scheduler.task_count() == 1, "one pending flush per player")
advance(0.099)
assert(#writes == 0)
grow(0, 1)
advance(0.002)
assert(#writes == 5 and #sends == 1 and builds == 1 and reads == 4)
assert(latest(0).growth.growth_attack == 101, "flush must read latest authoritative totals")
assert(scheduler.task_count() == 0)
print("WEAPON_SNAPSHOT_BURST_PASS 101 growth events -> 1 tooltip, 5 NetTable writes, 1 notification, 4 service reads")

reset_counts()
for _ = 1, 10 do
    for _ = 1, 10 do grow(0, 1, "damage_dealt") end
    advance(0.11)
end
assert(data[0].growth == 201 and latest(0).growth.growth_attack == 201)
assert(builds == 10 and #writes == 50 and #sends == 10 and reads == 40)
print("WEAPON_SNAPSHOT_SUSTAINED_PASS 100 damage events across 10 windows -> 10 tooltips, 50 NetTable writes")

reset_counts()
grow(0, 1); grow(1, 7)
assert(scheduler.task_count() == 2)
advance(0.11)
assert(builds == 2 and #writes == 10 and #sends == 2)
assert(latest(0).growth.growth_attack == 202 and latest(1).growth.growth_attack == 7)

for _, event in ipairs({ events.WEAPON_EQUIPPED_CHANGED, events.CONTENT_INVENTORY_CHANGED,
    events.EQUIPMENT_INSTANCE_CHANGED, events.EQUIPMENT_GROWTH_CHANGED, events.WEAPON_SYNTHESIZED }) do
    reset_counts(); grow(0, 1)
    data[0].content = "replacement_" .. event
    bus.emit(event, { player_id = 0 })
    assert(builds == 1 and #writes == 5 and #sends == 1)
    assert(latest(0).equipment.main_hand_content_id == data[0].content)
    assert(scheduler.task_count() == 0)
    advance(0.11)
    assert(builds == 1, "an immediate equipment update must cancel its older growth flush")
end
reset_counts(); grow(0, 1)
service.publish_player(0, "explicit_request")
assert(builds == 1 and latest(0).reason == "explicit_request" and scheduler.task_count() == 0)
for _, reason in ipairs({ "weapon_equipped", "forging_hammer_changed", "debug_attack_growth", "unknown" }) do
    reset_counts(); emit_growth(0, reason)
    assert(builds == 1 and #writes == 5 and scheduler.task_count() == 0)
end

reset_counts(); grow(0, 1); grow(1, 1)
local old = heroes[0]
bus.emit(events.HERO_REMOVED, { player_id = 0, unit = old })
grow(0, 1)
advance(0.11)
assert(builds == 1 and sends[1].id == 1, "removal must cancel only the removed player's pending work")
data[0].content, data[0].growth, heroes[0] = "new_hero_weapon", 900, {}
bus.emit(events.HERO_SUMMONED, { player_id = 0, unit = heroes[0] })
assert(latest(0).growth.growth_attack == 900)
reset_counts(); grow(0, 1)
bus.emit(events.HERO_REMOVED, { player_id = 0, unit = old })
advance(0.11)
assert(builds == 1 and latest(0).growth.growth_attack == 901, "stale removal must not cancel replacement")

reset_counts()
read_hook = function()
    data[0].content = "reentrant_equipment"
    data[0].growth = 1000
    bus.emit(events.WEAPON_EQUIPPED_CHANGED, { player_id = 0 })
end
service.publish_player(0, "before_reentry")
assert(builds == 1 and #writes == 5 and latest(0).equipment.main_hand_content_id == "reentrant_equipment")
assert(latest(0).growth.growth_attack == 1000 and reads == 5)

reset_counts()
write_hook = function()
    bus.emit(events.HERO_REMOVED, { player_id = 0, unit = heroes[0] })
    data[0].content, data[0].growth, heroes[0] = "replacement_during_publish", 2000, {}
    bus.emit(events.HERO_SUMMONED, { player_id = 0, unit = heroes[0] })
end
service.publish_player(0, "old_hero_publish")
assert(#writes == 6 and builds == 2 and #sends == 1)
assert(latest(0).equipment.main_hand_content_id == "replacement_during_publish")
assert(latest(0).growth.growth_attack == 2000)
for index = 2, #writes do
    assert(writes[index].value.main_hand_content_id ~= "reentrant_equipment",
        "old publication continued after replacement")
end

reset_counts(); grow(0, 1)
service.init()
assert(scheduler.task_count() == 0)
advance(0.11)
assert(builds == 0 and #writes == 0)
grow(0, 1)
advance(0.11)
assert(builds == 1 and #writes == 5, "hot init must leave one active event subscriber")
assert(latest(0).growth.growth_attack == 2002)
print("WEAPON_SNAPSHOT_LIFECYCLE_PASS immediate equipment/inventory/upgrade/request, latest-value reads, two players, removal/replacement, read/write reentry and hot init")
