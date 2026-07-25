local event_bus = require("core/event_bus")
local events = require("core/events")
local essences = require("config/seven_sins_essences")

local function use(self)
    if not IsServer() then return end
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return end
    local player_id = caster:GetPlayerOwnerID()
    local definition = essences.by_engine_item_name[self:GetAbilityName()]
    if player_id == nil or player_id < 0 or not definition then return end
    event_bus.request(events.SEVEN_SINS_ESSENCE_USE_REQUEST, {
        player_id = player_id,
        caster = caster,
        item = self,
        content_id = definition.content_id,
    })
end

for _, definition in ipairs(essences.rows) do
    local item_class = class({})
    item_class.OnSpellStart = use
    _G[definition.engine_item_name] = item_class
end

return true