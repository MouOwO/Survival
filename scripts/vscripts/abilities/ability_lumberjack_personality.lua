local definitions = require("config/generated/lumberjack_personality_definitions")

local M = class({})
function M:GetIntrinsicModifierName() return "modifier_lumberjack_personality" end
function M:IsStealable() return false end
function M:IsHiddenWhenStolen() return true end
function M:GetManaCost() return 0 end

for _, row in ipairs(definitions.rows or {}) do
    if row.enabled ~= false and row.ability_name then
        _G[row.ability_name] = M
    end
end
return M