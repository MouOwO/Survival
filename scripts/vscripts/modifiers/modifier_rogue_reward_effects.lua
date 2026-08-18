modifier_rogue_enemy_attack_speed = class({})

function modifier_rogue_enemy_attack_speed:IsHidden() return false end
function modifier_rogue_enemy_attack_speed:IsPurgable() return false end
function modifier_rogue_enemy_attack_speed:RemoveOnDeath() return true end
function modifier_rogue_enemy_attack_speed:OnCreated(params)
    self.value = tonumber(params and params.value) or -15
end
function modifier_rogue_enemy_attack_speed:OnRefresh(params)
    self:OnCreated(params)
end
function modifier_rogue_enemy_attack_speed:DeclareFunctions()
    return { MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE }
end
function modifier_rogue_enemy_attack_speed:GetModifierAttackSpeedPercentage()
    return self.value
end

modifier_rogue_base_tower_attack = class({})

function modifier_rogue_base_tower_attack:IsHidden() return false end
function modifier_rogue_base_tower_attack:IsPurgable() return false end
function modifier_rogue_base_tower_attack:RemoveOnDeath() return true end
function modifier_rogue_base_tower_attack:OnCreated(params)
    self.value = tonumber(params and params.value) or 100
end
function modifier_rogue_base_tower_attack:OnRefresh(params)
    self:OnCreated(params)
end
function modifier_rogue_base_tower_attack:DeclareFunctions()
    return { MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE }
end
function modifier_rogue_base_tower_attack:GetModifierBaseDamageOutgoing_Percentage()
    return self.value
end

modifier_rogue_tower_attack_projection = class({})
function modifier_rogue_tower_attack_projection:IsHidden() return true end
function modifier_rogue_tower_attack_projection:IsPurgable() return false end
function modifier_rogue_tower_attack_projection:RemoveOnDeath() return true end
function modifier_rogue_tower_attack_projection:OnCreated(params)
    self.value = tonumber(params and params.value) or 0
end
function modifier_rogue_tower_attack_projection:OnRefresh(params)
    self:OnCreated(params)
end
function modifier_rogue_tower_attack_projection:DeclareFunctions()
    return { MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE }
end
function modifier_rogue_tower_attack_projection:GetModifierBaseDamageOutgoing_Percentage()
    return self.value
end

modifier_rogue_weakening_attack = class({})
function modifier_rogue_weakening_attack:IsHidden() return false end
function modifier_rogue_weakening_attack:IsPurgable() return false end
function modifier_rogue_weakening_attack:RemoveOnDeath() return true end
function modifier_rogue_weakening_attack:OnCreated(params)
    self.value = tonumber(params and params.value) or -50
end
function modifier_rogue_weakening_attack:DeclareFunctions()
    return { MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE }
end
function modifier_rogue_weakening_attack:GetModifierBaseDamageOutgoing_Percentage()
    return self.value
end

modifier_rogue_tower_growth = class({})
function modifier_rogue_tower_growth:IsHidden() return false end
function modifier_rogue_tower_growth:IsPurgable() return false end
function modifier_rogue_tower_growth:RemoveOnDeath() return true end
function modifier_rogue_tower_growth:OnCreated(params)
    self:SetStackCount(math.max(0, math.floor(tonumber(params and params.stacks) or 0)))
    self.value = tonumber(params and params.value) or 10
end
function modifier_rogue_tower_growth:OnRefresh(params)
    self.value = tonumber(params and params.value) or self.value or 10
    self:SetStackCount(self:GetStackCount() + 1)
end
function modifier_rogue_tower_growth:DeclareFunctions()
    return { MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE }
end
function modifier_rogue_tower_growth:GetModifierBaseDamageOutgoing_Percentage()
    return (self.value or 10) * self:GetStackCount()
end

modifier_rogue_sharp_volley_growth = class({})
function modifier_rogue_sharp_volley_growth:IsHidden() return false end
function modifier_rogue_sharp_volley_growth:IsPurgable() return false end
function modifier_rogue_sharp_volley_growth:RemoveOnDeath() return true end
function modifier_rogue_sharp_volley_growth:OnCreated(params)
    self:SetStackCount(math.max(0, tonumber(params and params.value) or 0))
end
function modifier_rogue_sharp_volley_growth:AddGrowth(value)
    self:SetStackCount(self:GetStackCount() + math.max(0, tonumber(value) or 0))
end
function modifier_rogue_sharp_volley_growth:DeclareFunctions()
    return { MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE }
end
function modifier_rogue_sharp_volley_growth:GetModifierPreAttack_BonusDamage()
    return self:GetStackCount()
end

modifier_rogue_lumberjack_attack_speed = class({})
function modifier_rogue_lumberjack_attack_speed:IsHidden() return false end
function modifier_rogue_lumberjack_attack_speed:IsPurgable() return false end
function modifier_rogue_lumberjack_attack_speed:RemoveOnDeath() return true end
function modifier_rogue_lumberjack_attack_speed:OnCreated(params)
    self.value = tonumber(params and params.value) or 100
end
function modifier_rogue_lumberjack_attack_speed:OnRefresh(params) self:OnCreated(params) end
function modifier_rogue_lumberjack_attack_speed:DeclareFunctions()
    return { MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE }
end
function modifier_rogue_lumberjack_attack_speed:GetModifierAttackSpeedPercentage()
    return self.value
end

modifier_rogue_corrosive_shield_attack = class({})

function modifier_rogue_corrosive_shield_attack:IsHidden() return true end
function modifier_rogue_corrosive_shield_attack:IsPurgable() return false end
function modifier_rogue_corrosive_shield_attack:RemoveOnDeath() return true end
function modifier_rogue_corrosive_shield_attack:OnCreated()
    self.seen_records = {}
end
function modifier_rogue_corrosive_shield_attack:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK }
end
function modifier_rogue_corrosive_shield_attack:OnAttack(params)
    if not IsServer() or not params or params.attacker ~= self:GetParent() then return end
    local target = params.target
    if not target or target:IsNull() or target:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then return end
    if target.survival_player_id == nil then return end
    local record = tonumber(params.record)
    if record and self.seen_records[record] then return end
    if record then self.seen_records[record] = true end
    local player_context = require("systems/player_context_service")
    local effect_state = require("systems/rogue_effect_state_service")
    for _, player_id in ipairs(player_context.active_player_ids()) do
        if effect_state.has_effect(player_id, "owned_target_attacker_armor_reduction")
            and player_context.is_owned_by(player_id, target) then
            local armor = self:GetParent():FindModifierByName("modifier_research_armor_reduction")
            if not armor then
                armor = self:GetParent():AddNewModifier(self:GetParent(), nil,
                    "modifier_research_armor_reduction", {})
            end
            if armor and armor.AddArmorReduction then
                armor:AddArmorReduction(1, record, "corrosive_shield")
            end
            break
        end
    end
end

return {
    enemy_attack_speed = modifier_rogue_enemy_attack_speed,
    base_tower_attack = modifier_rogue_base_tower_attack,
    weakening_attack = modifier_rogue_weakening_attack,
    tower_growth = modifier_rogue_tower_growth,
    sharp_volley_growth = modifier_rogue_sharp_volley_growth,
    lumberjack_attack_speed = modifier_rogue_lumberjack_attack_speed,
}