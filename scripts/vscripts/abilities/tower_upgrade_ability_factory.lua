local event_bus = require("core/event_bus")
local events = require("core/events")

local function create(mode)
    local Ability = class({})
    function Ability:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
    function Ability:GetManaCost() return 0 end
    function Ability:OnSpellStart()
        event_bus.emit(events.BUILDING_UPGRADE_REQUEST, {
            building = self:GetCaster(),
            upgrade_mode = mode,
        })
    end
    return Ability
end

return { create = create }
