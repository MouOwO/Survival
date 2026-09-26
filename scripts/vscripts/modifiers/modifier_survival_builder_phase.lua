modifier_survival_builder_phase = class({})
_G.modifier_survival_builder_phase = modifier_survival_builder_phase
local M = modifier_survival_builder_phase
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end
function M:CheckState()
    -- Phase through dynamic unit hulls (including buildings and wall proxies),
    -- while native ground pathing still respects cliffs and map navigation.
    return { [MODIFIER_STATE_NO_UNIT_COLLISION] = true }
end
return M