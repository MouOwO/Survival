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

local function positive_amount(amount)
    local value = tonumber(amount) or 0
    if value <= 0 or value ~= value or value == math.huge then return 0 end
    return math.floor(value)
end

local function show(entry, wood, gold, player)
    if wood > 0 then
        particle_manager.show_green_number(entry.worker, wood, player)
    end
    if gold > 0 then
        CustomGameEventManager:Send_ServerToPlayer(player,
            "survival_gold_mine_income_number", {
                target_entindex = entry.entindex, amount = gold, critical = 0,
            })
    end
end

function M.add(player_id, worker, wood, gold)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 or player_id == math.huge
        or player_id ~= player_id or player_id ~= math.floor(player_id)
        or not valid(worker) then return end
    wood, gold = positive_amount(wood), positive_amount(gold)
    if wood <= 0 and gold <= 0 then return end
    local entindex = worker:entindex()
    local id = task_id(player_id, entindex)
    local entry = pending[id]
    if entry and entry.worker ~= worker then
        scheduler.cancel(id)
        pending[id] = nil
        entry = nil
    end
    if entry then
        entry.wood = entry.wood + wood
        entry.gold = entry.gold + gold
        return
    end
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return end
    entry = {worker = worker, player_id = player_id, entindex = entindex, wood = 0, gold = 0}
    pending[id] = entry
    scheduler.after(INTERVAL, function()
        if pending[id] ~= entry then return end
        if not valid(entry.worker) or (entry.wood <= 0 and entry.gold <= 0) then
            pending[id] = nil
            return
        end
        local owner = PlayerResource:GetPlayer(entry.player_id)
        if not owner then pending[id] = nil; return end
        local accumulated_wood, accumulated_gold = entry.wood, entry.gold
        entry.wood, entry.gold = 0, 0
        show(entry, accumulated_wood, accumulated_gold, owner)
        if pending[id] == entry then return INTERVAL end
    end, id)
    -- The first real hit is immediate; only subsequent hits share this window.
    show(entry, wood, gold, player)
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
