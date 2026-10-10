package.path = "scripts/vscripts/?.lua;" .. package.path
local catalog = require("systems/shop_catalog")
local config = require("config/research_technology_config")
local context = {
    ui_mode = "research", research_scope = "normal",
    resources = {gold = 0, wood = 0}, purchased_count = {[0] = {}},
    technology_levels = {[0] = {}}, city_level = 10, rebirth_level = 10,
    research_unlocked = true, advanced_researcher_unlocked = true,
    building_counts = {research_lab = 1, advanced_research_lab = 1}, owned_content = {},
    hero_summoned = true,
}
local function snapshot()
    local result = {}
    for _, row in ipairs(catalog.build_snapshot(0, context).entries) do
        if row.content_type == "technology" then result[row.technology_group] = row end
    end
    return result
end
for _, scope in ipairs({"normal", "advanced"}) do
    context.research_scope = scope
    context.resources = {gold = 0, wood = 0}
    local poor = snapshot()
    assert(next(poor), "fixture must project real technology entries")
    context.resources = {gold = 1e15, wood = 1e15}
    local rich = snapshot()
    for group, row in pairs(poor) do
        assert(row.prerequisite_met == rich[group].prerequisite_met
            and row.purchasable == rich[group].purchasable
            and row.disabled_reason == rich[group].disabled_reason,
            "wallet changes must not change technology state: " .. group)
        assert(row.can_afford == 1 and row.resource_check_on_cast == 1)
    end
end
context.research_scope = "normal"
assert(snapshot().lumberjack_speed.prerequisite_met == 1)
assert(snapshot().advanced_lumberjack_speed.prerequisite_met == 0)
local advanced = config.by_legacy_group.advanced_lumberjack_speed
local predecessor = config.by_id[advanced.prerequisite.tech_id]
context.technology_levels[0][predecessor.legacy_group] = advanced.prerequisite.required_level
assert(snapshot().advanced_lumberjack_speed.prerequisite_met == 1,
    "finishing the actual preceding technology unlocks its successor")
context.research_unlocked = false
assert(snapshot().advanced_lumberjack_speed.prerequisite_met == 0,
    "research building access participates in prerequisites")
context.research_unlocked = true
context.research = {source_entindex = 10, queue_count = 7, capacity = 7, reserved_levels = {}}
local queued = snapshot().advanced_lumberjack_speed
assert(queued.prerequisite_met == 1 and queued.purchasable == 0
    and queued.disabled_reason_code == "research_queue_full",
    "queue fullness preserves unlocked appearance but still rejects execution")
print("RESEARCH_CATALOG_PREREQUISITES_PASS: wallet-independent normal/advanced technology cards, research access, predecessor completion and queue capacity")
