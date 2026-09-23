local event_bus = require("core/event_bus")
local events = require("core/events")
local M = {}

local function player_id_from_caster(caster)
    if not caster or caster:IsNull() then return -1 end
    return tonumber(caster.survival_player_id) or caster:GetPlayerOwnerID()
end

function M.create(class_index)
    local Ability = class({})
    function Ability:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
    function Ability:GetManaCost() return 0 end
    function Ability:CastFilterResult()
        if not IsServer() then return UF_SUCCESS end
        local request = {
            player_id = player_id_from_caster(self:GetCaster()),
            tower = self:GetCaster(),
            class_index = class_index,
            source_ability = self,
        }
        local result = event_bus.request(events.TOWER_CLASS_CHECK_REQUEST, request)
            or request.result
        self.cast_error = result and result.error or "防御塔转职当前不可用"
        if result and result.ok == true then
            self.cast_error = nil
            return UF_SUCCESS
        end
        return UF_FAIL_CUSTOM
    end
    function Ability:GetCustomCastError()
        return self.cast_error or "防御塔转职当前不可用"
    end
    function Ability:OnSpellStart()
        if not IsServer() then return end
        local result = event_bus.request(events.TOWER_CLASS_REQUEST, {
            player_id = player_id_from_caster(self:GetCaster()),
            tower = self:GetCaster(),
            class_index = class_index,
            source_ability = self,
        })
        if not result or not result.ok then self:EndCooldown() end
    end
    return Ability
end

return M
