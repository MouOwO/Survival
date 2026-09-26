local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})
_G.ability_survival_rogue_reward = M

function M:GetAbilityTextureName()
    local caster = self:GetCaster()
    local player_id = caster and caster:GetPlayerOwnerID() or -1
    local snapshot = CustomNetTables and CustomNetTables:GetTableValue("survival_rogue_reward", tostring(player_id))
    local talent = snapshot and snapshot.builder_talent
    return talent and talent.icon_name or "survival/native/talent_question"
end

function M:OnSpellStart()
    local caster = self:GetCaster()
    local player_id = caster and tonumber(caster.survival_player_id) or nil
    if player_id == nil and caster then player_id = caster:GetPlayerOwnerID() end
    player_id = tonumber(player_id) or -1
    print("[RogueRewardAbility] OnSpellStart player_id=" .. tostring(player_id)
        .. " caster=" .. tostring(caster and caster:entindex() or -1))
    local result = event_bus.request(events.ROGUE_REWARD_OPEN_REQUEST, {
        player_id = player_id, source = "builder",
    })
    print("[RogueRewardAbility] result ok=" .. tostring(result and result.ok == true)
        .. " error=" .. tostring(result and result.error or ""))
end

return M