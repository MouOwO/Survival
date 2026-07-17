-- ============================================================================
-- ability_chop_wood: 伐木技能
-- ============================================================================
ability_chop_wood = class({})

function ability_chop_wood:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_NO_TARGET or DOTA_ABILITY_BEHAVIOR_PASSIVE
end

function ability_chop_wood:OnSpellStart()
    WorkerSystem.ChopWood({ caster = self:GetCaster() })
end
