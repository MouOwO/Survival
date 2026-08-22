package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

GameRules = { GetGameTime = function() return 100 end }
PlayerResource = {
    IsValidPlayerID = function(_, player_id) return player_id == 0 end,
    GetTeam = function() return 2 end,
}

package.loaded["debug/technology_cheat_handler"] = {
    register = function() end,
}
package.loaded["core/scheduler"] = {
    after = function() end,
    cancel = function() end,
}

local event_bus = require("core/event_bus")
local events = require("core/events")
local research_events = require("research/research_event_names")
event_bus.reset()

event_bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function()
    return { snapshot = { hero_summoned = 0 } }
end)
event_bus.handle_request(events.PLAYER_ENTITLEMENT_GET_REQUEST, function()
    return { snapshot = { vip = 1 } }
end)
event_bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function()
    return { snapshot = { rebirth_level = 10 } }
end)
event_bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, function()
    return { snapshot = { counts = {} } }
end)
event_bus.handle_request(events.RESOURCE_GET_REQUEST, function()
    return { wood = 10 ^ 12, gold = 10 ^ 12 }
end)
event_bus.handle_request(events.WAVE_STATE_GET_REQUEST, function()
    return { game_started = true, early_final_remaining = 0 }
end)
event_bus.handle_request(research_events.STATE_GET_REQUESTED, function()
    return { ok = true, legacy_levels = {} }
end)

local upgrade_requests = 0
event_bus.handle_request(research_events.UPGRADE_REQUESTED, function()
    upgrade_requests = upgrade_requests + 1
    return { success = true, new_level = 1 }
end)

package.loaded["systems/shop_system"] = nil
local shop_system = require("systems/shop_system")
shop_system.init()
event_bus.emit(events.BUILDING_CREATED, {
    building_id = "main_city",
    player_id = 0,
    team = 2,
    level = 99,
})
event_bus.emit(events.BUILDING_CREATED, {
    building_id = "building_research_lab",
    player_id = 0,
    team = 2,
})
event_bus.emit(events.BUILDING_CREATED, {
    building_id = "building_advanced_research_lab",
    player_id = 0,
    team = 2,
})

local opened = event_bus.request(events.SHOP_OPEN_REQUEST, {
    player_id = 0,
    mode = "research",
})
assert(opened and opened.ok == true,
    "research page must open before a hero is summoned")
assert(opened.snapshot and opened.snapshot.ui_mode == "research",
    "research open returned the wrong snapshot mode")
assert(#(opened.snapshot.entries or {}) == 19,
    "research page must still project all 19 technology groups")

local hero_groups = {
    researcher_hero_final_damage = true,
    researcher_hero_armor_reduction = true,
    researcher_hero_attack = true,
}
local hero_entries = 0
local ordinary_entry = nil
local blocked_hero_entry = nil
for _, entry in ipairs(opened.snapshot.entries or {}) do
    if hero_groups[entry.technology_group] then
        hero_entries = hero_entries + 1
        blocked_hero_entry = blocked_hero_entry or entry
        assert(entry.purchasable == 0,
            "hero technology must be disabled before hero summon")
        assert(entry.disabled_reason == "请先在英雄祭坛召唤英雄",
            "hero technology must expose its summon prerequisite")
    elseif entry.purchasable == 1 then
        ordinary_entry = ordinary_entry or entry
    end
end
assert(hero_entries == 3,
    "research page must expose all three hero technology groups")
assert(ordinary_entry,
    "non-hero technology must remain purchasable without a summoned hero")

local bypass = event_bus.request(events.SHOP_PURCHASE_REQUEST, {
    player_id = 0,
    entry_id = blocked_hero_entry.purchase_entry_id,
    request_id = "blocked_without_hero",
})
assert(bypass and bypass.ok == false,
    "direct server purchase bypassed the hero summon prerequisite")
assert(bypass.error == "请先在英雄祭坛召唤英雄",
    "blocked server purchase returned the wrong reason")
assert(upgrade_requests == 0,
    "blocked hero technology reached the research upgrade service")

print("SHOP_RESEARCH_WITHOUT_HERO_PASS")