local event_bus = require("core/event_bus")
local events = require("core/events")
local essences = require("config/seven_sins_essences")

local function request_use(self, caster)
    if not IsServer() or not caster or caster:IsNull() then return false end
    local player_id = caster:GetPlayerOwnerID()
    local definition = essences.by_engine_item_name[self:GetAbilityName()]
    if player_id == nil or player_id < 0 or not definition then return false end
    local result, request_error = event_bus.request(events.SEVEN_SINS_ESSENCE_USE_REQUEST, {
        player_id = player_id,
        caster = caster,
        item = self,
        content_id = definition.content_id,
    })
    if not result or not result.ok then
        print(string.format(
            "[SEVEN_SINS_ESSENCE_USE_FAILED] player=%s content=%s error=%s",
            tostring(player_id),
            tostring(definition.content_id),
            tostring(result and result.error or request_error or "handler_missing")
        ))
        return false
    end
    return true
end

local function use(self)
    request_use(self, self:GetCaster())
end

local function claim(self, caster)
    if not IsServer() or not caster or caster:IsNull()
        or not self or self:IsNull() then return false end
    local charges = math.max(1, math.floor(tonumber(
        self.GetCurrentCharges and self:GetCurrentCharges() or 1
    ) or 1))
    local consumed = 0
    while consumed < charges and self and not self:IsNull() do
        if not request_use(self, caster) then break end
        consumed = consumed + 1
    end
    return consumed == charges
end

for _, definition in ipairs(essences.rows) do
    local item_class = class({})
    function item_class:GetBehavior()
        return DOTA_ABILITY_BEHAVIOR_NO_TARGET
            + DOTA_ABILITY_BEHAVIOR_IMMEDIATE
    end
    item_class.OnSpellStart = use
    item_class.Claim = claim
    _G[definition.engine_item_name] = item_class
end

return true