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
        / math.max(1, tonumber(self:GetParent().survival_endless_attack_scale) or 1)
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
local function choose_corrosive_declaration(self)
    if self.corrosive_event_decl_sampled == true then return end
    self.corrosive_event_decl_sampled = true
    self.shared_corrosive_shield_observer = false
    if _G.SURVIVAL_SHARED_CORROSIVE_SHIELD_PROBE ~= true then return end
    local observer = require("systems/tower_damage_observer")
    if type(observer.choose_corrosive_shield) ~= "function"
        or type(observer.register_corrosive_shield) ~= "function" then return end
    local ok, world = pcall(function() return observer.choose_corrosive_shield(self:GetParent()) end)
    if not ok or not world then return end
    self.shared_corrosive_shield_observer = true
    self.corrosive_shield_declared_world = world
end
function modifier_rogue_corrosive_shield_attack:OnCreated(params)
    choose_corrosive_declaration(self)
    self.seen_records = {}
    self:OnRefresh(params)
    if self.shared_corrosive_shield_observer == true then
        self.corrosive_shield_registration_failed =
            not require("systems/tower_damage_observer").register_corrosive_shield(
                self:GetParent(), self, self.corrosive_shield_declared_world)
    end
end
function modifier_rogue_corrosive_shield_attack:OnRefresh(params)
    -- A refreshed legacy/native-cached instance cannot opt into a new route.
    if not self.corrosive_event_decl_sampled then
        self.corrosive_event_decl_sampled = true
        self.shared_corrosive_shield_observer = false
    end
    self.armor_reduction_per_attack = tonumber(params and params.armor_reduction_per_attack)
        or require("config/armor_balance").from_war3_linear(1)
end
function modifier_rogue_corrosive_shield_attack:DeclareFunctions()
    if self ~= modifier_rogue_corrosive_shield_attack and self.GetParent then
        choose_corrosive_declaration(self)
        if self.shared_corrosive_shield_observer == true then return {} end
    end
    return { MODIFIER_EVENT_ON_ATTACK }
end
function modifier_rogue_corrosive_shield_attack:OnAttack(params)
    if self.shared_corrosive_shield_observer == true then return end
    return self:HandleAttack(params)
end
function modifier_rogue_corrosive_shield_attack:HandleAttack(params)
    if not IsServer() or not params or params.attacker ~= self:GetParent() then return end
    local target = params.target
    if not target or target:IsNull() or target:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then return end
    if target.survival_player_id == nil then return end
    local record = tonumber(params.record)
    local registration = self.corrosive_shield_registration
    local counters = registration and registration.state.counters
    if record and self.seen_records[record] then
        if counters then counters.duplicate_records = counters.duplicate_records + 1 end
        return
    end
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
                if counters then counters.armor_reduction_calls = counters.armor_reduction_calls + 1 end
                armor:AddArmorReduction(self.armor_reduction_per_attack, record, "corrosive_shield")
            end
            break
        end
    end
end

function modifier_rogue_corrosive_shield_attack:OnDestroy()
    if not IsServer() then return end
    self.corrosive_shield_destroyed = true
    if self.corrosive_shield_registration then
        require("systems/tower_damage_observer").unregister_corrosive_shield(self)
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
