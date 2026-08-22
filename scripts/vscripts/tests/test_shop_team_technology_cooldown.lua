package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local now = 100
GameRules = { GetGameTime = function() return now end }
PlayerResource = {
    IsValidPlayerID = function(_, player_id) return player_id == 0 or player_id == 1 end,
    GetTeam = function() return 2 end,
}

local entry = {
    entryid = "technology:test_group_01",
    contenttype = "technology",
    contentid = "test_group_01",
    definition = { technology_group = "test_group", level = 1 },
}
local snapshot_contexts = {}
local technology_level = 0
local begin_count = 0
local commit_count = 0
local notifications = {}
package.loaded["systems/shop_catalog"] = {
    find_entry = function(entry_id) return entry_id == entry.entryid and entry or nil end,
    allowed_in_mode = function() return true end,
    evaluate = function() return true end,
    content_name = function() return "测试科技" end,
    build_snapshot = function(player_id, context)
        snapshot_contexts[player_id] = context
        return { player_id = player_id, sequence = context.sequence,
            resources = context.resources, categories = {}, entries = {},
            ui_mode = context.ui_mode,
            technology_cooldown_remaining = context.technology_cooldown_remaining,
            technology_cooldown_total = context.technology_cooldown_total,
            technology_cooldown_until = context.technology_cooldown_until,
            technology_cooldown_source_group = context.technology_cooldown_source_group,
            technology_cooldown_source_entry = context.technology_cooldown_source_entry,
            technology_cooldown_sequence = context.technology_cooldown_sequence,
        }
    end,
}
package.loaded["systems/shop_grant_service"] = {
    grant = function() return { ok = true } end,
    refund = function() end,
}
package.loaded["config/generated/challenge_definitions"] = { rows = {} }
package.loaded["config/research_technology_config"] = {
    by_legacy_group = {
        test_group = { tech_id = "TEST-01", display_name = "测试科技" },
    },
}
package.loaded["debug/technology_cheat_handler"] = { register = function() end }
local scheduled = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, key)
        scheduled[key or tostring(#scheduled + 1)] = { delay = delay, callback = callback }
    end,
    cancel = function() end,
}

local event_bus = require("core/event_bus")
local events = require("core/events")
local research_events = require("research/research_event_names")
event_bus.reset()

event_bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST,
    function() return { snapshot = { hero_summoned = 1 } } end)
event_bus.handle_request(events.PLAYER_ENTITLEMENT_GET_REQUEST,
    function() return { snapshot = { vip = 0 } } end)
event_bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST,
    function() return { snapshot = { rebirth_level = 0 } } end)
event_bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST,
    function() return { snapshot = { counts = {} } } end)
event_bus.handle_request(events.RESOURCE_GET_REQUEST,
    function() return { wood = 999999, gold = 999999 } end)
event_bus.handle_request(events.WAVE_STATE_GET_REQUEST,
    function() return { game_started = true, early_final_remaining = 0 } end)
event_bus.handle_request(research_events.STATE_GET_REQUESTED,
    function()
        return { ok = true, legacy_levels = { test_group = technology_level } }
    end)
event_bus.handle_request(research_events.UPGRADE_BEGIN_REQUESTED, function(payload)
    begin_count = begin_count + 1
    return {
        success = true,
        player_id = payload.player_id,
        transaction_id = "test-transaction-" .. tostring(begin_count),
        old_level = technology_level,
        new_level = technology_level + 1,
        pending = true,
    }
end)
event_bus.handle_request(research_events.UPGRADE_COMMIT_REQUESTED, function(payload)
    commit_count = commit_count + 1
    technology_level = technology_level + 1
    event_bus.emit(research_events.LEVEL_CHANGED, {
        player_id = 0,
        legacy_levels = { test_group = technology_level },
    })
    return { success = true, new_level = technology_level,
        transaction_id = payload.transaction_id }
end)
event_bus.subscribe(events.UI_NOTIFICATION, function(payload)
    notifications[#notifications + 1] = payload.message
end)

package.loaded["systems/shop_system"] = nil
local shop_system = require("systems/shop_system")
shop_system.init()

for player_id = 0, 1 do
    local opened = event_bus.request(events.SHOP_OPEN_REQUEST, {
        player_id = player_id,
        mode = "research",
    })
    assert(opened and opened.ok == true, "failed to open teammate research page")
end

local first = event_bus.request(events.SHOP_PURCHASE_REQUEST, {
    player_id = 0,
    entry_id = entry.entryid,
    request_id = "first",
})
assert(first and first.ok == true, "first team technology purchase failed")
assert(first.research_started == true,
    "technology purchase must return a research-started result")
assert(begin_count == 1 and commit_count == 0,
    "technology was committed before the research progress completed")
assert(technology_level == 0,
    "technology level changed immediately when research started")
assert(not table.concat(notifications, "|"):find("已完成研究", 1, true),
    "research completion was announced before the progress completed")
assert(scheduled["shop_snapshot_push_0"] and scheduled["shop_snapshot_push_1"],
    "technology purchase did not schedule a snapshot for every open teammate")
scheduled["shop_snapshot_push_0"].callback()
scheduled["shop_snapshot_push_1"].callback()
for player_id = 0, 1 do
    local context = snapshot_contexts[player_id]
    assert(context.technology_cooldown_remaining > 1.9
        and context.technology_cooldown_remaining <= 2,
        "teammate snapshot is missing the two-second research progress")
    assert(context.technology_cooldown_total == 2,
        "technology research duration is missing")
    assert(context.technology_cooldown_source_group == "test_group",
        "technology cooldown source group is incorrect")
    assert(context.technology_cooldown_source_entry == entry.entryid,
        "technology cooldown source entry is incorrect")
    assert(context.technology_cooldown_sequence == 1,
        "technology cooldown sequence was not incremented")
end

local teammate = event_bus.request(events.SHOP_PURCHASE_REQUEST, {
    player_id = 1,
    entry_id = entry.entryid,
    request_id = "teammate",
})
assert(teammate and teammate.ok == false,
    "teammate bypassed shared team research")
assert(teammate.error_code == "technology_research_in_progress",
    "shared team research returned wrong reason code")
assert(teammate.cooldown_remaining > 1.9 and teammate.cooldown_remaining <= 2,
    "shared technology research duration is not two seconds")

now = 102.1
local completion = scheduled["shop_technology_cooldown:2"]
assert(completion and completion.delay == 2,
    "technology completion callback was not scheduled for two seconds")
completion.callback()
assert(commit_count == 1 and technology_level == 1,
    "technology was not committed exactly once after research completed")
assert(table.concat(notifications, "|"):find("已完成研究：测试科技 Lv.1", 1, true),
    "completion notification was not delayed until the research finished")
completion.callback()
assert(commit_count == 1 and technology_level == 1,
    "stale research completion callback committed the technology twice")

entry.definition.level = 2
local after_cooldown = event_bus.request(events.SHOP_PURCHASE_REQUEST, {
    player_id = 1,
    entry_id = entry.entryid,
    request_id = "after_cooldown",
})
assert(after_cooldown and after_cooldown.ok == true,
    "technology research did not recover after the previous research completed")

print("SHOP_TEAM_TECHNOLOGY_COOLDOWN_PASS")
