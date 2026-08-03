local definitions = require("config/generated/hero_skill_definitions")

local M = {}

local function create_ability_class()
    local ability_class = class({})

    function ability_class:GetIntrinsicModifierName()
        return "modifier_survival_hero_skill"
    end

    function ability_class:IsStealable()
        return false
    end

    function ability_class:IsHiddenWhenStolen()
        return true
    end

    function ability_class:GetManaCost() return 0 end

    function ability_class:GetCooldown()
        if self:GetAbilityName() == "ability_survival_monkey_king_agility" then
            return 0
        end
        return self.BaseClass.GetCooldown(self, self:GetLevel())
    end

    function ability_class:OnSpellStart()
        if self:GetAbilityName() ~= "ability_survival_monkey_king_agility" then
            return
        end
        local caster = self:GetCaster()
        local result = require("systems/tower_fusion_service")
            .teleport_for_player(caster:GetPlayerOwnerID(), caster)
        if not result or not result.ok then self:EndCooldown() end
    end

    function ability_class:OnProjectileHit_ExtraData(target, location, extra_data)
        local service = require("systems/hero_passive_skill_service")
        return service.on_tracking_projectile_hit(self, target, location, extra_data)
    end

    return ability_class
end

for _, definition in ipairs(definitions.rows or {}) do
    if definition.enabled ~= false
        and definition.ability_name
        and definition.ability_name ~= "" then
        _G[definition.ability_name] = create_ability_class()
    end
end

return M
