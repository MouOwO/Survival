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
