local M = {}

local MOVE_ABILITY = "ability_building_blink"
local DESTROY_ABILITY = "ability_destroy_arrow_tower"
local MAX_VISIBLE_ABILITIES = 6

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function configured(row, ability_name)
    for _, name in ipairs(row and row.active_skill_ids or {}) do
        if name == ability_name then return true end
    end
    return false
end

local function remove_utility(unit)
    for _, ability_name in ipairs({ MOVE_ABILITY, DESTROY_ABILITY }) do
        if unit:FindAbilityByName(ability_name) then
            unit:RemoveAbility(ability_name)
        end
    end
end

function M.clear(unit)
    if valid_entity(unit) then remove_utility(unit) end
end

local function visible_non_utility_count(unit)
    local count = 0
    for index = 0, 23 do
        local ability = unit:GetAbilityByIndex(index)
        if ability and not ability:IsNull() then
            local name = ability:GetAbilityName()
            if name ~= MOVE_ABILITY and name ~= DESTROY_ABILITY
                and not ability:IsHidden() then
                count = count + 1
            end
        end
    end
    return count
end

local function add_utility(unit, ability_name, hidden)
    local ability = unit:AddAbility(ability_name)
    if not ability then return nil end
    ability:SetLevel(1)
    ability:SetActivated(not hidden)
    ability:SetHidden(hidden)
    return ability
end

function M.sync(state, row)
    local unit = state and state.unit
    if not valid_entity(unit) or state.building_id ~= "arrow_tower" then return end

    -- tower_ability_sync has already removed utility abilities before adding
    -- route abilities. Keep this second clear for direct callers and make the
    -- final append order explicit: movement first (D), destruction last.
    M.clear(unit)
    local free_slots = math.max(0, MAX_VISIBLE_ABILITIES - visible_non_utility_count(unit))
    local show_destroy = configured(row, DESTROY_ABILITY) and free_slots >= 1
    local show_move = configured(row, MOVE_ABILITY) and free_slots >= 2

    if configured(row, MOVE_ABILITY) then
        add_utility(unit, MOVE_ABILITY, not show_move)
    end
    if configured(row, DESTROY_ABILITY) then
        add_utility(unit, DESTROY_ABILITY, not show_destroy)
    end
end

M.MOVE_ABILITY = MOVE_ABILITY
M.DESTROY_ABILITY = DESTROY_ABILITY

return M