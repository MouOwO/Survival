package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local real_print = print
print = function(...)
    local line = tostring(select(1, ...))
    if line:find("handler error", 1, true) or line:find("task failed", 1, true) then error(line) end
    real_print(...)
end
local clock = 0
GameRules = { GetGameTime = function() return clock end }
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
    GetTeam = function() return 2 end,
}
CustomNetTables = { SetTableValue = function() end }
local bus = require("core/event_bus")
local events = require("core/events")
local names = require("research/research_event_names")
local scheduler = require("core/scheduler")
local research = require("bootstrap/research_technology_bootstrap")
local shop = require("systems/shop_system")
local config = require("config/research_technology_config")
local catalog = require("systems/shop_catalog")
local stats = require("systems/technology_stat_manager")
local resources, buildings, log, commits, refunds
local function eq(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected=" .. tostring(expected)
        .. " actual=" .. tostring(actual))
end
local function fixture()
    bus.reset(); scheduler.clear(); clock = 0
    resources = { [0] = { gold = 1000000000, wood = 1000000000 },
        [1] = { gold = 1000000000, wood = 1000000000 } }
    buildings = {
        [10] = { entindex = 10, building_id = "building_research_lab", player_id = 0, team = 2 },
        [11] = { entindex = 11, building_id = "building_research_lab", player_id = 1, team = 2 },
        [12] = { entindex = 12, building_id = "building_advanced_research_lab", player_id = 0, team = 2 },
        [13] = { entindex = 13, building_id = "building_research_lab", player_id = 0, team = 2 },
    }
    log, commits, refunds = {}, {}, 0
    bus.handle_request(events.RESOURCE_GET_REQUEST, function(p) return resources[p.player_id] end)
    bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function(p)
        local r = resources[p.player_id]
        if r.gold < (p.gold or 0) or r.wood < (p.wood or 0) then
            return { ok = false, error = "insufficient_resources" }
        end
        r.gold = r.gold - (p.gold or 0); r.wood = r.wood - (p.wood or 0)
        return { ok = true }
    end)
    bus.handle_request(events.RESOURCE_ADD_REQUEST, function(p)
        local r = resources[p.player_id]
        r.gold = r.gold + (p.gold or 0); r.wood = r.wood + (p.wood or 0)
        refunds = refunds + 1
        return { ok = true }
    end)
    bus.handle_request(events.BUILDING_QUERY_REQUEST, function(p) return buildings[p.entindex] end)
    bus.handle_request(events.BUILDING_LIST_REQUEST, function()
        local list = {}; for _, b in pairs(buildings) do list[#list + 1] = b end
        return { buildings = list }
    end)
    bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function()
        return { snapshot = { rebirth_level = 10 } }
    end)
    bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function()
        return { snapshot = { hero_summoned = 1 } }
    end)
    shop.init(); research.init(); stats.init()
    for _, b in pairs(buildings) do bus.emit(events.BUILDING_CREATED, b) end
    bus.subscribe(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, function(p)
        log[#log + 1] = { time = clock, player_id = p.player_id, researching = p.researching,
            source_entindex = p.source_entindex, research_group = p.research_group }
    end)
    bus.subscribe(names.LEVEL_CHANGED, function(p)
        commits[#commits + 1] = { time = clock, player_id = p.player_id, tech_id = p.tech_id }
    end)
end
local function tick(value) clock = value; scheduler.think() end
local function toggle(player, source, group)
    local r = bus.request(events.SHOP_AUTO_RESEARCH_TOGGLE_REQUEST,
        { player_id = player, source_entindex = source, technology_group = group })
    assert(r, "missing toggle result")
    return r
end
local function snapshot(player, source)
    return bus.request(events.TECHNOLOGY_STATE_GET_REQUEST,
        { player_id = player, source_entindex = source }).research
end
local function level(player, tech) return research.repository():GetLevel(player, tech) end
local function manual(player, source, group)
    return bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, {
        player_id = player, source_entindex = source, technology_group = group,
        source = "research_lab_ability",
    })
end

fixture()
assert(toggle(0, 10, "lumberjack_speed").enabled)
tick(0)
eq(snapshot(0, 10).researching, 1, "first research starts")
eq(level(0, "RS-01"), 0, "no instant effect")
eq(snapshot(0, 10).finish_at, 2, "configured two-second duration")
tick(1.99); eq(level(0, "RS-01"), 0)
tick(2); eq(level(0, "RS-01"), 1)
eq(snapshot(0, 10).researching, 0)
eq(snapshot(0, 10).next_start_at, 3, "one-second wait deadline")
bus.emit(events.RESOURCE_CHANGED, { player_id = 0, team = 2 })
tick(2.5); eq(snapshot(0, 10).researching, 0)
assert(not toggle(0, 10, "lumberjack_speed").enabled)
assert(toggle(0, 10, "lumberjack_speed").enabled)
tick(2.999); eq(snapshot(0, 10).researching, 0, "retoggle cannot skip delay")
tick(3); eq(snapshot(0, 10).researching, 1)
eq(snapshot(0, 10).started_at, 3)
assert(not toggle(0, 10, "lumberjack_speed").enabled)
eq(snapshot(0, 10).researching, 1, "cancel auto retains current research")
tick(5); eq(level(0, "RS-01"), 2)
tick(10); eq(level(0, "RS-01"), 2, "cancelled auto never resumes")

fixture()
assert(toggle(0, 10, "lumberjack_speed").enabled)
assert(toggle(1, 11, "lumberjack_speed").enabled)
assert(toggle(0, 12, "researcher_lumberjack_attack_growth").enabled)
tick(0)
eq(snapshot(0, 10).researching, 1)
eq(snapshot(1, 11).researching, 1, "same-team player starts independently")
eq(snapshot(0, 12).researching, 1, "normal/advanced run concurrently")
assert(manual(0, 13, "lumberjack_speed").ok == false,
    "same player's same technology cannot double-reserve across buildings")
assert(manual(0, 10, "lumberjack_efficiency").ok == true,
    "busy building accepts a manual waiting job")
eq(snapshot(0, 10).queue_count, 2)
eq(snapshot(0, 10).queued[1].technology_group, "lumberjack_efficiency")
assert(manual(1, 10, "lumberjack_speed").ok == false, "another player's lab is rejected")
tick(2)
eq(level(0, "RS-01"), 1); eq(level(1, "RS-01"), 1)
eq(level(0, "ARS-01"), 1); eq(level(1, "ARS-01"), 0, "technology effect is private")
assert(stats.get(0).final.lumberjack.attack_gain_per_attack > 0,
    "real stat consumer applies personal research effects")
eq(stats.get(1).final.lumberjack.attack_gain_per_attack, 0,
    "real stat consumer never applies another player's advanced technology")
eq(#commits, 3, "no teammate level broadcasts")
eq(refunds, 0, "same-team concurrent research has no transaction collisions")

fixture()
resources[0].gold = 0; resources[0].wood = 0
assert(toggle(0, 10, "lumberjack_speed").enabled)
tick(0); tick(1)
eq(snapshot(0, 10).researching, 0)
eq(snapshot(0, 10).auto_enabled, 1, "resource shortage keeps auto enabled")
resources[0].gold = 1000000000; resources[0].wood = 1000000000
tick(2); eq(snapshot(0, 10).researching, 1, "funds restore auto research")

fixture()
assert(toggle(0, 10, "advanced_lumberjack_speed").enabled)
tick(0); eq(snapshot(0, 10).researching, 0)
eq(snapshot(0, 10).auto_enabled, 1, "prerequisite shortage keeps auto enabled")
research.repository():SetLevel(0, "RS-01", config.by_id["RS-01"].max_level)
tick(1); eq(snapshot(0, 10).researching, 1, "prerequisite unlock retries")

fixture()
research.repository():SetLevel(0, "RS-01", config.by_id["RS-01"].max_level - 1)
assert(toggle(0, 10, "lumberjack_speed").enabled)
tick(0); tick(2)
eq(level(0, "RS-01"), config.by_id["RS-01"].max_level)
eq(snapshot(0, 10).auto_enabled, 0, "max level clears auto immediately")
tick(3); eq(snapshot(0, 10).researching, 0)
assert(toggle(0, 10, "lumberjack_speed").ok == false, "cannot enable max level")

for _, reason in ipairs({ "destroyed", "disconnected", "defeated" }) do
    fixture()
    local before = resources[0].wood
    assert(toggle(0, 10, "lumberjack_speed").enabled); tick(0)
    assert(resources[0].wood < before)
    if reason == "destroyed" then
        local old = buildings[10]; buildings[10] = nil
        bus.emit(events.BUILDING_DESTROYED, old)
    else
        bus.emit(reason == "defeated" and events.PLAYER_DEFEATED or events.PLAYER_DISCONNECTED,
            { player_id = 0, team = 2 })
    end
    eq(resources[0].wood, before, reason .. " refunds reserved resources")
    eq(snapshot(0, 10).auto_enabled, 0)
    tick(10); eq(level(0, "RS-01"), 0, reason .. " cannot commit stale callback")
    eq(refunds, 1, reason .. " refunds once")
end

fixture()
local opened = bus.request(events.SHOP_OPEN_REQUEST,
    { player_id = 0, source_entindex = 12, mode = "research" })
assert(opened.ok)
assert(toggle(0, 10, "lumberjack_speed").enabled); tick(0)
local direct = manual(0, 12, "researcher_lumberjack_attack_growth")
assert(direct.ok, "selected other research building must not borrow busy source context")
local view = bus.request(events.SHOP_OPEN_REQUEST,
    { player_id = 0, source_entindex = 12, mode = "research" }).snapshot
eq(view.research.source_entindex, 12)
eq(view.research.researching, 1)
-- Two public advanced labs must share a player's technology pause, even if
-- the second lab already has a retry scheduled before the first one finishes.
fixture()
buildings[13] = { entindex = 13, building_id = "building_advanced_research_lab",
    player_id = 1, team = 2 }
local shared_group = "researcher_lumberjack_attack_growth"
assert(toggle(0, 12, shared_group).enabled); tick(0)
assert(toggle(0, 13, shared_group).enabled); tick(0.1); tick(1.1)
tick(2)
eq(level(0, "ARS-01"), 1)
eq(snapshot(0, 13).next_start_at, 3, "other lab shows the same technology pause")
local found_deadline_refresh = false
for _, row in ipairs(log) do
    if row.time == 2 and row.source_entindex == 13 then found_deadline_refresh = true end
end
assert(found_deadline_refresh, "selected other lab receives completion deadline refresh")
tick(2.1)
eq(snapshot(0, 13).researching, 0, "cross-lab retry cannot skip one second")
assert(not toggle(0, 12, shared_group).enabled)
tick(2.999); eq(snapshot(0, 13).researching, 0)
tick(3); eq(snapshot(0, 13).started_at, 3, "next level starts at exact shared deadline")
tick(5); eq(level(0, "ARS-01"), 2)
assert(not toggle(0, 13, shared_group).enabled)
tick(5.1); assert(toggle(0, 12, shared_group).enabled)
eq(snapshot(0, 12).next_start_at, 6, "returning to first lab retains shared pause")
tick(5.999); eq(snapshot(0, 12).researching, 0)
tick(6); eq(snapshot(0, 12).started_at, 6)

-- The deadline is for automatic continuation of that player's same technology.
-- Manual requests and another player's or another technology's work remain free.
fixture()
buildings[13] = { entindex = 13, building_id = "building_advanced_research_lab",
    player_id = 1, team = 2 }
assert(toggle(0, 12, shared_group).enabled); tick(0); tick(2)
assert(not toggle(0, 12, shared_group).enabled)
assert(toggle(1, 12, shared_group).enabled)
assert(toggle(0, 13, "researcher_lumberjack_armor_reduction").enabled)
tick(2.1)
eq(snapshot(1, 12).started_at, 2.1, "other player is not delayed")
eq(snapshot(0, 13).started_at, 2.1, "other technology in another lab is not delayed")
assert(manual(0, 12, shared_group).ok, "manual research does not inherit automatic pause")
eq(snapshot(0, 12).started_at, 2.1)
-- Manual FIFO: one active plus six waiting, and each queued level charges
-- exactly once when it actually starts (never when the click is accepted).
fixture()
local starting_wood = resources[0].wood
local first_cost = config.cost_for_level(config.by_id["RS-01"], 1).wood
for index = 1, 7 do
    local result = manual(0, 10, "lumberjack_speed")
    assert(result.ok and result.queued)
    eq(result.target_level, index, "same-technology queued target advances")
end
local full = snapshot(0, 10)
eq(full.queue_count, 7); eq(full.capacity, 7); eq(#full.queued, 6)
eq(full.target_level, 1); eq(full.queued[6].target_level, 7)
assert(full.queued[1].ability_name ~= "" and full.queued[1].icon_name ~= "",
    "waiting task provides real ability and texture icons")
eq(resources[0].wood, starting_wood - first_cost, "waiting queue does not precharge")
local denied = manual(0, 10, "lumberjack_speed")
eq(denied.error_code, "research_queue_full")
eq(resources[0].wood, starting_wood - first_cost)
tick(1.99); eq(level(0, "RS-01"), 0)
tick(2); eq(level(0, "RS-01"), 1)
eq(snapshot(0, 10).target_level, 2); eq(snapshot(0, 10).started_at, 2)
eq(snapshot(0, 10).finish_at, 4, "queued next task receives full research duration")
local second_cost = config.cost_for_level(config.by_id["RS-01"], 2).wood
eq(resources[0].wood, starting_wood - first_cost - second_cost)
tick(3.99); eq(level(0, "RS-01"), 1)
tick(4); tick(6); tick(8); tick(10); tick(12); tick(14)
eq(level(0, "RS-01"), 7); eq(snapshot(0, 10).queue_count, 0)
local total_cost = 0
for index = 1, 7 do total_cost = total_cost + config.cost_for_level(config.by_id["RS-01"], index).wood end
eq(resources[0].wood, starting_wood - total_cost, "seven starts charged their actual configured prices")

fixture()
local request = { player_id = 0, source_entindex = 10, technology_group = "lumberjack_speed",
    source = "research_lab_ability", request_id = "queue-click-1" }
local first = bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, request)
local duplicate = bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, request)
eq(first.job_id, duplicate.job_id); eq(snapshot(0, 10).queue_count, 1, "retry is idempotent")
assert(manual(0, 10, "lumberjack_efficiency").ok)
assert(manual(0, 10, "lumberjack_speed").ok)
assert(manual(0, 10, "tower_attack").ok)
eq(snapshot(0, 10).queued[1].technology_group, "lumberjack_efficiency")
eq(snapshot(0, 10).queued[2].target_level, 2)
tick(2); eq(snapshot(0, 10).research_group, "lumberjack_efficiency")
tick(4); eq(snapshot(0, 10).research_group, "lumberjack_speed")
tick(6); eq(snapshot(0, 10).research_group, "tower_attack")

fixture()
resources[0].gold = 0; resources[0].wood = 0
for index = 1, 7 do assert(manual(0, 10, "lumberjack_speed").ok) end
local blocked = snapshot(0, 10)
eq(blocked.researching, 0); eq(blocked.queue_count, 7); eq(#blocked.queued, 6)
eq(blocked.blocked_head.target_level, 1)
for index = 1, 6 do
    eq(blocked.queued[index].target_level, index + 1,
        "blocked head keeps all six waiting tasks in order")
end
eq(manual(0, 10, "lumberjack_speed").error_code, "research_queue_full",
    "eighth blocked task is rejected")
assert(blocked.blocked_reason:find("开始研究时扣费", 1, true))
eq(resources[0].wood, 0)
tick(1); eq(snapshot(0, 10).researching, 0)
resources[0].gold = 1000000000; resources[0].wood = 1000000000
tick(2); eq(snapshot(0, 10).researching, 1); eq(snapshot(0, 10).target_level, 1)
eq(snapshot(0, 10).finish_at, 4)

fixture()
assert(manual(0, 10, "lumberjack_speed").ok)
resources[0].wood = 0; resources[0].gold = 0
assert(manual(0, 10, "lumberjack_efficiency").ok)
assert(manual(0, 10, "tower_attack").ok)
tick(2)
eq(level(0, "RS-01"), 1)
eq(snapshot(0, 10).researching, 0)
eq(snapshot(0, 10).blocked_head.technology_group, "lumberjack_efficiency")
eq(snapshot(0, 10).queued[1].technology_group, "tower_attack", "unaffordable head cannot be overtaken")
resources[0].wood = 1000000000; resources[0].gold = 1000000000
tick(3); eq(snapshot(0, 10).research_group, "lumberjack_efficiency")
eq(snapshot(0, 10).finish_at, 5)

fixture()
assert(manual(0, 10, "advanced_lumberjack_speed").ok)
eq(snapshot(0, 10).researching, 0)
assert(snapshot(0, 10).blocked_head.job_id)
research.repository():SetLevel(0, "RS-01", config.by_id["RS-01"].max_level)
tick(1); eq(snapshot(0, 10).researching, 1, "queued prerequisite starts after it becomes valid")

fixture()
research.repository():SetLevel(0, "RS-01", config.by_id["RS-01"].max_level - 1)
assert(manual(0, 10, "lumberjack_speed").ok)
eq(manual(0, 10, "lumberjack_speed").error_code, "max_level_reached")
eq(snapshot(0, 10).queue_count, 1)

fixture()
assert(toggle(0, 10, "lumberjack_speed").enabled); tick(0)
assert(manual(0, 10, "lumberjack_speed").ok)
assert(manual(0, 10, "lumberjack_efficiency").ok)
tick(2); eq(snapshot(0, 10).research_group, "lumberjack_speed")
eq(snapshot(0, 10).target_level, 2, "manual queue wins over automatic continuation")
eq(snapshot(0, 10).started_at, 2)
assert(not toggle(0, 10, "lumberjack_speed").enabled)
eq(snapshot(0, 10).queue_count, 2, "cancel auto preserves active and waiting manual jobs")
tick(4); eq(snapshot(0, 10).research_group, "lumberjack_efficiency")
tick(6); tick(7); eq(snapshot(0, 10).queue_count, 0)

fixture()
assert(toggle(0, 10, "lumberjack_speed").enabled); tick(0)
assert(manual(0, 10, "lumberjack_efficiency").ok)
tick(2); eq(snapshot(0, 10).research_group, "lumberjack_efficiency")
tick(4); eq(snapshot(0, 10).researching, 0)
tick(4.999); eq(snapshot(0, 10).researching, 0)
tick(5); eq(snapshot(0, 10).research_group, "lumberjack_speed")
eq(snapshot(0, 10).started_at, 5, "auto still waits one second after manual queue drains")

for _, reason in ipairs({ "destroyed", "disconnected", "defeated" }) do
    fixture()
    local before = resources[0].wood
    for index = 1, 7 do assert(manual(0, 10, "lumberjack_speed").ok) end
    if reason == "destroyed" then
        local old = buildings[10]; buildings[10] = nil
        bus.emit(events.BUILDING_DESTROYED, old)
    else
        bus.emit(reason == "defeated" and events.PLAYER_DEFEATED or events.PLAYER_DISCONNECTED,
            { player_id = 0, team = 2 })
    end
    eq(resources[0].wood, before, reason .. " refunds active only; waiting jobs were free")
    eq(refunds, 1)
    eq(snapshot(0, 10).queue_count, 0); eq(#snapshot(0, 10).queued, 0)
    tick(20); eq(level(0, "RS-01"), 0, reason .. " cancels all queued callbacks")
end

fixture()
local original_commit = research.service().CommitUpgrade
local failed_once = false
research.service().CommitUpgrade = function(self, payload)
    if not failed_once then
        failed_once = true
        return self:RollbackUpgrade({ transaction_id = payload.transaction_id,
            error_code = "test_transient_failure" })
    end
    return original_commit(self, payload)
end
local before_failure = resources[0].wood
assert(manual(0, 10, "lumberjack_speed").ok)
assert(manual(0, 10, "lumberjack_speed").ok)
tick(2)
eq(level(0, "RS-01"), 0); eq(resources[0].wood, before_failure)
eq(snapshot(0, 10).blocked_head.target_level, 1)
eq(snapshot(0, 10).queued[1].target_level, 2, "failed target remains before its dependent level")
tick(3); eq(snapshot(0, 10).target_level, 1)
tick(5); eq(level(0, "RS-01"), 1); eq(snapshot(0, 10).target_level, 2)
tick(7); eq(level(0, "RS-01"), 2)
eq(resources[0].wood, before_failure - first_cost - second_cost,
    "failed/retried queue task is not double charged")
-- Existing shop purchase requests enter the same capacity-limited queue;
-- their catalog cards remain usable while another technology is researching.
fixture()
local advanced_entry = catalog.find_technology_entry(shared_group, 1)
local open_queue = bus.request(events.SHOP_OPEN_REQUEST,
    { player_id = 0, source_entindex = 12, mode = "research" })
assert(open_queue.ok)
for index = 1, 6 do
    assert(bus.request(events.SHOP_PURCHASE_REQUEST, { player_id = 0,
        source_entindex = 12, entry_id = advanced_entry.entryid }).ok)
end
local queued_view = bus.request(events.SHOP_OPEN_REQUEST,
    { player_id = 0, source_entindex = 12, mode = "research" }).snapshot
local card
for _, row in ipairs(queued_view.entries) do
    if row.technology_group == shared_group then card = row end
end
assert(card and card.purchasable == 1, "busy research card can still enqueue")
eq(card.next_technology_level, 7, "shop card projects following reserved target")
assert(card.cost_timing_text:find("开始研究时扣费", 1, true))
assert(bus.request(events.SHOP_PURCHASE_REQUEST, { player_id = 0,
    source_entindex = 12, entry_id = advanced_entry.entryid }).ok)
eq(bus.request(events.SHOP_PURCHASE_REQUEST, { player_id = 0,
    source_entindex = 12, entry_id = advanced_entry.entryid }).error_code, "research_queue_full")
-- Ordinary and shared advanced labs use identical seven-slot rules.
-- Teammates sharing one advanced entity have private jobs, costs and levels.
fixture()
resources[1].gold = 0; resources[1].wood = 0
for index = 1, 7 do
    assert(manual(0, 10, "lumberjack_speed").ok)
    assert(manual(0, 12, shared_group).ok)
    assert(manual(1, 12, shared_group).ok, "shared advanced lab keeps teammate's queue independent")
end
for _, case in ipairs({ { 0, 10, "lumberjack_speed" }, { 0, 12, shared_group },
    { 1, 12, shared_group } }) do
    local view = snapshot(case[1], case[2])
    eq(view.capacity, 7); eq(view.queue_count, 7); eq(#view.queued, 6)
    eq(view.queued[6].target_level, 7)
    eq(manual(case[1], case[2], case[3]).error_code, "research_queue_full",
        "eighth ordinary/shared-advanced task is rejected")
end
local private_blocked = snapshot(1, 12)
eq(private_blocked.researching, 0); eq(private_blocked.blocked_head.target_level, 1)
assert(private_blocked.blocked_head.job_id ~= snapshot(0, 12).active_job.job_id,
    "shared entity never exposes another player's job identity")
eq(resources[1].wood, 0, "unfunded teammate was not charged for seven waiting jobs")
tick(2)
eq(level(0, "RS-01"), 1); eq(level(0, "ARS-01"), 1)
eq(level(1, "ARS-01"), 0, "teammate does not inherit completed research")
eq(snapshot(0, 12).target_level, 2)
eq(snapshot(1, 12).blocked_head.target_level, 1)
eq(#snapshot(1, 12).queued, 6, "blocked teammate keeps all six waiting icons")
resources[1].gold = 1000000000; resources[1].wood = 1000000000
tick(3)
eq(snapshot(1, 12).researching, 1); eq(snapshot(1, 12).started_at, 3)
eq(snapshot(1, 12).finish_at, 5)
tick(4); eq(level(0, "ARS-01"), 2); eq(level(1, "ARS-01"), 0)
tick(5); eq(level(1, "ARS-01"), 1)
eq(snapshot(1, 12).target_level, 2)
print("RESEARCH_PRODUCTION_AUTO_PASS: two-second FIFO 1+6, start-time charge, idempotency, blocked head, auto pause/isolation, failure/lifecycle refunds")
