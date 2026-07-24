local event_bus = require("core/event_bus")
local events = require("core/events")

ability_survival_pickup_materials = class({})

function ability_survival_pickup_materials:OnSpellStart()
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return end
    event_bus.request(events.CHALLENGE_MATERIAL_PICKUP_REQUEST, {
        caster = caster,
        player_id = caster:GetPlayerOwnerID(),
    })
end