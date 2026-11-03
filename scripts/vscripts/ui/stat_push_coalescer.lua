-- Presentation-only: bounded latest-value delivery, independent of gameplay ticks.
local M = {}
local transport = {reason=true, push_phase=true, refresh_sequence=true, server_time=true}
local function equal(a,b)
    -- Projectors replace immutable cached research/catalogue subtrees only on
    -- real generation changes. Never walk those same tables on every push.
    if a == b then return true end
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
    local latest, queued, sent, versions, generation = {}, {}, {}, {}, 0
    local prefix = options.task_prefix or "building_ui_push_"
    local interval = options.interval or 0.15
    local api = {}
    function api.reset()
        generation = generation + 1
        for player in pairs(queued) do options.scheduler.cancel(prefix..player) end
        latest, queued, sent, versions = {}, {}, {}, {}
    end
    function api.disconnect(player)
        versions[player]=(versions[player]or 0)+1
        options.scheduler.cancel(prefix..player)
        latest[player],queued[player],sent[player]=nil,nil,nil
    end
    function api.push(payload)
        local player = tonumber(payload and payload.player_id)
        local unit = tonumber(payload and payload.entindex)
        if not player or not unit or not options.is_selected(player,unit) then return end
        local copy = {}
        for k,v in pairs(payload) do copy[k] = v end
        if options.merge and latest[player] and latest[player].entindex == copy.entindex then
            options.merge(latest[player], copy)
        end
        latest[player] = copy
        if queued[player] then return end
        queued[player] = true
        local current_generation = generation
        local player_generation = versions[player]or 0
        options.scheduler.after(interval,function()
            if generation ~= current_generation or (versions[player]or 0)~=player_generation then return end
            queued[player] = nil
            local value = latest[player]; latest[player] = nil
            if not value or not options.is_selected(player,tonumber(value.entindex)) then return end
            local snapshot = options.build(value)
            if not snapshot then return end
            if sent[player] and equal(sent[player],snapshot) then return end
            sent[player] = snapshot
            options.send(player,snapshot)
        end,prefix..player)
    end
    return api
end
return M
