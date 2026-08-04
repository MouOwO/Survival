local M = {}

local phase_by_player = {}
local hero_by_player = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function hide_wearable_children(hero)
    if not hero.FirstMoveChild then
        return
    end
    local child = hero:FirstMoveChild()
    local no_draw = rawget(_G, "EF_NODRAW") or 32
    while valid_entity(child) do
        local next_child = child.NextMovePeer and child:NextMovePeer() or nil
        if child.GetClassname and child:GetClassname() == "dota_item_wearable"
            and child.AddEffects then
            child:AddEffects(no_draw)
        end
        child = next_child
    end
end

function M.isolate_placeholder(player_id, hero)
    if phase_by_player[player_id] ~= "placeholder"
        or hero_by_player[player_id] ~= hero
        or not valid_entity(hero) then
        return false, "placeholder_unavailable"
    end
    hero:AddNoDraw()
    hide_wearable_children(hero)
    if hero.SetControllableByPlayer then
        hero:SetControllableByPlayer(player_id, false)
    end
    if hero.SetAttackCapability then
        hero:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    end
    if hero.SetMoveCapability then
        hero:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
    end
    if hero.AddNewModifier and not hero:HasModifier("modifier_survival_placeholder_anchor") then
        hero:AddNewModifier(hero, nil, "modifier_survival_placeholder_anchor", {})
    end
    if hero.SetAbsOrigin then
        hero:SetAbsOrigin(Vector(0, 0, -10000))
    end
    print(string.format(
        "[PLACEHOLDER_ISOLATED] player=%s entindex=%s move=none collision=none selectable=false",
        tostring(player_id), tostring(hero:entindex())))
    return true, nil
end

function M.init()
    phase_by_player = {}
    hero_by_player = {}
end

function M.register_placeholder(player_id, hero)
    if not valid_entity(hero) then
        return false, "placeholder_invalid"
    end
    local phase = phase_by_player[player_id]
    if phase == "replacing" or phase == "combat_ready" then
        return false, "placeholder_phase_closed"
    end
    phase_by_player[player_id] = "placeholder"
    hero_by_player[player_id] = hero
    return M.isolate_placeholder(player_id, hero)
end

function M.begin_replacement(player_id)
    if phase_by_player[player_id] ~= "placeholder"
        or not valid_entity(hero_by_player[player_id]) then
        return nil, "placeholder_unavailable"
    end
    phase_by_player[player_id] = "replacing"
    return hero_by_player[player_id], nil
end

function M.commit_replacement(player_id, hero)
    if phase_by_player[player_id] ~= "replacing" or not valid_entity(hero) then
        return false, "replacement_commit_invalid"
    end
    phase_by_player[player_id] = "combat_ready"
    hero_by_player[player_id] = hero
    return true, nil
end

function M.abort_replacement(player_id)
    if phase_by_player[player_id] == "replacing" then
        phase_by_player[player_id] = "placeholder"
        M.isolate_placeholder(player_id, hero_by_player[player_id])
    end
end

function M.phase(player_id)
    return phase_by_player[player_id]
end

function M.is_placeholder_phase(player_id)
    local phase = phase_by_player[player_id]
    return phase == nil or phase == "placeholder"
end

return M