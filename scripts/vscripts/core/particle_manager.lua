local M = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

function M.show_green_number(unit, amount, player)
    if not valid_entity(unit) then return end
    local value = math.max(0, math.floor(tonumber(amount) or 0))
    if value <= 0 then return end
    if not player and unit.GetPlayerOwnerID then
        local player_id = unit:GetPlayerOwnerID()
        if player_id and player_id >= 0 then
            player = PlayerResource:GetPlayer(player_id)
        end
    end
    SendOverheadEventMessage(
        player,
        OVERHEAD_ALERT_HEAL,
        unit,
        value,
        nil
    )
end

return M
