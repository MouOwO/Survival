local global_rules = require("config/global_rules")
local armor_balance = require("config/armor_balance")

local M = {}
local enabled = false

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

function M.apply(state)
    if not enabled or not state or state.building_id ~= "wall"
        or not valid_entity(state.unit) then return false end
    local health = tonumber(global_rules.dev_wall_health)
    local war3_armor = tonumber(global_rules.dev_wall_war3_armor)
    if not health or health <= 0 or not war3_armor then return false end
    local runtime_armor = armor_balance.from_war3(war3_armor)
    state.unit:SetBaseMaxHealth(health)
    state.unit:SetMaxHealth(health)
    state.unit:SetHealth(health)
    state.unit:SetPhysicalArmorBaseValue(runtime_armor)
    state.unit.survival_armor = runtime_armor
    state.unit.survival_war3_armor = war3_armor
    return true
end

function M.enable(buildings)
    enabled = true
    local applied = 0
    for _, state in pairs(buildings or {}) do
        if M.apply(state) then applied = applied + 1 end
    end
    return true, applied
end

function M.reset()
    enabled = false
end

return M