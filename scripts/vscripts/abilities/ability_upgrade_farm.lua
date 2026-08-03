local event_bus = require("core/event_bus")
local events = require("core/events")
local M = class({})

function M:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
function M:GetManaCost() return 0 end
function M:OnSpellStart()
    event_bus.emit(events.BUILDING_UPGRADE_REQUEST, {
        building = self:GetCaster(),
        source_ability = self,
    })
end

_G.ability_upgrade_farm = M
return M