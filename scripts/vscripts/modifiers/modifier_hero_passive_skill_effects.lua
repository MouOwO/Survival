modifier_hero_passive_skill_effect = class({})

function modifier_hero_passive_skill_effect:IsHidden() return false end
function modifier_hero_passive_skill_effect:IsDebuff() return true end
function modifier_hero_passive_skill_effect:IsPurgable() return true end
function modifier_hero_passive_skill_effect:RemoveOnDeath() return true end
function modifier_hero_passive_skill_effect:GetAttributes()
    return MODIFIER_ATTRIBUTE_MULTIPLE or 0
end

function modifier_hero_passive_skill_effect:OnCreated(params)
    self:Configure(params)
end

function modifier_hero_passive_skill_effect:OnRefresh(params)
    self:Configure(params)
end

function modifier_hero_passive_skill_effect:Configure(params)
    params = params or {}
    self.effect_type = tostring(params.effect_type or self.effect_type or "")
    self.effect_value = tonumber(params.effect_value) or self.effect_value or 0
    self.source_skill_id = tostring(params.source_skill_id or self.source_skill_id or "")
end

function modifier_hero_passive_skill_effect:GetTexture()
    if self.effect_type == "skill_vulnerability" then return "skywrath_mage_ancient_seal" end
    if self.effect_type == "attack_slow" then return "crystal_maiden_frostbite" end
    return "crystal_maiden_crystal_nova"
end

function modifier_hero_passive_skill_effect:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE,
        MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE,
    }
end

function modifier_hero_passive_skill_effect:GetModifierMoveSpeedBonus_Percentage()
    return self.effect_type == "move_slow" and -math.abs(self.effect_value) or 0
end

function modifier_hero_passive_skill_effect:GetModifierAttackSpeedPercentage()
    return self.effect_type == "attack_slow" and -math.abs(self.effect_value) or 0
end

_G.modifier_hero_passive_skill_effect = modifier_hero_passive_skill_effect
return modifier_hero_passive_skill_effect