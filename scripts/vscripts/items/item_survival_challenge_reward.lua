local event_bus = require("core/event_bus")
local events = require("core/events")

item_survival_challenge_reward = class({})

function item_survival_challenge_reward:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_NO_TARGET + DOTA_ABILITY_BEHAVIOR_IMMEDIATE
end

function item_survival_challenge_reward:Claim(caster)
    if not IsServer() or self.survival_claimed then return false end
    local player_id = caster and caster:GetPlayerOwnerID() or -1
    local owner_id = tonumber(self.survival_owner_player_id)
    local content_id = tostring(self.survival_content_id or "")
    if player_id < 0 or owner_id ~= player_id or content_id == "" then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "该挑战材料不属于你",
            level = "error",
        })
        return false
    end
    -- The native pickup has temporarily occupied an inventory slot. Free it
    -- before publishing the authoritative grant so the visual material shell
    -- can always use that same slot. Keep this entity alive for rollback.
    if caster.RemoveItem then caster:RemoveItem(self) end
    local result = event_bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST, {
        player_id = player_id,
        content_id = content_id,
        count = 1,
        reason = "challenge_ground_reward_pickup",
    })
    if not result or not result.ok then
        if caster.AddItem and not self:IsNull() then caster:AddItem(self) end
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "挑战材料入库失败："
                .. tostring(result and result.error or "handler_missing"),
            level = "error",
        })
        return false
    end
    self.survival_claimed = true
    CustomNetTables:SetTableValue(
        "survival_inventory_item_identity",
        tostring(self:entindex()),
        { content_id = content_id, removed = 1 }
    )
    UTIL_Remove(self)
    return true
end

function item_survival_challenge_reward:OnSpellStart()
    self:Claim(self:GetCaster())
end

return item_survival_challenge_reward