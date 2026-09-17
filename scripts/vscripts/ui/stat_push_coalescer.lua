-- Presentation-only: bounded latest-value delivery, independent of gameplay ticks.
local M = {}
local transport = {reason=true, push_phase=true, refresh_sequence=true}
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k,v in pairs(a) do
        if not transport[k] and not equal(v,b[k]) then return false end
    end
    for k in pairs(b) do
        if not transport[k] and a[k] == nil then return false end
    end
    return true
end
function M.new(options)
    local latest, queued, sent, generation = {}, {}, {}, 0
    local api = {}
    function api.reset()
        generation = generation + 1
        for player in pairs(queued) do options.scheduler.cancel("building_ui_push_"..player) end
        latest, queued, sent = {}, {}, {}
    end
    function api.push(payload)
        local player = tonumber(payload and payload.player_id)
        local unit = tonumber(payload and payload.entindex)
        if not player or not unit or not options.is_selected(player,unit) then return end
        local copy = {}
        for k,v in pairs(payload) do copy[k] = v end
        latest[player] = copy
        if queued[player] then return end
        queued[player] = true
        local current_generation = generation
        options.scheduler.after(0.15,function()
            if generation ~= current_generation then return end
            queued[player] = nil
            local value = latest[player]; latest[player] = nil
            if not value or not options.is_selected(player,tonumber(value.entindex)) then return end
            local snapshot = options.build(value)
            if not snapshot then return end
            if sent[player] and equal(sent[player],snapshot) then return end
            sent[player] = snapshot
            options.send(player,snapshot)
        end,"building_ui_push_"..player)
    end
    return api
end
return M
