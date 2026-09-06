local M = {}
local NAME = "modifier_survival_hero_base_health"
local bound = false
local retry_at = setmetatable({}, {__mode="k"})

function M.apply(unit, bonus)
    local modifier = unit.FindModifierByName and unit:FindModifierByName(NAME)
    if modifier then
        if modifier.SetHealthBonus then modifier:SetHealthBonus(bonus)
        else modifier:SetStackCount(bonus) end
        retry_at[unit] = nil
        return modifier
    end
    local now = GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
    if retry_at[unit] and now < retry_at[unit] then return nil end
    if not bound and type(LinkLuaModifier) == "function" then
        require("modifiers/modifier_survival_hero_base_health")
        LinkLuaModifier(NAME, "modifier_bindings/" .. NAME, LUA_MODIFIER_MOTION_NONE)
        bound = true
    end
    modifier = unit:AddNewModifier(unit, nil, NAME, {health_bonus=bonus})
    if not modifier then
        -- A broken engine binding must not produce ten errors per second.
        retry_at[unit] = now + 5
        bound = false
        return nil
    end
    retry_at[unit] = nil
    return modifier
end
return M
