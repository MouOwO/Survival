local event_bus = require("core/event_bus")
local events = require("core/events")
local sound_service = require("core/sound_service")

modifier_lumberjack_ai = class({})
local M = modifier_lumberjack_ai
local IDLE_RESUME_DELAY = 3
local THINK_INTERVAL = 0.25

local function game_time()
    if GameRules and GameRules.GetGameTime then return GameRules:GetGameTime() end
    return 0
end

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    if not IsServer() then return end
    self.tree_entindex = tonumber(params.tree_entindex) or -1
    self.base_lumber_efficiency = tonumber(params.base_lumber_efficiency) or 1
    self.tree_lumber_efficiency_buff = tonumber(
        params.tree_lumber_efficiency_buff
    ) or 0
    self.technology_lumber_efficiency = tonumber(
        params.technology_lumber_efficiency
    ) or 0
    self.player_id = tonumber(params.player_id) or -1
    self.fusion_count = math.max(1, tonumber(params.fusion_count) or 1)
    self.wood_multiplier_chance_pct = math.max(
        0, tonumber(params.wood_multiplier_chance_pct) or 0
    )
    self.gold_per_hit_flat = math.max(0, tonumber(params.gold_per_hit_flat) or 0)
    self.tree_damage_chance_pct = math.max(
        0, tonumber(params.tree_damage_chance_pct) or 0
    )
    self.personality_attack_growth_per_hit = math.max(
        0, tonumber(params.personality_attack_growth_per_hit) or 0
    )
    self.technology_crit_chance = math.max(
        0, tonumber(params.technology_crit_chance) or 0
    )
    self.technology_armor_reduction = math.max(
        0, tonumber(params.technology_armor_reduction) or 0
    )
    self.attack_gain_per_attack = math.max(
        0, tonumber(params.attack_gain_per_attack) or 0
    )
    self.lumber_efficiency = self.base_lumber_efficiency
        + self.tree_lumber_efficiency_buff
        + self.technology_lumber_efficiency
    self.manual_control = false
    self.manual_idle_since = nil
    self:StartIntervalThink(THINK_INTERVAL)
end

function M:OnPlayerOrder(order_type, target)
    if not IsServer() then return end
    if tonumber(order_type) == tonumber(DOTA_UNIT_ORDER_ATTACK_TARGET)
        and target and not target:IsNull()
        and target:entindex() == self.tree_entindex then
        self.manual_control = false
        self.manual_idle_since = nil
        return
    end
    self.manual_control = true
    self.manual_idle_since = nil
end

function M:SetTreeEntIndex(entindex)
    self.tree_entindex = tonumber(entindex) or -1
end

function M:SetTreeLumberEfficiency(buff)
    self.tree_lumber_efficiency_buff = math.max(0, tonumber(buff) or 0)
    self.lumber_efficiency = self.base_lumber_efficiency
        + self.tree_lumber_efficiency_buff
        + self.technology_lumber_efficiency
end

function M:SetBaseLumberEfficiency(value)
    self.base_lumber_efficiency = math.max(0, tonumber(value) or 0)
    self.lumber_efficiency = self.base_lumber_efficiency
        + self.tree_lumber_efficiency_buff
        + self.technology_lumber_efficiency
end

function M:SetTechnologyLumberEfficiency(value)
    self.technology_lumber_efficiency = math.max(0, tonumber(value) or 0)
    self.lumber_efficiency = self.base_lumber_efficiency
        + self.tree_lumber_efficiency_buff
        + self.technology_lumber_efficiency
end
function M:SetTechnologyCritChance(value)
    self.technology_crit_chance = math.max(0, tonumber(value) or 0)
end

function M:SetTechnologyArmorReduction(value)
    self.technology_armor_reduction = math.max(0, tonumber(value) or 0)
end

function M:SetAttackGainPerAttack(value)
    self.attack_gain_per_attack = math.max(0, tonumber(value) or 0)
end

function M:GetLumberEfficiency()
    return self.lumber_efficiency or self.base_lumber_efficiency or 1
end

local function is_idle(unit)
    if not unit.IsIdle then return false end
    local ok, idle = pcall(unit.IsIdle, unit)
    return ok and idle == true
end

local function issue_tree_attack(unit, tree)
    unit.survival_lumberjack_internal_order = true
    ExecuteOrderFromTable({
        UnitIndex = unit:entindex(),
        OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
        TargetIndex = tree:entindex(),
        Queue = false,
    })
    unit.survival_lumberjack_internal_order = nil
end

function M:OnIntervalThink()
    if not IsServer() then return end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end
    if self.tree_entindex < 0 then return end

    local tree = EntIndexToHScript(self.tree_entindex)
    if not tree or tree:IsNull() or not tree:IsAlive() then return end
    if parent.CanEntityBeSeenByMyTeam
        and not parent:CanEntityBeSeenByMyTeam(tree) then
        return
    end
    if parent:GetAttackTarget() == tree then
        self.manual_control = false
        self.manual_idle_since = nil
        return
    end
    if self.manual_control then
        if not is_idle(parent) then
            self.manual_idle_since = nil
            return
        end
        local now = game_time()
        self.manual_idle_since = self.manual_idle_since or now
        if now - self.manual_idle_since < IDLE_RESUME_DELAY then return end
        self.manual_control = false
        self.manual_idle_since = nil
    end
    issue_tree_attack(parent, tree)
end

function M:DeclareFunctions()
    return {
        MODIFIER_EVENT_ON_ATTACK_LANDED,
    }
end

function M:OnAttackLanded(keys)
    if not IsServer() then return end
    local parent = self:GetParent()
    if keys.attacker ~= parent then return end
    local target = keys.target
    if not target or target:IsNull() then return end
    if target:entindex() ~= self.tree_entindex then return end
    self.manual_control = false
    self.manual_idle_since = nil
    if self.tree_damage_chance_pct > 0
        and RandomFloat(0, 100) < self.tree_damage_chance_pct then
        local health = target:GetHealth()
        local amount = math.max(1, math.floor(target:GetMaxHealth() * 0.01))
        if health > 1 then target:SetHealth(math.max(1, health - amount)) end
    end
    if target:GetHealth() <= 1 then
        event_bus.emit(events.TREE_DEPLETED, {
            attacker = parent,
            target = target,
            player_id = self.player_id,
        })
    end
    sound_service.play("worker_lumberjack_tree_impact", {
        unit = target,
        source = target,
    })
    if self.technology_armor_reduction > 0
        and target:GetTeamNumber() ~= parent:GetTeamNumber() then
        local modifier = target:AddNewModifier(
            parent,
            nil,
            "modifier_research_armor_reduction",
            { armor_reduction_per_attack = self.technology_armor_reduction }
        )
    end
    event_bus.emit(events.TREE_HIT, {
        attacker = parent,
        target = target,
        team = parent:GetTeamNumber(),
        player_id = self.player_id,
        base_lumber_efficiency = self.base_lumber_efficiency
            + self.technology_lumber_efficiency,
        critical_chance_pct = self.technology_crit_chance or 0,
        fusion_count = self.fusion_count,
        wood_multiplier_chance_pct = self.wood_multiplier_chance_pct,
        gold_per_hit_flat = self.gold_per_hit_flat,
        personality_attack_growth_per_hit = self.personality_attack_growth_per_hit,
        source = "lumberjack",
    })
end

M.IDLE_RESUME_DELAY = IDLE_RESUME_DELAY

return M
