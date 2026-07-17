local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

function M.create(building_id)
    local Ability = class({})

    function Ability:GetBehavior()
        return DOTA_ABILITY_BEHAVIOR_POINT
    end

    function Ability:GetManaCost()
        return 0
    end

    function Ability:CastFilterResultLocation(location)
        if not IsServer() then return UF_SUCCESS end
        local result = event_bus.request(events.BUILD_CAN_PLACE_REQUEST, {
            caster = self:GetCaster(),
            building_id = building_id,
            position = location,
        })
        self.cast_error = result and result.error or "build_validation_failed"
        return result and result.ok and UF_SUCCESS or UF_FAIL_CUSTOM
    end

    function Ability:GetCustomCastErrorLocation()
        return self.cast_error or "无法在此建造"
    end

    function Ability:OnSpellStart()
        event_bus.emit(events.BUILD_REQUEST, {
            caster = self:GetCaster(),
            building_id = building_id,
            position = self:GetCursorPosition(),
        })
    end

    return Ability
end

return M
