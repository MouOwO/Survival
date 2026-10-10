local MODIFIER = "modifier_tower_fixed_facing"
if LinkLuaModifier then
    LinkLuaModifier(MODIFIER, "modifiers/modifier_tower_fixed_facing", LUA_MODIFIER_MOTION_NONE)
end

local M = {}

function M.apply(unit, tower_class)
    if not unit or unit:IsNull() then return false end
    if tower_class == nil then tower_class = unit.survival_tower_class end
    local fixed = unit:GetUnitName() == "building_arrow_tower"
        and tostring(tower_class or "") == "" and not unit.survival_ultimate_tower
    local installed = unit:HasModifier(MODIFIER)
    if fixed and not installed then
        unit:AddNewModifier(unit, nil, MODIFIER, {})
    elseif not fixed and installed then
        unit:RemoveModifierByName(MODIFIER)
    end
    return fixed
end

return M
