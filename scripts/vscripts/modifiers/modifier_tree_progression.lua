local scheduler = require("core/scheduler")

modifier_tree_progression = class({})
local M = modifier_tree_progression

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MIN_HEALTH,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
    }
end

function M:GetMinHealth()
    return 1
end

function M:OnTakeDamage(params)
    if not IsServer() then return end
    local parent = self:GetParent()
    if params.unit ~= parent or (tonumber(params.damage) or 0) <= 0 then return end
    if parent:GetHealth() > 1 or self.upgrade_pending then return end
    local callback = parent.survival_tree_depleted_callback
    if type(callback) ~= "function" then return end

    self.upgrade_pending = true
    scheduler.after(0, function()
        self.upgrade_pending = false
        if parent and not parent:IsNull() then
            callback(parent)
        end
    end, "tree_depleted_" .. tostring(parent:entindex()))
end

return M