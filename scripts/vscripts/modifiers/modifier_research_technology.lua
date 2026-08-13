modifier_research_technology = class({})
modifier_research_armor_reduction = class({})

local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local armor_balance = require("config/armor_balance")
local M = modifier_research_technology

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    self:ApplyValues(params or {})
end

function M:OnRefresh(params)
    self:ApplyValues(params or {})
end

function M:ApplyValues(params)
    self.attack_pct = tonumber(params.attack_pct) or self.attack_pct or 0
    self.final_damage_pct = tonumber(params.final_damage_pct)
        or self.final_damage_pct or 0
    self.armor_reduction = tonumber(params.armor_reduction)
        or self.armor_reduction or 0
    if IsServer() then
        self:GetParent().survival_research_final_damage_pct =
            self.final_damage_pct
    end
end

function M:SetTechnologyValues(attack_pct, final_damage_pct, armor_reduction,
        critical_chance_pct)
    self.attack_pct = math.max(0, tonumber(attack_pct) or 0)
    self.final_damage_pct = math.max(0, tonumber(final_damage_pct) or 0)
    self.armor_reduction = math.max(0, tonumber(armor_reduction) or 0)
    self.critical_chance_pct = math.max(
        0, tonumber(critical_chance_pct) or 0
    )
    self:GetParent().survival_research_final_damage_pct =
        self.final_damage_pct
    self:ForceRefresh()
end

function M:OnDestroy()
    if IsServer() then
        self:GetParent().survival_research_final_damage_pct = nil
    end
end

function M:DeclareFunctions()
    return {}
end

local D = modifier_research_armor_reduction

local ARMOR_DIAGNOSTIC_MILESTONES = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [10] = true,
    [25] = true,
    [50] = true,
    [100] = true,
    [250] = true,
    [500] = true,
}

local function publish_armor_changed(modifier, diagnostic)
    local parent = modifier:GetParent()
    if not parent or parent:IsNull() then return end
    local entindex = parent:entindex()
    local custom_war3 = tonumber(parent.survival_armor_mapping_version)
        == armor_balance.CUSTOM_WAR3_MAPPING_VERSION
    local reduction = custom_war3
        and math.max(0, tonumber(parent.survival_war3_armor_reduction) or 0)
        or math.max(0, (tonumber(modifier:GetStackCount()) or 0) / 100)
    -- SetStackCount updates the Lua state immediately, but engine armor can
    -- still be stale in the same call stack. Publish on the next scheduler
    -- frame so the selected-unit UI reads the resolved effective armor.
    scheduler.after(0, function()
        if not parent or parent:IsNull() then return end
        if diagnostic and ARMOR_DIAGNOSTIC_MILESTONES[diagnostic.hit] then
            local armor_after = custom_war3
                and tonumber(parent.survival_effective_war3_armor)
                or tonumber(parent:GetPhysicalArmorValue(false))
            local armor_before = tonumber(diagnostic.armor_before)
            print(string.format(
                "[RESEARCH_ARMOR_EFFECT] hit=%s target=%s phase=%s "
                    .. "increment=%s stack_scheduled=%s stack_resolved=%s "
                    .. "reduction=%s armor_before=%s armor_after=%s "
                    .. "armor_delta=%s minimum=%s",
                tostring(diagnostic.hit),
                tostring(entindex),
                tostring(diagnostic.phase),
                tostring(diagnostic.increment),
                tostring(diagnostic.stack),
                tostring(modifier:GetStackCount()),
                tostring(reduction),
                tostring(armor_before),
                tostring(armor_after),
                tostring(armor_before and armor_after
                    and armor_after - armor_before or "unavailable"),
                tostring(custom_war3 and parent.survival_minimum_war3_armor
                    or parent.survival_minimum_armor)
            ))
        end
        event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
            entindex = entindex,
            unit = parent,
            reason = "research_armor_reduction",
            research_armor_reduction = reduction,
        })
    end)
end

function D:IsHidden() return false end
function D:IsDebuff() return true end
function D:IsPurgable() return false end
function D:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function D:OnCreated(params)
    self.armor_reduction = 0
    self.war3_armor_reduction = 0
    self:AddArmorReduction(
        params and params.armor_reduction_per_attack or 0,
        params and params.diagnostic_hit,
        "created"
    )
end

function D:OnRefresh(params)
    self:AddArmorReduction(
        params and params.armor_reduction_per_attack or 0,
        params and params.diagnostic_hit,
        "refreshed"
    )
end

function D:AddArmorReduction(value, diagnostic_hit, phase)
    if not IsServer() then return end
    local increment = math.max(0, tonumber(value) or 0)
    if increment <= 0 then return end
    local parent = self:GetParent()
    local armor_before = tonumber(parent:GetPhysicalArmorValue(false))
    local mapping_version = tonumber(parent.survival_armor_mapping_version)
    local war3_mapping = mapping_version == armor_balance.MODERN_MAPPING_VERSION
        or mapping_version == armor_balance.CUSTOM_WAR3_MAPPING_VERSION
    if war3_mapping and tonumber(parent.survival_war3_armor) ~= nil then
        local minimum_war3 = tonumber(parent.survival_minimum_war3_armor)
        local war3_increment = armor_balance.to_war3_linear(increment)
        local current_reduction = math.max(0,
            tonumber(self.war3_armor_reduction) or 0)
        local target_reduction = current_reduction + war3_increment
        if minimum_war3 ~= nil then
            local maximum_reduction = math.max(0,
                tonumber(parent.survival_war3_armor) - minimum_war3)
            target_reduction = math.min(target_reduction, maximum_reduction)
        end
        self.war3_armor_reduction = target_reduction
        parent.survival_war3_armor_reduction = target_reduction
        parent.survival_effective_war3_armor =
            armor_balance.effective_war3_armor(
                parent.survival_war3_armor,
                target_reduction,
                minimum_war3,
                parent.survival_poison_cloud_armor_reduction_pct
            )
        if mapping_version == armor_balance.CUSTOM_WAR3_MAPPING_VERSION then
            local target_stack = math.floor(target_reduction * 100 + 0.000001)
            self.armor_reduction = 0
            if target_stack <= (tonumber(self:GetStackCount()) or 0) then return end
            self:SetStackCount(target_stack)
            publish_armor_changed(self, {
                hit = tonumber(diagnostic_hit),
                phase = phase or "unknown",
                increment = war3_increment,
                armor_before = tonumber(parent.survival_effective_war3_armor)
                    + war3_increment,
                stack = target_stack,
            })
            return
        end
        local base_runtime = armor_balance.from_war3_modern(
            parent.survival_war3_armor
        )
        local effective_runtime = armor_balance.from_war3_modern(
            parent.survival_effective_war3_armor
        )
        local runtime_reduction = math.max(0, base_runtime - effective_runtime)
        -- StackCount remains hundredths of actual Dota armor so the replicated
        -- modifier property has identical server/client semantics. The War3
        -- accumulator is server-owned and only drives the nonlinear remap.
        local target_stack = math.floor(runtime_reduction * 100 + 0.000001)
        self.armor_reduction = runtime_reduction
        if target_stack <= (tonumber(self:GetStackCount()) or 0) then return end
        self:SetStackCount(target_stack)
        publish_armor_changed(self, {
            hit = tonumber(diagnostic_hit),
            phase = phase or "unknown",
            increment = war3_increment,
            armor_before = armor_before,
            stack = target_stack,
        })
        return
    end
    local minimum = tonumber(parent.survival_minimum_armor)
    local applied_reduction = math.max(
        0,
        (tonumber(self:GetStackCount()) or 0) / 100
    )
    local accumulated_reduction = math.max(
        applied_reduction,
        tonumber(self.armor_reduction) or 0
    )
    local target_reduction = accumulated_reduction + increment
    if minimum ~= nil then
        local current = tonumber(parent:GetPhysicalArmorValue(false)) or minimum
        local armor_without_this_modifier = current + applied_reduction
        local maximum_reduction = math.max(
            0,
            armor_without_this_modifier - minimum
        )
        target_reduction = math.min(target_reduction, maximum_reduction)
    end
    -- The modifier stack stores hundredths of armor. Round down at the minimum
    -- boundary so repeated fractional reductions can never cross below it.
    local target_stack = math.floor(target_reduction * 100 + 0.000001)
    self.armor_reduction = target_reduction
    if target_stack <= (tonumber(self:GetStackCount()) or 0) then return end
    self:SetStackCount(target_stack)
    publish_armor_changed(self, {
        hit = tonumber(diagnostic_hit),
        phase = phase or "unknown",
        increment = increment,
        armor_before = armor_before,
        stack = target_stack,
    })
end

function D:DeclareFunctions()
    return { MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS }
end

function D:GetModifierPhysicalArmorBonus()
    if tonumber(self:GetParent().survival_armor_mapping_version)
        == armor_balance.CUSTOM_WAR3_MAPPING_VERSION then
        return 0
    end
    return -(self:GetStackCount() or 0) / 100
end

return M
