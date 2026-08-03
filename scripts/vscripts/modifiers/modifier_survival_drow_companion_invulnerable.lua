modifier_survival_drow_companion_invulnerable = class({})

function modifier_survival_drow_companion_invulnerable:IsHidden() return true end
function modifier_survival_drow_companion_invulnerable:IsPurgable() return false end
function modifier_survival_drow_companion_invulnerable:RemoveOnDeath() return false end

function modifier_survival_drow_companion_invulnerable:CheckState()
    return {
        [MODIFIER_STATE_INVULNERABLE] = true,
        [MODIFIER_STATE_NO_HEALTH_BAR] = false,
    }
end

return modifier_survival_drow_companion_invulnerable