modifier_endless_training_target = class({})

function modifier_endless_training_target:IsHidden() return true end
function modifier_endless_training_target:IsPurgable() return false end
function modifier_endless_training_target:RemoveOnDeath() return false end

function modifier_endless_training_target:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MIN_HEALTH,
        MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT,
    }
end

function modifier_endless_training_target:GetMinHealth()
    return 1
end

function modifier_endless_training_target:GetModifierConstantHealthRegen()
    return tonumber(self.health_regen) or 100000000
end

function modifier_endless_training_target:OnCreated(kv)
    self.health_regen = tonumber(kv.health_regen) or 100000000
end

function modifier_endless_training_target:OnRefresh(kv)
    self.health_regen = tonumber(kv.health_regen) or self.health_regen or 100000000
end