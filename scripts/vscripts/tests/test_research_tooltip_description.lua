package.path = "scripts/vscripts/?.lua;" .. package.path

local config = require("config/research_technology_config")
local description = require("research/research_technology_description")
local builder = require("ui/ability_runtime_builder")
local mappings = require("config/generated/research_lab_abilities")

local function contains(text, fragment)
    assert(text:find(fragment, 1, true), fragment .. " missing from " .. text)
end

local function absent(text, fragment)
    assert(not text:find(fragment, 1, true), fragment .. " leaked into " .. text)
end

local function lines(text)
    local result = {}
    for line in text:gmatch("[^\n]+") do result[#result + 1] = line end
    return result
end

-- The screenshot's unresearched and researched states show each comparison
-- separately; only the requested current cumulative field remains below.
local speed = config.by_id["RS-01"]
assert(description.build(speed, 0, 1) == "所有伐木工：每级攻击速度+5%。\n"
    .. "当前Lv.0：尚未生效。\n升级后Lv.1：攻击速度+5%。")
assert(description.build(speed, 2, 3) == "所有伐木工：每级攻击速度+5%。\n"
    .. "当前Lv.2：攻击速度+10%。\n升级后Lv.3：攻击速度+15%。")
assert(description.effect_summary(speed, 2) == "攻击速度+10%",
    "compact display must preserve accumulated effect values")

local count = 0
for _, definition in ipairs(config.technologies) do
    local text = description.build(definition, 0, 1)
    local split = lines(text)
    assert(#split == 3, definition.tech_id .. " must have three description rows")
    contains(split[1], "：每级")
    contains(split[2], "当前Lv.0：尚未生效。")
    contains(split[3], "升级后Lv.1：")
    for _, unwanted in ipairs({"即时刷新", "保持当前", "统一伤害结算", "Dota实际护甲",
        "加入研究队列", "扣费", "等级上限", "当前累计", "升级后累计", "自动研究", "自动间隔"}) do
        absent(text, unwanted)
    end
    local fields = description.fields(definition, 0, 1)
    assert(#fields == 1 and fields[1].label == "当前累计"
        and fields[1].value == "尚未生效")
    local final = description.sections(definition, definition.max_level, definition.max_level)
    assert(final.next_effect_text == "", "completed research has no next-level comparison")
    assert(#lines(description.build(definition, definition.max_level, definition.max_level)) == 2)
    count = count + 1
end
assert(count == 19)

-- Essential gameplay limits and multipliers remain with the effect summary.
contains(description.sections(config.by_id["RS-02"], 0, 1).research_effect_description,
    "攻击间隔最低为0.05秒。")
contains(description.sections(config.by_id["RS-03"], 0, 1).research_effect_description,
    "采集暴击时获得2倍木材。")
contains(description.sections(config.by_id["ARS-02"], 0, 1).research_effect_description,
    "大树护甲最低为100。")
contains(description.sections(config.by_id["ARS-07"], 0, 1).research_effect_description,
    "科技暴击造成2倍伤害。")

local function max_levels()
    local result = {}
    for _, definition in ipairs(config.technologies) do
        result[definition.legacy_group] = definition.max_level
    end
    return result
end

local function runtime(row, current, transaction, levels)
    local available_levels = levels or max_levels()
    available_levels[row.technology_group] = current
    return builder.build(row.ability_name, {player_id = 0, building_id = row.building_id,
        research_levels = available_levels, research_transaction = transaction or {},
        reincarnation_level = 10}, {wood = 0, gold = 0})
end

local checked = 0
for _, row in ipairs(mappings.rows) do
    if row.enabled ~= false then
        local definition = assert(config.by_legacy_group[row.technology_group])
        local result = runtime(row, 0)
        assert(result.research_upgrade == 1 and result.available == 1)
        assert(result.current_level == 0 and result.next_level == 1)
        assert(result.research_status_code == "available" and result.status_text == "可以研究")
        assert(result.can_afford == 1 and result.resource_check_on_cast == 1,
            "display cleanup must preserve click-time resource checks")
        local cost = config.cost_for_level(definition, 1)
        assert(result.cost_wood == (cost.wood or 0) and result.cost_gold == (cost.gold or 0),
            "research prices must remain unchanged")
        assert(result.cost_timing_text == nil and #result.fields == 1
            and result.fields[1].label == "当前累计" and result.fields[1].value == "尚未生效")
        assert(result.upgrade_description == result.research_effect_description .. "\n"
            .. result.current_effect_text .. "\n" .. result.next_effect_text)
        local final = runtime(row, definition.max_level)
        assert(final.completed == 1 and final.available == 0 and final.research_status_code == "max_level")
        assert(final.next_effect_text == "" and final.next_level == definition.max_level)
        assert(#final.fields == 1 and final.fields[1].label == "当前累计"
            and final.fields[1].value == description.effect_summary(definition, definition.max_level))
        assert(final.cost_wood == 0 and final.cost_gold == 0)
        checked = checked + 1
    end
end
assert(checked == 19)

-- Queue targeting, absolute timer values and automatic research controls are
-- still supplied to their owning components; only tooltip copy is removed.
local speed_row = assert(mappings.by_id.ability_research_lumberjack_speed)
local queued = runtime(speed_row, 0, {queue_count = 1, capacity = 7,
    reserved_levels = {lumberjack_speed = 1}, researching = 1,
    research_group = "lumberjack_speed", target_level = 1,
    started_at = 5, finish_at = 7, duration = 2, next_start_at = 8,
    auto_research = {lumberjack_speed = true}})
assert(queued.available == 1 and queued.next_level == 2 and queued.reserved_level == 1)
assert(queued.research_status_code == "queue_available" and queued.status_text == "可以研究")
assert(queued.research_started_at == 5 and queued.research_until == 7 and queued.research_total == 2)
assert(queued.auto_research_next_at == 8 and queued.auto_research_available == 1
    and queued.auto_research_enabled == 1)
contains(queued.next_effect_text, "升级后Lv.2：攻击速度+10%。")
local full = runtime(speed_row, 0, {queue_count = 7, capacity = 7})
assert(full.available == 0 and full.research_status_code == "research_queue_full")
assert(full.status_text == "研究队列已满" and full.prerequisite_met == 1)
local reserved = runtime(speed_row, 0, {queue_count = 1, capacity = 7,
    reserved_levels = {lumberjack_speed = speed.max_level}})
assert(reserved.available == 0 and reserved.completed == 0
    and reserved.research_status_code == "queued_max_level" and reserved.next_effect_text == "")
local locked_row = assert(mappings.by_id.ability_research_ars_03)
local locked = runtime(locked_row, 0, {}, {})
assert(locked.available == 0 and locked.prerequisite_met == 0
    and locked.research_status_code == "prerequisite_not_met")
assert(locked.status_text == "前置科技或转职要求未满足")

print("RESEARCH_TOOLTIP_DESCRIPTION_PASS: 19 technologies, separate comparison rows, no implementation details; costs, prerequisites, queue targets, timers and auto controls preserved")
