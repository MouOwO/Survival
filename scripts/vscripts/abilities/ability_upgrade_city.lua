local event_bus = require("core/event_bus")
local events = require("core/events")
local M = class({})

function M:GetBehavior() return DOTA_ABILITY_BEHAVIOR_NO_TARGET end
function M:GetManaCost() return 0 end
function M:OnSpellStart()
    print("[MainCityAbility] upgrade cast entindex="
        .. tostring(self:GetCaster():entindex()))
    local result = event_bus.request(events.BUILDING_UPGRADE_REQUEST, {
        building = self:GetCaster(),
        source_ability = self,
    })
    if not result or not result.ok then self:EndCooldown() end
end

_G.ability_upgrade_city = M
return M
