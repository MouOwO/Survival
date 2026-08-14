local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})
_G.ability_challenge_auto_summon = M

function M:OnToggle()
    if self.survival_reverting_toggle then
        self.survival_reverting_toggle = nil
        return
    end
    local caster = self:GetCaster()
    local result = event_bus.request(events.BUILDING_CHALLENGE_AUTO_REQUEST, {
        building = caster,
        building_entindex = caster and caster:entindex() or -1,
        enabled = self:GetToggleState() == true,
    })
    if not result or result.ok ~= true then
        self.survival_reverting_toggle = true
        self:ToggleAbility()
    end
end

return M