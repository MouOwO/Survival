local effect_state = require("systems/rogue_effect_state_service")
local hero_attack_projection = require("combat/rogue_hero_attack_projection")

modifier_rogue_combat_bonus = class({})

-- Explicit Tools candidate, sampled once at native instance creation. Default
-- production behavior is unchanged. Never toggle an existing engine-cached
-- event declaration through ForceRefresh or a changed global probe flag.
local function sample_damage_declaration(self, created)
    if self.survival_rogue_damage_decl_sampled == true then return end
    self.survival_rogue_damage_decl_sampled = true
    self.survival_rogue_damage_decl_omitted = false
    self.survival_rogue_damage_decl_reason = created
        and "probe_disabled_at_creation" or "declaration_before_creation_or_legacy_instance"
    if not created then return end
    local probe = _G.SURVIVAL_ROGUE_COMBAT_DAMAGE_DECL_PROBE
    if type(probe) ~= "table" or probe.enabled ~= true then return end
    if not IsServer or not IsServer() then
        self.survival_rogue_damage_decl_reason = "client_legacy"
        return
    end
    if not IsInToolsMode or not IsInToolsMode() then
        self.survival_rogue_damage_decl_reason = "non_tools_legacy"
        return
    end
    local ok, eligible, reason = pcall(function()
        local mode = GameRules:GetGameModeEntity()
        local guard = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
        if probe.mode ~= mode or not guard or probe.guard ~= guard or guard.mode ~= mode then
            return false, "probe_world_or_guard_mismatch"
        end
        local parent = self:GetParent()
        if not parent or parent:IsNull() or parent:IsRealHero() ~= false
            or parent:GetClassname() ~= "npc_dota_creature" then
            return false, "hero_or_unknown_native_role"
        end
        local id = tonumber(self.player_id)
        if not id or id < 0 or id ~= math.floor(id)
            or parent.survival_building_id ~= "arrow_tower"
            or tonumber(parent.survival_player_id) ~= id then
            return false, "not_formal_owned_arrow_tower"
        end
        local native_id = parent:GetPlayerOwnerID()
        if native_id ~= id and native_id ~= -1 then return false, "native_owner_mismatch" end
        local bus, events = require("core/event_bus"), require("core/events")
        local state = bus.request(events.BUILDING_QUERY_REQUEST,
            {entindex = parent:entindex(), read_only = true})
        if not state or state.unit ~= parent or state.building_id ~= "arrow_tower"
            or tonumber(state.player_id) ~= id
            or not require("systems/player_context_service").is_owned_by(id, parent) then
            return false, "formal_registration_or_context_mismatch"
        end
        return true, "tools_formal_nonhero_arrow_tower"
    end)
    self.survival_rogue_damage_decl_reason = ok and reason or "role_or_registration_exception"
    self.survival_rogue_damage_decl_omitted = ok and eligible == true
end

function modifier_rogue_combat_bonus:IsHidden() return true end
function modifier_rogue_combat_bonus:IsPurgable() return false end
function modifier_rogue_combat_bonus:RemoveOnDeath() return false end
function modifier_rogue_combat_bonus:OnCreated(kv)
    self.player_id = tonumber(kv and kv.player_id)
    sample_damage_declaration(self, true)
end
function modifier_rogue_combat_bonus:DeclareFunctions()
    -- Class-level diagnostic calls are not native instances. A declaration
    -- before OnCreated, including an old instance after reload, locks legacy.
    if self.GetParent and self.survival_rogue_damage_decl_sampled ~= true then
        sample_damage_declaration(self, false)
    end
    local functions = {
        MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
    }
    if self.survival_rogue_damage_decl_omitted ~= true then
        functions[#functions + 1] = MODIFIER_EVENT_ON_TAKEDAMAGE
    end
    return functions
end
function modifier_rogue_combat_bonus:GetModifierBaseDamageOutgoing_Percentage()
    return effect_state.numeric(self.player_id, "unit_attack_bonus_pct")
end
function modifier_rogue_combat_bonus:GetModifierPreAttack_BonusDamage()
    local parent = self:GetParent()
    if parent.survival_building_id ~= "arrow_tower" then return 0 end
    local pct = effect_state.numeric(self.player_id,
        "tower_hero_attack_projection_pct")
    return hero_attack_projection.calculate(self.player_id, pct)
        / math.max(1, tonumber(parent.survival_endless_attack_scale) or 1)
end
function modifier_rogue_combat_bonus:OnTakeDamage(params)
    if not IsServer() or params.attacker ~= self:GetParent()
        or not params.unit or params.unit:GetTeamNumber() == params.attacker:GetTeamNumber()
        or params.damage_category ~= DOTA_DAMAGE_CATEGORY_ATTACK then return end
    local pct = effect_state.numeric(self.player_id, "hero_lifesteal_pct")
    if pct > 0 and params.attacker.IsRealHero and params.attacker:IsRealHero() then
        local amount = require("combat/lifesteal_amount").calculate(
            params.attacker, params.unit, params.damage, pct)
        if amount > 0 then
            require("core/hero_health_guard").allow_healing(params.attacker)
            params.attacker:Heal(amount, nil)
        end
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
    return (tonumber(self.value) or 0)
        / math.max(1, tonumber(self:GetParent().survival_endless_attack_scale) or 1)
end
