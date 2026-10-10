local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})
_G.ability_survival_rogue_reward = M

local function owner_id(ability)
    local caster = ability:GetCaster()
    local player_id = caster and tonumber(caster.survival_player_id) or nil
    if player_id == nil and caster then player_id = caster:GetPlayerOwnerID() end
    return tonumber(player_id) or -1
end

local function selected_talent(ability)
    local snapshot = CustomNetTables and CustomNetTables:GetTableValue(
        "survival_rogue_reward", tostring(owner_id(ability)))
    local talent = snapshot and snapshot.builder_talent
    if talent and talent.card_id ~= nil and talent.card_id ~= "" then
        return talent
    end
end

function M:GetBehavior()
    if selected_talent(self) then return DOTA_ABILITY_BEHAVIOR_PASSIVE end
    return DOTA_ABILITY_BEHAVIOR_NO_TARGET + DOTA_ABILITY_BEHAVIOR_IMMEDIATE
end

function M:GetAbilityTextureName()
    local talent = selected_talent(self)
    return talent and talent.icon_name or "ogre_magi_multicast"
end

function M:OnSpellStart()
    if selected_talent(self) then return end
    local caster = self:GetCaster()
    local player_id = owner_id(self)
    print("[RogueRewardAbility] OnSpellStart player_id=" .. tostring(player_id)
        .. " caster=" .. tostring(caster and caster:entindex() or -1))
    local result = event_bus.request(events.ROGUE_REWARD_OPEN_REQUEST, {
        player_id = player_id, source = "builder",
    })
    print("[RogueRewardAbility] result ok=" .. tostring(result and result.ok == true)
        .. " error=" .. tostring(result and result.error or ""))
end

return M
