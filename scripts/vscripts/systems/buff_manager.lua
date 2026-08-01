local definitions = require("config/generated/buff_definitions")

local M = {}
local BUFF_MODIFIER = "modifier_survival_managed_buff"
local AURA_MODIFIER = "modifier_survival_managed_aura"

local function valid(unit)
    return unit and not unit:IsNull()
end

local function definition(buff_id)
    local row = (definitions.by_id or {})[buff_id]
    return row and row.enabled ~= false and row or nil
end

local function managed_modifiers(target)
    if not valid(target) then return {} end
    return target:FindAllModifiersByName(BUFF_MODIFIER) or {}
end

local function find(target, buff_id)
    for _, modifier in ipairs(managed_modifiers(target)) do
        if not modifier:IsNull() and modifier.buff_id == buff_id then
            return modifier
        end
    end
    return nil
end

local function remove_lower_priority_exclusive(target, incoming)
    if not incoming.exclusive_group or incoming.exclusive_group == "" then
        return true
    end
    local incoming_priority = tonumber(incoming.priority) or 0
    for _, modifier in ipairs(managed_modifiers(target)) do
        local current = modifier.definition
        if current and current.exclusive_group == incoming.exclusive_group then
            local current_priority = tonumber(current.priority) or 0
            if current_priority > incoming_priority then return false end
            if current.buff_id ~= incoming.buff_id then modifier:Destroy() end
        end
    end
    return true
end

function M.get_definition(buff_id)
    return definition(buff_id)
end

function M.apply(caster, target, buff_id, options)
    if not IsServer() or not valid(target) then return nil end
    local def = definition(buff_id)
    if not def then return nil end

    options = options or {}
    if valid(caster) and not options.ignore_team then
        local same_team = caster:GetTeamNumber() == target:GetTeamNumber()
        if def.polarity == "negative" and same_team then return nil end
        if def.polarity == "positive" and not same_team then return nil end
    end
    if not remove_lower_priority_exclusive(target, def) then
        return nil
    end

    local duration = math.max(0, tonumber(options.duration) or 0)
    local value = tonumber(options.value) or tonumber(def.default_value) or 0
    local max_stacks = math.max(
        1, tonumber(options.max_stacks) or tonumber(def.max_stacks) or 1
    )
    local modifier = find(target, buff_id)
    if modifier and not modifier:IsNull() then
        if modifier.RefreshManaged then
            modifier:RefreshManaged(value, duration, max_stacks)
        else
            modifier:ApplyManaged(value, duration, max_stacks)
        end
        return modifier
    end

    modifier = target:AddNewModifier(caster or target, nil, BUFF_MODIFIER, {
        buff_id = buff_id,
        managed_value = value,
        managed_duration = duration,
        managed_max_stacks = max_stacks,
        duration = duration > 0 and duration or nil,
    })
    return modifier
end

function M.remove(target, buff_id)
    for _, modifier in ipairs(managed_modifiers(target)) do
        if not modifier:IsNull() and modifier.buff_id == buff_id then
            modifier:Destroy()
        end
    end
end

function M.has(target, buff_id)
    return find(target, buff_id) ~= nil
end

function M.apply_aura(caster, buff_id, radius)
    if not IsServer() or not valid(caster) or not definition(buff_id) then
        return nil
    end
    local modifier = caster:FindModifierByName(AURA_MODIFIER)
    if modifier and not modifier:IsNull() then
        modifier:Configure(buff_id, radius)
        return modifier
    end
    return caster:AddNewModifier(caster, nil, AURA_MODIFIER, {
        buff_id = buff_id,
        radius = radius,
    })
end

function M.remove_aura(caster, buff_id)
    if not valid(caster) then return end
    local modifier = caster:FindModifierByName(AURA_MODIFIER)
    if modifier and not modifier:IsNull()
        and (not buff_id or modifier.buff_id == buff_id) then
        modifier:Destroy()
    end
end

return M