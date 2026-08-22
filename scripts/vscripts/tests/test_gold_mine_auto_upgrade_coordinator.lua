package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local events = require("core/events")
local handlers = {}
local subscribers = {}
local scheduled = {}
local technology = {
    gold_mine_efficiency = 0,
    gold_mine_crit = 0,
}
local technology_purchases = 0
local mine_upgrades = 0

local event_bus = {}
function event_bus.handle_request(name, handler) handlers[name] = handler end
function event_bus.subscribe(name, handler)
    subscribers[name] = subscribers[name] or {}
    subscribers[name][#subscribers[name] + 1] = handler
end
function event_bus.emit(name, payload)
    for _, handler in ipairs(subscribers[name] or {}) do handler(payload) end
end
function event_bus.request(name, payload)
    if handlers[name] then return handlers[name](payload) end
    if name == events.TECHNOLOGY_STATE_GET_REQUEST then
        return { ok = true, levels = technology }
    end
    if name == events.TECHNOLOGY_PURCHASE_NEXT_REQUEST then
        technology_purchases = technology_purchases + 1
        local group = payload.technology_group
        technology[group] = technology[group] + 1
        event_bus.emit(events.TECHNOLOGY_CHANGED, {
            player_id = payload.player_id,
            technology_group = group,
            level = technology[group],
            levels = technology,
        })
        return { ok = true, level = technology[group] }
    end
    if name == events.RESOURCE_TRY_SPEND_REQUEST then
        return { ok = true }
    end
    error("unexpected coordinator request: " .. tostring(name))
end

package.loaded["core/event_bus"] = event_bus
package.loaded["core/scheduler"] = {
    after = function(_, callback, key) scheduled[key] = callback end,
    every = function() end,
    cancel = function(key) scheduled[key] = nil end,
}
package.loaded["config/gold_mine_config"] = {
    max_mine_level = 2,
    max_efficiency_level = 2,
    max_crit_level = 1,
    production_interval = 1,
    mine_upgrade_cost = function() return { wood = 100, gold = 0 } end,
    level_data = function(level)
        return { health = 100 + level, armor = level, base_income = level }
    end,
    normal_income = function() return 1 end,
    efficiency_percent = function() return 0 end,
    efficiency_bonus = function() return 0 end,
    crit_chance = function() return 0 end,
    crit_multiplier = function() return 3 end,
    income_amount = function() return 1 end,
}
package.loaded["systems/building_visual_service"] = { apply = function() end }
package.loaded["systems/building_sound_service"] = {
    upgrade_completed = function() end,
}
package.loaded["systems/building_upgrade_process"] = {
    is_active = function() return false end,
    begin = function(_, options)
        mine_upgrades = mine_upgrades + 1
        options.on_start()
        options.on_complete()
        return { ok = true, pending = true }
    end,
    cancel_by_entindex = function() end,
}

local function ability()
    return {
        SetHidden = function() end,
        SetActivated = function() end,
    }
end

local function mine(entindex, level)
    local abilities = {
        ability_upgrade_gold_mine = ability(),
        ability_upgrade_gold_mine_efficiency = ability(),
        ability_upgrade_gold_mine_crit = ability(),
        ability_gold_mine_auto_upgrade = ability(),
        ability_gold_mine_stop_auto_upgrade = ability(),
    }
    local unit = {
        survival_player_id = 0,
        survival_building_id = "gold_mine",
        __building_level = level,
    }
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:entindex() return entindex end
    function unit:FindAbilityByName(name) return abilities[name] end
    function unit:SetBaseMaxHealth() end
    function unit:SetMaxHealth() end
    function unit:SetHealth() end
    function unit:SetPhysicalArmorBaseValue() end
    return unit
end

package.loaded["systems/gold_mine_system"] = nil
local system = require("systems/gold_mine_system")
system.init()

local low = mine(201, 1)
local high = mine(202, 2)
event_bus.emit(events.BUILDING_CREATED, {
    unit = low,
    player_id = 0,
    team = 2,
    building_id = "gold_mine",
    level = 1,
})
event_bus.emit(events.BUILDING_CREATED, {
    unit = high,
    player_id = 0,
    team = 2,
    building_id = "gold_mine",
    level = 2,
})

assert(handlers[events.GOLD_MINE_AUTO_UPGRADE_REQUEST]({
    entindex = 201,
    enabled = true,
}).ok)
assert(handlers[events.GOLD_MINE_AUTO_UPGRADE_REQUEST]({
    entindex = 202,
    enabled = true,
}).ok)

local low_step = assert(scheduled["gold_mine_auto_upgrade_201"])
local high_step = assert(scheduled["gold_mine_auto_upgrade_202"])
assert(low_step() == 1.1 and mine_upgrades == 1,
    "lowest auto mine did not independently finish its body upgrade")
assert(high_step() == 2.0 and technology_purchases == 0,
    "higher auto mine purchased shared technology before the coordinator")
assert(low_step() == 1.0 and technology_purchases == 1
    and technology.gold_mine_efficiency == 1,
    "lowest auto mine did not purchase exactly one shared technology level")
assert(high_step() == 2.0 and technology_purchases == 1,
    "higher auto mine duplicated the coordinator technology purchase")
assert(low_step() == 1.0 and technology_purchases == 2
    and technology.gold_mine_efficiency == 2,
    "coordinator technology state drifted from the authoritative event")

print("GOLD_MINE_AUTO_COORDINATOR_LUA51_PASS")
