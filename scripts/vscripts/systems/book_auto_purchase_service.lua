local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local M = {}
local enabled, removed = {}, {}
local allowed = { shop_item_knowledge_book = true, shop_item_super_knowledge_book = true }
local function task_id(player_id) return "book_auto_purchase:" .. tostring(player_id) end
local function publish(player_id)
    if CustomNetTables then
        local values = {}
        for id in pairs(enabled[player_id] or {}) do values[id] = 1 end
        CustomNetTables:SetTableValue("survival_shop_config", "auto_purchase_" .. player_id, values)
    end
end
function M.init(purchase)
    for player_id in pairs(enabled) do
        scheduler.cancel(task_id(player_id))
        enabled[player_id] = nil
        publish(player_id)
    end
    enabled, removed = {}, {}
    event_bus.handle_request(events.SHOP_AUTO_PURCHASE_TOGGLE_REQUEST, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        local id = tostring(payload and payload.entry_id or "")
        if not player_id or player_id < 0 or not PlayerResource:IsValidPlayerID(player_id)
            or removed[player_id] or not allowed[id] then
            return { ok = false, error = "auto_purchase_invalid" }
        end
        local bucket = enabled[player_id] or {}
        enabled[player_id] = bucket
        bucket[id] = not bucket[id] or nil
        publish(player_id)
        scheduler.cancel(task_id(player_id))
        if next(bucket) then
            scheduler.every(1, function()
                if removed[player_id] or not next(bucket) then return false end
                -- Reuse authoritative costs, stock, unlock and cooldown checks.
                for entry_id in pairs(bucket) do
                    purchase({ player_id = player_id, entry_id = entry_id,
                        silent_notification = true, source = "book_auto_purchase" })
                end
            end, task_id(player_id))
        end
        return { ok = true, enabled = bucket[id] == true }
    end)
    local function stop(payload)
        local player_id = tonumber(payload and payload.player_id)
        if not player_id then return end
        removed[player_id] = true
        enabled[player_id] = nil
        scheduler.cancel(task_id(player_id))
        publish(player_id)
    end
    event_bus.subscribe(events.PLAYER_DEFEATED, stop)
    event_bus.subscribe(events.PLAYER_DISCONNECTED, stop)
end
return M
