-- Presentation only. Resource settlement never waits for this queue.
local scheduler = require("core/scheduler")
local particle_manager = require("core/particle_manager")
local M = {}
local pending = {}
local INTERVAL = 0.25

local function valid(unit)
    return unit and not unit:IsNull()
end

local function task_id(player_id, entindex)
    return "harvest_feedback_" .. tostring(player_id) .. "_" .. tostring(entindex)
end

function M.add(player_id, worker, wood, gold)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 or not valid(worker) then return end
    local entindex = worker:entindex()
    local id = task_id(player_id, entindex)
    local entry = pending[id]
    if entry and entry.worker ~= worker then
        scheduler.cancel(id)
        entry = nil
    end
    if not entry then
        entry = {worker = worker, player_id = player_id, wood = 0, gold = 0}
        pending[id] = entry
        scheduler.after(INTERVAL, function()
            if pending[id] ~= entry then return end
            pending[id] = nil
            if not valid(entry.worker) then return end
            local player = PlayerResource:GetPlayer(entry.player_id)
            if not player then return end
            particle_manager.show_green_number(entry.worker, entry.wood, player)
            if entry.gold > 0 then
                CustomGameEventManager:Send_ServerToPlayer(player,
                    "survival_gold_mine_income_number", {
                        target_entindex = entindex, amount = entry.gold, critical = 0,
                    })
            end
        end, id)
    end
    entry.wood = entry.wood + math.max(0, math.floor(tonumber(wood) or 0))
    entry.gold = entry.gold + math.max(0, math.floor(tonumber(gold) or 0))
end

function M.reset(player_id)
    for id, entry in pairs(pending) do
        if player_id == nil or entry.player_id == tonumber(player_id) then
            scheduler.cancel(id)
            pending[id] = nil
        end
    end
end

return M
