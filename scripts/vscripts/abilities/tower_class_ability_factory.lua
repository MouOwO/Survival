local event_bus = require("core/event_bus")
local events = require("core/events")
local M = {}

function M.create(class_index)
    local Ability = class({})
    function Ability:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
    function Ability:GetManaCost() return 0 end
    function Ability:OnSpellStart()
        event_bus.emit(events.TOWER_CLASS_REQUEST, {
            tower = self:GetCaster(),
            class_index = class_index,
        })
    end
    return Ability
end

return M
