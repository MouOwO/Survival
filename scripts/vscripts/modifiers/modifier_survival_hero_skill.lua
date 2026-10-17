local definitions = require("config/generated/hero_skill_definitions")

modifier_survival_hero_skill = class({})

local by_ability = {}
for _, row in ipairs(definitions.rows or {}) do
    local ability_name = row.ability_name
    -- Runtime passive-proc skills intentionally have no engine ability. They
    -- are handled by hero_passive_skill_service instead of this modifier.
    if row.enabled ~= false
        and type(ability_name) == "string"
        and ability_name ~= "" then
        by_ability[ability_name] = row
    end
end

local function modifier_value(self, effect_type)
    local ability = self:GetAbility()
    if not ability or ability:IsNull() then
        return 0
    end
    if ability.IsActivated and not ability:IsActivated() then
        return 0
    end
    local definition = by_ability[ability:GetAbilityName()]
    if not definition or definition.effect_type ~= effect_type then
        return 0
    end
    local per_level =
        tonumber(definition.effect_value_per_level) or 0
    return per_level * math.max(1, ability:GetLevel())
end

function modifier_survival_hero_skill:IsHidden()
    return true
end

function modifier_survival_hero_skill:IsPurgable()
    return false
end

function modifier_survival_hero_skill:RemoveOnDeath()
    return false
end

function modifier_survival_hero_skill:GetAttributes()
    return MODIFIER_ATTRIBUTE_MULTIPLE or 0
end

local function legacy_declarations()
    return {
        MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
        MODIFIER_PROPERTY_HEALTH_BONUS,
        MODIFIER_PROPERTY_STATS_STRENGTH_BONUS,
        MODIFIER_PROPERTY_STATS_AGILITY_BONUS,
        MODIFIER_PROPERTY_STATS_INTELLECT_BONUS,
        MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,
        MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
        MODIFIER_PROPERTY_MOVESPEED_BONUS_CONSTANT,
        MODIFIER_PROPERTY_ATTACK_RANGE_BONUS,
        MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT,
        MODIFIER_PROPERTY_MANA_REGEN_CONSTANT,
    }
end

local stat_properties = {
    pre_attack_damage = MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
    health_bonus = MODIFIER_PROPERTY_HEALTH_BONUS,
    strength_bonus = MODIFIER_PROPERTY_STATS_STRENGTH_BONUS,
    agility_bonus = MODIFIER_PROPERTY_STATS_AGILITY_BONUS,
    intellect_bonus = MODIFIER_PROPERTY_STATS_INTELLECT_BONUS,
    armor_bonus = MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,
    attack_speed_bonus = MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
    move_speed_bonus = MODIFIER_PROPERTY_MOVESPEED_BONUS_CONSTANT,
    attack_range_bonus = MODIFIER_PROPERTY_ATTACK_RANGE_BONUS,
    health_regen = MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT,
    mana_regen = MODIFIER_PROPERTY_MANA_REGEN_CONSTANT,
}
-- These effects run in the passive/exclusive services. None can contribute
-- through modifier_value's stat getters; unknown future effects stay legacy.
local scripted_effects = {
    passive_proc = true,
    monkey_king_q = true, monkey_king_w = true,
    monkey_king_e = true, monkey_king_r = true,
    blademaster_q = true, blademaster_w = true,
    blademaster_e = true, blademaster_r = true,
}

function modifier_survival_hero_skill:DeclareFunctions()
    -- Native declarations can precede OnCreated. Commit on this instance's
    -- first query, never on the shared class or according to activation/level.
    if self == modifier_survival_hero_skill or not self.GetParent then
        return legacy_declarations()
    end
    if self.survival_skill_declaration_decided then
        return self.survival_skill_native_declarations
    end
    local ok, declarations = pcall(function()
        if type(self.GetAbility) ~= "function" then return nil end
        local ability = self:GetAbility()
        if not ability or type(ability.IsNull) ~= "function" or ability:IsNull()
            or type(ability.GetAbilityName) ~= "function" then return nil end
        local definition = by_ability[ability:GetAbilityName()]
        if not definition or definition.enabled == false then return nil end
        local property = stat_properties[definition.effect_type]
        if property ~= nil then return { property } end
        if scripted_effects[definition.effect_type] then return {} end
        return nil
    end)
    self.survival_skill_native_declarations = ok and declarations
        or legacy_declarations()
    self.survival_skill_declaration_decided = true
    return self.survival_skill_native_declarations
end

function modifier_survival_hero_skill:GetModifierPreAttack_BonusDamage()
    return modifier_value(self, "pre_attack_damage")
end

function modifier_survival_hero_skill:GetModifierHealthBonus()
    return modifier_value(self, "health_bonus")
end


function modifier_survival_hero_skill:GetModifierBonusStats_Strength()
    return modifier_value(self, "strength_bonus")
end

function modifier_survival_hero_skill:GetModifierBonusStats_Agility()
    return modifier_value(self, "agility_bonus")
end

function modifier_survival_hero_skill:GetModifierBonusStats_Intellect()
    return modifier_value(self, "intellect_bonus")
end

function modifier_survival_hero_skill:GetModifierPhysicalArmorBonus()
    return modifier_value(self, "armor_bonus")
end

function modifier_survival_hero_skill:GetModifierAttackSpeedBonus_Constant()
    return modifier_value(self, "attack_speed_bonus")
end

function modifier_survival_hero_skill:GetModifierMoveSpeedBonus_Constant()
    return modifier_value(self, "move_speed_bonus")
end

function modifier_survival_hero_skill:GetModifierAttackRangeBonus()
    return modifier_value(self, "attack_range_bonus")
end

function modifier_survival_hero_skill:GetModifierConstantHealthRegen()
    return modifier_value(self, "health_regen")
end

function modifier_survival_hero_skill:GetModifierConstantManaRegen()
    return modifier_value(self, "mana_regen")
end

return modifier_survival_hero_skill
