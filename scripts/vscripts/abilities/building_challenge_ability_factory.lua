local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

function M.create(challenge_id)
    local Ability = class({})

    function Ability:OnSpellStart()
        local caster = self:GetCaster()
        local result = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
            building = caster,
            building_entindex = caster and caster:entindex() or -1,
            challenge_id = challenge_id,
            source_ability = self,
        })
        if not result or result.ok ~= true then
            self:EndCooldown()
        end
    end

    return Ability
end

return M