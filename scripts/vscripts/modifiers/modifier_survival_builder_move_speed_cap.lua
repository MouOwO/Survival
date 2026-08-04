modifier_survival_builder_move_speed_cap = class({})
_G.modifier_survival_builder_move_speed_cap = modifier_survival_builder_move_speed_cap

local DEFAULT_MOVE_SPEED_CAP = 600

function modifier_survival_builder_move_speed_cap:IsHidden()
    return true
end

function modifier_survival_builder_move_speed_cap:IsPurgable()
    return false
end

function modifier_survival_builder_move_speed_cap:RemoveOnDeath()
    return false
end

function modifier_survival_builder_move_speed_cap:OnCreated(params)
    self.move_speed_cap = tonumber(params and params.move_speed_cap)
        or DEFAULT_MOVE_SPEED_CAP
end

function modifier_survival_builder_move_speed_cap:OnRefresh(params)
    self:OnCreated(params)
end

function modifier_survival_builder_move_speed_cap:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MOVESPEED_MAX,
        MODIFIER_PROPERTY_MOVESPEED_LIMIT,
    }
end

function modifier_survival_builder_move_speed_cap:GetModifierMoveSpeed_Max()
    return self.move_speed_cap or DEFAULT_MOVE_SPEED_CAP
end

function modifier_survival_builder_move_speed_cap:GetModifierMoveSpeed_Limit()
    return self.move_speed_cap or DEFAULT_MOVE_SPEED_CAP
end

return modifier_survival_builder_move_speed_cap