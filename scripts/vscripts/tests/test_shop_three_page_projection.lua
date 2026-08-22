package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local catalog = require("systems/shop_catalog")
local research_config = require("config/research_technology_config")

local function context(mode, levels, rebirth_level, active_encounters, purchased_count)
    return {
        sequence = 1,
        reason = "test",
        resources = { wood = 10 ^ 12, gold = 10 ^ 12 },
        purchased_count = { [0] = purchased_count or {} },
        city_level = 99,
        building_counts = {
            hero_altar = 1,
            building_research_lab = 1,
            building_advanced_research_lab = 1,
        },
        hero_summoned = true,
        vip = true,
        rebirth_level = rebirth_level == nil and 10 or rebirth_level,
        owned_content = {},
        active_challenge_encounters = active_encounters or {},
        technology_levels = { [0] = levels or {} },
        research_unlocked = true,
        advanced_researcher_unlocked = true,
        debug_all_unlocked = false,
        technology_cooldown_remaining = 0,
        wave_state = {
            game_started = true,
            current_wave = 1,
            total_waves = 30,
            early_final_remaining = 0,
            early_final_used = false,
            victory_settled = false,
        },
        ui_mode = mode,
    }
end

local function entries(snapshot)
    local result = {}
    for _, entry in ipairs(snapshot.entries or {}) do
        result[#result + 1] = entry
    end
    return result
end

local function technology_entry(snapshot, group)
    for _, entry in ipairs(snapshot.entries or {}) do
        if entry.technology_group == group then return entry end
    end
    return nil
end

local function technology_ui_position(snapshot, group)
    local projected = entries(snapshot)
    table.sort(projected, function(a, b)
        local a_section = a.technology_track == "advanced_researcher" and 20 or 10
        local b_section = b.technology_track == "advanced_researcher" and 20 or 10
        if a_section ~= b_section then return a_section < b_section end
        return (tonumber(a.sort_order) or 0) < (tonumber(b.sort_order) or 0)
    end)
    for index, entry in ipairs(projected) do
        if entry.technology_group == group then return index end
    end
    return nil
end

local shop = entries(catalog.build_snapshot(0, context("shop")))
local early_final = nil
for _, entry in ipairs(shop) do
    assert(entry.content_type ~= "technology", "shop page leaked technology")
    assert(entry.content_type ~= "challenge", "shop page leaked normal challenge")
    assert(entry.content_type ~= "rebirth", "shop page leaked rebirth challenge")
    if entry.content_id == "service_early_final_boss" then
        early_final = entry
    end
end
assert(early_final, "shop page is missing early-clear service")
assert(early_final.gold_cost == 50000, "early-clear price must be 50000 gold")
assert(early_final.purchase_limit == 1, "early-clear service must be limited to one")
assert(early_final.shop_id == "item", "early-clear service must belong to shop page")

local research_snapshot = catalog.build_snapshot(0, context("research"))
local research = entries(research_snapshot)
assert(#research == 19, "research page must project exactly 19 technology groups")
local groups = {}
local locked_prerequisite = nil
for _, entry in ipairs(research) do
    assert(entry.content_type == "technology", "research page leaked non-technology")
    assert(entry.technology_group and entry.technology_group ~= "",
        "technology group projection is missing")
    assert(not groups[entry.technology_group], "technology group was projected twice")
    groups[entry.technology_group] = true
    assert(entry.level_text == "Lv.0 / " .. tostring(entry.technology_max_level),
        "technology level text is incorrect")
    if entry.technology_group == "advanced_lumberjack_speed" then
        locked_prerequisite = entry
    end
end
assert(locked_prerequisite and locked_prerequisite.purchasable == 0,
    "unmet prerequisite technology must remain visible and disabled")
assert(locked_prerequisite.disabled_reason_code == "prerequisite_not_met",
    "unmet prerequisite technology returned wrong reason code")
assert(locked_prerequisite.prerequisite_technology_id == "RS-01",
    "prerequisite technology id is missing")

local stable_group = "lumberjack_efficiency"
local stable_sort_order = assert(technology_entry(research_snapshot, stable_group),
    "stable-order technology is missing").sort_order
local stable_ui_position = technology_ui_position(research_snapshot, stable_group)
for _, current_level in ipairs({ 8, 9, 10, 11, 12 }) do
    local snapshot = catalog.build_snapshot(0,
        context("research", { [stable_group] = current_level }))
    local entry = assert(technology_entry(snapshot, stable_group),
        "stable-order technology disappeared at level " .. tostring(current_level))
    assert(entry.next_technology_level == current_level + 1,
        "technology projected the wrong next level at current level "
            .. tostring(current_level))
    assert(entry.sort_order == stable_sort_order,
        "technology shelf order changed at current level "
            .. tostring(current_level))
    assert(technology_ui_position(snapshot, stable_group) == stable_ui_position,
        "technology moved to another UI slot at current level "
            .. tostring(current_level))
end
assert(locked_prerequisite.prerequisite_technology_group == "lumberjack_speed",
    "prerequisite technology group is missing")
assert(locked_prerequisite.prerequisite_current_level == 0
    and locked_prerequisite.prerequisite_required_level == 5,
    "prerequisite current/required levels are incorrect")
assert(locked_prerequisite.disabled_reason:find("当前Lv.0", 1, true),
    "prerequisite disabled reason must expose the current level")

local prerequisite_unlocked = entries(catalog.build_snapshot(0,
    context("research", { lumberjack_speed = 5 })))
for _, entry in ipairs(prerequisite_unlocked) do
    if entry.technology_group == "advanced_lumberjack_speed" then
        assert(entry.purchasable == 1,
            "technology did not become purchasable after its prerequisite was met")
        assert(entry.prerequisite_met == 1,
            "unlocked technology still reports an unmet prerequisite")
    end
end

local rebirth_locked = entries(catalog.build_snapshot(0,
    context("research", {}, 0)))
local hero_final_damage = nil
for _, entry in ipairs(rebirth_locked) do
    if entry.technology_group == "researcher_hero_final_damage" then
        hero_final_damage = entry
    end
end
assert(hero_final_damage and hero_final_damage.purchasable == 0,
    "three-rebirth technology must remain visible and disabled")
assert(hero_final_damage.disabled_reason_code == "rebirth_level_not_met",
    "three-rebirth technology returned the wrong reason code")
assert(hero_final_damage.prerequisite_rebirth_level == 3,
    "three-rebirth prerequisite metadata is missing")
assert(hero_final_damage.disabled_reason:find("当前0转", 1, true),
    "rebirth disabled reason must expose the current rebirth level")

local rebirth_unlocked = entries(catalog.build_snapshot(0,
    context("research", {}, 3)))
for _, entry in ipairs(rebirth_unlocked) do
    if entry.technology_group == "researcher_hero_final_damage" then
        assert(entry.purchasable == 1,
            "technology did not become purchasable after rebirth prerequisite was met")
    end
end

local max_levels = {}
for _, definition in ipairs(research_config.technologies) do
    max_levels[definition.legacy_group] = definition.max_level
end
local maxed = entries(catalog.build_snapshot(0, context("research", max_levels)))
assert(#maxed == 19, "maxed technologies must remain visible")
for _, entry in ipairs(maxed) do
    assert(entry.purchasable == 0, "maxed technology remained purchasable")
    assert(entry.disabled_reason_code == "max_level_reached",
        "maxed technology reason code is incorrect: "
            .. tostring(entry.technology_group) .. "="
            .. tostring(entry.disabled_reason_code) .. " reason="
            .. tostring(entry.disabled_reason))
end

local challenge = entries(catalog.build_snapshot(0, context("challenge")))
local normal_count, rebirth_count = 0, 0
local purchasable_rebirth_count = 0
for _, entry in ipairs(challenge) do
    if entry.content_type == "challenge" then normal_count = normal_count + 1
    elseif entry.content_type == "rebirth" then
        rebirth_count = rebirth_count + 1
        if entry.purchasable == 1 then
            purchasable_rebirth_count = purchasable_rebirth_count + 1
        end
    else error("challenge page leaked content type " .. tostring(entry.content_type)) end
end
assert(normal_count == 11, "challenge page must project all 11 normal challenges")
assert(rebirth_count == 0, "ten rebirths must hide all rebirth challenges")
assert(purchasable_rebirth_count == 0,
    "ten rebirths must not leave a purchasable rebirth challenge")

for _, current_rebirth in ipairs({ 0, 5, 9 }) do
    local projected = entries(catalog.build_snapshot(0,
        context("challenge", {}, current_rebirth)))
    local rebirth_entries = {}
    for _, entry in ipairs(projected) do
        if entry.content_type == "rebirth" then
            rebirth_entries[#rebirth_entries + 1] = entry
        end
    end
    assert(#rebirth_entries == 1,
        "challenge page must project exactly the next rebirth challenge")
    assert(rebirth_entries[1].content_id == string.format(
        "rebirth_challenge_%02d",
        current_rebirth + 1
    ),
        "challenge page projected the wrong rebirth stage")
end

local active_rebirth = entries(catalog.build_snapshot(0,
    context(
        "challenge",
        {},
        0,
        { encounter_rebirth_01 = true },
        { ["rebirth:rebirth_challenge_01"] = 1 }
    )))
for _, entry in ipairs(active_rebirth) do
    if entry.content_type == "rebirth" then
        assert(entry.challenge_active == 1,
            "active rebirth challenge did not expose its active state")
        assert(entry.wood_cost == 10000 and entry.gold_cost == 0,
            "active rebirth challenge must retain its original price")
        assert(entry.purchasable == 1,
            "active rebirth challenge must remain purchasable for re-entry")
    end
end

print("SHOP_THREE_PAGE_PROJECTION_PASS")
