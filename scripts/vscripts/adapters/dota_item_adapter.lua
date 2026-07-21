local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function valid(entity)
    return entity and entity.IsNull and not entity:IsNull()
end

function M.add_growth_tracker(hero, player_id)
    if not valid(hero) or not hero.AddNewModifier then return false, "hero_invalid" end
    if hero.HasModifier and hero:HasModifier("modifier_weapon_attack_tracker") then
        return true
    end
    hero:AddNewModifier(hero, nil, "modifier_weapon_growth_tracker", {
        player_id = player_id,
    })
    return true
end

function M.emit_valid_kill(victim, attacker)
    if not valid(victim) or not valid(attacker) then return false end
    if attacker.GetTeamNumber and victim.GetTeamNumber
        and attacker:GetTeamNumber() == victim:GetTeamNumber() then return false end
    local owner = attacker
    if attacker.GetOwnerEntity and valid(attacker:GetOwnerEntity()) then owner = attacker:GetOwnerEntity() end
    local player_id = owner.GetPlayerOwnerID and owner:GetPlayerOwnerID() or -1
    if player_id < 0 then return false end
    event_bus.emit(events.WEAPON_ENEMY_KILLED, {
        player_id = player_id, attacker = attacker, owner = owner, victim = victim,
        victim_entindex = victim.entindex and victim:entindex() or -1,
    })
    return true
end

return M
