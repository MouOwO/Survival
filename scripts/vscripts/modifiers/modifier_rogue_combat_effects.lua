local event_bus = require("core/event_bus")
local events = require("core/events")
local effect_state = require("systems/rogue_effect_state_service")

modifier_rogue_combat_bonus = class({})

function modifier_rogue_combat_bonus:IsHidden() return true end
function modifier_rogue_combat_bonus:IsPurgable() return false end
function modifier_rogue_combat_bonus:RemoveOnDeath() return false end
function modifier_rogue_combat_bonus:OnCreated(kv)
    self.player_id = tonumber(kv and kv.player_id)
end
function modifier_rogue_combat_bonus:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
    }
end
function modifier_rogue_combat_bonus:GetModifierBaseDamageOutgoing_Percentage()
    return effect_state.numeric(self.player_id, "unit_attack_bonus_pct")
end
function modifier_rogue_combat_bonus:GetModifierPreAttack_BonusDamage()
    local parent = self:GetParent()
    if parent.survival_building_id ~= "arrow_tower" then return 0 end
    local pct = effect_state.numeric(self.player_id,
        "tower_hero_attack_projection_pct")
    if pct <= 0 then return 0 end
    local result = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
        player_id = self.player_id,
    }) or {}
    return (tonumber(result.snapshot and result.snapshot.attack_total) or 0)
        * pct / 100
end
function modifier_rogue_combat_bonus:OnTakeDamage(params)
    if not IsServer() or params.attacker ~= self:GetParent()
        or not params.unit or params.unit:GetTeamNumber() == params.attacker:GetTeamNumber()
        or params.damage_category ~= DOTA_DAMAGE_CATEGORY_ATTACK then return end
    local pct = effect_state.numeric(self.player_id, "hero_lifesteal_pct")
    if pct > 0 and params.attacker.IsRealHero and params.attacker:IsRealHero() then
        params.attacker:Heal(math.max(0, tonumber(params.damage) or 0) * pct / 100, nil)
    end
end

modifier_rogue_training_dummy = class({})
function modifier_rogue_training_dummy:IsHidden() return true end
function modifier_rogue_training_dummy:IsPurgable() return false end
function modifier_rogue_training_dummy:CheckState()
    return { [MODIFIER_STATE_MAGIC_IMMUNE] = true }
end
function modifier_rogue_training_dummy:OnCreated(kv)
    self.value = tonumber(kv and kv.value) or 100
end
function modifier_rogue_training_dummy:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_LANDED, MODIFIER_PROPERTY_MIN_HEALTH }
end
function modifier_rogue_training_dummy:GetMinHealth() return 1 end
function modifier_rogue_training_dummy:OnAttackLanded(params)
    if not IsServer() or params.target ~= self:GetParent() then return end
    local attacker = params.attacker
    if not attacker or attacker:IsNull() then return end
    local player_context = require("systems/player_context_service")
    if not player_context.is_owned_by(
        self:GetParent().survival_player_id, attacker
    ) then return end
    attacker.survival_rogue_dummy_attack_bonus =
        (tonumber(attacker.survival_rogue_dummy_attack_bonus) or 0) + self.value
    attacker:AddNewModifier(attacker, nil, "modifier_rogue_training_attack", {
        value = attacker.survival_rogue_dummy_attack_bonus,
    })
end
function modifier_rogue_training_dummy:OnDestroy()
    if IsServer() and self:GetParent() and not self:GetParent():IsNull() then
        UTIL_Remove(self:GetParent())
    end
end

modifier_rogue_training_attack = class({})
function modifier_rogue_training_attack:IsHidden() return false end
function modifier_rogue_training_attack:IsPurgable() return false end
function modifier_rogue_training_attack:RemoveOnDeath() return false end
function modifier_rogue_training_attack:OnCreated(kv)
    self.value = tonumber(kv and kv.value) or 0
end
function modifier_rogue_training_attack:OnRefresh(kv) self:OnCreated(kv) end
function modifier_rogue_training_attack:DeclareFunctions()
    return { MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE }
end
function modifier_rogue_training_attack:GetModifierPreAttack_BonusDamage()
    return self.value
end