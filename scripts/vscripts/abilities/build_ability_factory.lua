local event_bus = require("core/event_bus")
local events = require("core/events")
local construction_rules = require(
    "config/generated/building_construction_rules"
)

local M = {}
local function build_cast_range(building_id)
    local row = (construction_rules.by_id or {})[building_id] or {}
    return tonumber(row.build_cast_range) or 200
end

function M.create(building_id)
    local Ability = class({})

    function Ability:GetBehavior()
        return DOTA_ABILITY_BEHAVIOR_POINT
    end

    function Ability:GetManaCost()
        return 0
    end

    function Ability:GetCastRange(location, target)
        -- The builder must be allowed to target a distant location. The
        -- building system moves Undying to the configured working radius and
        -- starts construction only after arrival.
        return 10000
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
