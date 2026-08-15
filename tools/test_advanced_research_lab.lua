package.path = table.concat({
    "scripts/vscripts/?.lua",
    "scripts/vscripts/?/init.lua",
    package.path,
}, ";")

local handlers = {}
local subscribers = {}
local scheduled = {}
local requests = {}
local game_time = 0
local levels = {}
local resources = { wood = 999999999, gold = 999999999 }
local advanced_building = {
    entindex = 701,
    building_id = "building_advanced_research_lab",
    team = 2,
    player_id = 0,
    level = 1,
}
local standard_building = {
    entindex = 702,
    building_id = "building_research_lab",
    team = 2,
    player_id = 0,
    level = 1,
}
local main_city = {
    entindex = 700,
    building_id = "main_city",
    team = 2,
    player_id = 0,
    level = 4,
}

package.preload["core/event_bus"] = function()
    return {
        handle_request = function(name, callback) handlers[name] = callback end,
        subscribe = function(name, callback)
            subscribers[name] = subscribers[name] or {}
            subscribers[name][#subscribers[name] + 1] = callback
        end,
        emit = function(name, payload)
            for _, callback in ipairs(subscribers[name] or {}) do callback(payload) end
        end,
        request = function(name, payload)
            requests[#requests + 1] = { name = name, payload = payload }
            if name == "building.query.request" then
                local entindex = tonumber(payload.entindex)
                if advanced_building and entindex == advanced_building.entindex then
                    return advanced_building
                end
                if standard_building and entindex == standard_building.entindex then
                    return standard_building
                end
                return nil
            end
            if name == "building.list.request" then
                local buildings = { main_city }
                if advanced_building then buildings[#buildings + 1] = advanced_building end
                if standard_building then buildings[#buildings + 1] = standard_building end
                return { ok = true, buildings = buildings }
            end
            if name == "resource.get.request" then return resources end
            if name == "research:state_get_requested" then
                return { ok = true, legacy_levels = levels }
            end
            if name == "research:upgrade_begin_requested" then
                local config = require("config/research_technology_config")
                local definition = config.by_id[payload.tech_id]
                local group = definition.legacy_group
                local target = (levels[group] or 0) + 1
                local cost = config.cost_for_level(definition, target)
                local required = definition.prerequisite or {}
                if required.tech_id then
                    local prerequisite = config.by_id[required.tech_id]
                    if (levels[prerequisite.legacy_group] or 0)
                        < (required.required_level or 0) then
                        return { success = false, error_code = "prerequisite_not_met" }
                    end
                end
                if resources.gold < cost.gold then
                    return { success = false, error_code = "insufficient_gold" }
                end
                if resources.wood < cost.wood then
                    return { success = false, error_code = "insufficient_wood" }
                end
                resources.gold = resources.gold - cost.gold
                resources.wood = resources.wood - cost.wood
                return {
                    success = true,
                    transaction_id = payload.tech_id .. ":" .. tostring(target),
                    new_level = target,
                }
            end
            if name == "research:upgrade_commit_requested" then
                local tech_id, target = string.match(
                    payload.transaction_id,
                    "^(A?RS%-%d+):(%d+)$"
                )
                local definition = require("config/research_technology_config").by_id[tech_id]
                levels[definition.legacy_group] = tonumber(target)
                return { success = true, new_level = tonumber(target) }
            end
            if name == "content.inventory_get.request" then
                return { snapshot = { counts = {} } }
            end
            if name == "hero.summon_snapshot.request" then return { snapshot = {} } end
            if name == "player.entitlement_get.request" then return { snapshot = {} } end
            if name == "hero.progression_get.request" then
                return { snapshot = { rebirth_level = 10 } }
            end
            if name == "wave.state_get.request" then return {} end
            if name == "monster.encounter.query.request" then return { ok = true } end
            local handler = handlers[name]
            return handler and handler(payload) or nil
        end,
    }
end

package.preload["core/scheduler"] = function()
    return {
        after = function(_, callback, id)
            scheduled[id] = callback
            return id
        end,
        cancel = function(id) scheduled[id] = nil end,
    }
end

package.preload["systems/shop_grant_service"] = function()
    return { grant = function() return { ok = true } end,
        refund = function() return { ok = true } end }
end

PlayerResource = {
    IsValidPlayerID = function(_, player_id) return player_id == 0 or player_id == 1 end,
    GetTeam = function() return 2 end,
}
GameRules = { GetGameTime = function() return game_time end }
DOTA_MAX_TEAM_PLAYERS = 4

local events = require("core/events")
local shop = require("systems/shop_system")
shop.init()
local test = shop._advanced_research_for_test

local function check(value, message)
    if not value then error(message, 2) end
end

local advanced = test.open_shop({
    player_id = 1,
    mode = "research",
    source_entindex = advanced_building.entindex,
})
check(advanced.ok == true, "ADVANCED_RESEARCH_OPEN_FAILED")
check(advanced.snapshot.research_scope == "advanced", "ADVANCED_SCOPE_MISSING")
check(#advanced.snapshot.entries == 10, "ADVANCED_CATALOG_NOT_EXCLUSIVE")
for index, entry in ipairs(advanced.snapshot.entries) do
    check(entry.technology_id == string.format("ARS-%02d", index),
        "ADVANCED_CATALOG_ORDER_INVALID")
end

local invalid = test.open_shop({
    player_id = 1,
    mode = "research",
    source_entindex = 999,
})
check(invalid.ok == false, "INVALID_SOURCE_ACCEPTED")

local missing = test.open_shop({
    player_id = 1,
    mode = "research",
})
check(missing.ok == false and missing.error == "research_source_required",
    "MISSING_RESEARCH_SOURCE_ACCEPTED")

local standard = test.open_shop({
    player_id = 0,
    mode = "research",
    source_entindex = standard_building.entindex,
})
check(standard.ok == false, "STANDARD_RESEARCH_WINDOW_STILL_AVAILABLE")

local mappings = require("config/generated/research_lab_abilities")
local building_config = require("config/buildings_config")
local research_config = require("config/research_technology_config")
local normal_groups = 0
local advanced_groups = 0
for _, definition in ipairs(research_config.technologies) do
    if definition.building_id == "research_lab" then
        normal_groups = normal_groups + 1
    elseif definition.building_id == "advanced_research_lab" then
        advanced_groups = advanced_groups + 1
    end
end
check(normal_groups == 9 and advanced_groups == 10,
    "RESEARCH_GROUP_PARTITION_INVALID")
check(research_config.by_legacy_group.gold_mine_efficiency == nil
        and research_config.by_legacy_group.gold_mine_crit == nil,
    "GOLD_MINE_TECHNOLOGY_ENTERED_RESEARCH_CONFIG")
local standard_mappings = {}
local advanced_mappings = {}
for _, mapping in ipairs(mappings.rows) do
    if mapping.building_id == "building_research_lab" then
        standard_mappings[#standard_mappings + 1] = mapping
    elseif mapping.building_id == "building_advanced_research_lab" then
        advanced_mappings[#advanced_mappings + 1] = mapping
    end
end
check(#standard_mappings == 9, "STANDARD_RESEARCH_ABILITY_COUNT_INVALID")
check(#advanced_mappings == 10, "ADVANCED_RESEARCH_ABILITY_COUNT_INVALID")
check(#building_config.building_research_lab.abilities == 6,
    "STANDARD_RESEARCH_BUILDING_ABILITY_COUNT_INVALID")
local initial_standard = {}
for _, mapping in ipairs(standard_mappings) do
    if mapping.chain_order == 1 then initial_standard[#initial_standard + 1] = mapping end
end
for index, mapping in ipairs(initial_standard) do
    check(mapping.slot_order == index, "STANDARD_RESEARCH_SLOT_ORDER_INVALID")
    check(building_config.building_research_lab.abilities[index]
            == mapping.ability_name,
        "STANDARD_RESEARCH_BUILDING_SLOT_INVALID")
    local definition = research_config.by_id[mapping.technology_id]
    local required = definition and definition.prerequisite or {}
    if required.tech_id then
        local prerequisite = research_config.by_id[required.tech_id]
        levels[prerequisite.legacy_group] = required.required_level
    end
    local started = test.purchase_next({
        player_id = 0,
        technology_group = mapping.technology_group,
        source_entindex = standard_building.entindex,
        source = "research_lab_ability",
    })
    check(started.ok == true and started.research_started == true,
        "STANDARD_RESEARCH_DIRECT_START_FAILED:" .. tostring(started.error))
    check((levels[mapping.technology_group] or 0) == 0,
        "STANDARD_RESEARCH_COMMITTED_TOO_EARLY")
    local completion = scheduled["shop_technology_cooldown:2"]
    check(type(completion) == "function", "STANDARD_RESEARCH_COMPLETION_NOT_SCHEDULED")
    game_time = game_time + 2
    completion()
    check(levels[mapping.technology_group] == 1,
        "STANDARD_RESEARCH_DIRECT_COMMIT_FAILED")
end

local first_mapping = mappings.rows[1]
levels[first_mapping.technology_group] = require("config/research_technology_config")
    .by_legacy_group[first_mapping.technology_group].max_level
local maximum = test.purchase_next({
    player_id = 0,
    technology_group = first_mapping.technology_group,
    source_entindex = standard_building.entindex,
    source = "research_lab_ability",
})
check(maximum.ok == false and maximum.error == "科技已满级",
    "STANDARD_RESEARCH_MAX_LEVEL_ACCEPTED")

standard_building = nil
local standard_purchase = test.purchase_next({
    player_id = 0,
    technology_group = initial_standard[2].technology_group,
    source_entindex = 702,
    source = "research_lab_ability",
})
check(standard_purchase.ok == false
        and standard_purchase.error == "research_source_invalid",
    "DESTROYED_STANDARD_SOURCE_ACCEPTED")

local group1 = "researcher_lumberjack_attack_growth"
local group2 = "researcher_lumberjack_armor_reduction"
check(test.toggle({ player_id = 0, technology_group = group2,
    source_entindex = advanced_building.entindex }).ok, "ARS02_TOGGLE_FAILED")
check(test.toggle({ player_id = 1, technology_group = group1,
    source_entindex = advanced_building.entindex }).ok, "ARS01_TOGGLE_FAILED")

local team_state = test.state().auto_research_by_team[2]
check(team_state[group1] and team_state[group2], "TEAM_AUTO_STATE_NOT_SHARED")
test.run(2)
local pending = test.state().technology_research_transaction_by_team[2]
check(pending and pending.technology_group == group1, "ARS_ORDER_NOT_DETERMINISTIC")

game_time = game_time + 2
local completion = scheduled["shop_technology_cooldown:2"]
check(type(completion) == "function", "RESEARCH_COMPLETION_NOT_SCHEDULED")
completion()
check(levels[group1] == 1, "ARS01_NOT_COMMITTED")

local next_tick = scheduled["shop_auto_research:2"]
check(type(next_tick) == "function", "AUTO_RESEARCH_NOT_CONTINUED")
next_tick()
pending = test.state().technology_research_transaction_by_team[2]
check(pending and pending.technology_group == group1,
    "ENABLED_ARS01_DID_NOT_CONTINUE_TO_NEXT_LEVEL")

test.state().technology_research_transaction_by_team[2] = nil
test.state().technology_cooldown_until_by_team[2] = 0
levels[group1] = require("config/research_technology_config").by_id["ARS-01"].max_level
resources.gold = 0
test.run(2)
check(test.state().auto_research_by_team[2][group1] == nil,
    "COMPLETED_ARS_NOT_SKIPPED")
check(test.state().auto_research_by_team[2][group2] ~= nil,
    "RESOURCE_SHORTAGE_DISABLED_ARS")
check(type(scheduled["shop_auto_research:2"]) == "function",
    "RESOURCE_SHORTAGE_NOT_RETRIED")

local group3 = "researcher_super_wall_health"
local group4 = "researcher_super_wall_armor"
resources.gold = 999999999
resources.wood = 999999999
test.state().auto_research_by_team[2] = {
    [group3] = { player_id = 0, source_entindex = 701 },
    [group4] = { player_id = 1, source_entindex = 701 },
}
test.run(2)
check(test.state().technology_research_transaction_by_team[2] == nil,
    "TEMPORARY_BLOCK_SKIPPED_TO_HIGHER_ARS")
check(type(scheduled["shop_auto_research:2"]) == "function",
    "TEMPORARY_BLOCK_NOT_RETRIED")

advanced_building = nil
scheduled["shop_auto_research:2"]()
check(next(test.state().auto_research_by_team[2]) == nil,
    "DESTROYED_SOURCE_DID_NOT_STOP_AUTO_RESEARCH")

print("ADVANCED_RESEARCH_LAB_LUA51_PASS")