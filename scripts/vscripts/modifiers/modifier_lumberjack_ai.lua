local event_bus = require("core/event_bus")
local events = require("core/events")
local sound_service = require("core/sound_service")

modifier_lumberjack_ai = class({})
local M = modifier_lumberjack_ai

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
    self:StartIntervalThink(0.5)
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
    if parent:GetAttackTarget() == tree then return end

    ExecuteOrderFromTable({
        UnitIndex = parent:entindex(),
        OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
        TargetIndex = tree:entindex(),
        Queue = false,
    })
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
        source = "lumberjack",
    })
end

return M
