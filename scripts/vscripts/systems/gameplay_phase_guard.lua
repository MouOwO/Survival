local M = {}
local frozen = false
local settled = false
local endless_players, endless_count = {}, 0

function M.post_clear_frozen()
    return settled or (frozen and endless_count == 0)
end

function M.set_post_clear_frozen(value)
    frozen = value == true
    -- A new settlement/defeat must override any previous playable window.
    if frozen then endless_players, endless_count = {}, 0 end
end

function M.set_endless_active(player_id, active)
    if settled and active == true then return false end
    if active == true and not endless_players[player_id] then
        endless_players[player_id] = true
        endless_count = endless_count + 1
    elseif active ~= true and endless_players[player_id] then
        endless_players[player_id] = nil
        endless_count = endless_count - 1
    end
    return true
end

function M.freeze_for_settlement()
    -- Final saves and defeat animations still run before SetGameWinner. New
    -- endless requests must not reopen gameplay during that interval.
    settled = true
    endless_players, endless_count = {}, 0
end

function M.reset()
    frozen = false
    settled = false
    endless_players, endless_count = {}, 0
end

return M
