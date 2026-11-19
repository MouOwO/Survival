-- Fused workers keep their ordinary BAT and express the final interval as IAS.
-- The engine then scales windup and the original attack animation together.
local M = { NAME = "modifier_lumberjack_native_cadence" }
local function valid(unit) return unit and not unit:IsNull() end
local function current(modifier, unit)
    return modifier and (not modifier.IsNull or not modifier:IsNull())
        and (not modifier.GetParent or modifier:GetParent() == unit)
end
function M.ensure(unit)
    if not valid(unit) then return nil end
    local modifier = unit:FindModifierByName(M.NAME)
    if current(modifier, unit) then return modifier end
    return unit:AddNewModifier(unit, nil, M.NAME, {})
end
function M.apply(state, reference_interval, final_interval)
    local unit = state.unit
    local modifier = state.native_cadence_modifier
    if not current(modifier, unit) then
        modifier = M.ensure(unit)
        state.native_cadence_modifier = modifier
    end
    assert(modifier and type(modifier.SetCadence) == "function", "fused_native_cadence_unavailable")
    modifier:SetCadence(reference_interval, final_interval)
    return reference_interval
end
-- Both existing native percentage sources notify only on real changes. There
-- is no modifier census in the getter, attack callback or periodic refresh.
function M.percentage_changed(unit, source, value)
    if not valid(unit) or unit.survival_super_lumberjack ~= true then return end
    local modifier = unit:FindModifierByName(M.NAME)
    if current(modifier, unit) and modifier.SetPercentageSource then
        modifier:SetPercentageSource(source, value)
    end
end
return M
