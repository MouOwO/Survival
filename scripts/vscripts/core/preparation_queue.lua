-- Indexed, bounded preparation work. No idle polling or scene enumeration.
-- Owners keep their normal activation deadline; an unfinished preparation is
-- claimed as a miss so the caller can preserve its original synchronous path.
local heap_factory = require("core/deadline_queue")
local clock_factory = require("core/performance_clock")
local M = {}

function M.new(options)
    local heap, entries, owners = heap_factory.new(), {}, {}
    local clock = options.clock or clock_factory.new()
    local total, sequence, running, closed = 0, 0, false, false
    local counters = {enqueued=0, prepared=0, failed=0, claimed=0,
        deadline_misses=0, discarded=0, batches=0, longest_batch_ms=0}
    local api, pump = {}, nil
    local function scope()
        return not closed and options.current()
    end
    local function forget(entry, dispose)
        if entries[entry.ticket] ~= entry then return end
        heap:remove(entry.id)
        entries[entry.ticket] = nil
        local owned = owners[entry.owner]
        if owned then
            owned[entry.ticket] = nil
            if next(owned) == nil then owners[entry.owner] = nil end
        end
        total = total - 1
        if dispose and options.current() then
            pcall(options.dispose, entry.owner, entry.ticket)
            counters.discarded = counters.discarded + 1
        end
    end
    function api.cancel(owner, ticket)
        local entry = entries[ticket]
        if entry and entry.owner == owner then forget(entry, true) end
    end
    function api.cancel_owner(owner)
        local owned = owners[owner]
        if not owned then return end
        local pending = {}
        for _, entry in pairs(owned) do pending[#pending + 1] = entry end
        for _, entry in ipairs(pending) do forget(entry, true) end
    end
    function api.clear()
        closed = true -- disposal callbacks cannot enqueue new work into a reset
        local pending = {}
        for _, entry in pairs(entries) do pending[#pending + 1] = entry end
        for _, entry in ipairs(pending) do forget(entry, true) end
        if running and options.current() then
            pcall(options.world.SetContextThink, options.world, options.name, nil, 0)
        end
        running = false
    end
    pump = function()
        if not scope() then api.clear(); return nil end
        local started, worked = clock(), 0
        while heap:peek() and worked < (options.max_items or 2) do
            if worked > 0 and clock() - started >= (options.budget_seconds or .002) then break end
            local item = heap:pop()
            local entry = item.task
            worked = worked + 1
            if entries[entry.ticket] == entry then
                if options.valid(entry.owner, entry.ticket) then
                    local ok, result = pcall(options.prepare, entry.owner, entry.ticket)
                    if entries[entry.ticket] == entry and scope()
                        and options.valid(entry.owner, entry.ticket) then
                        entry.ready = ok and result ~= nil and result ~= false
                        if entry.ready then
                            counters.prepared = counters.prepared + 1
                        else
                            counters.failed = counters.failed + 1
                            pcall(options.dispose, entry.owner, entry.ticket)
                        end
                    elseif options.current() then
                        -- A native/reward callback cancelled this exact entry
                        -- while preparation was in progress. Retire its partial
                        -- result, never another owner's replacement record.
                        pcall(options.dispose, entry.owner, entry.ticket)
                    end
                else
                    forget(entry, true)
                end
            end
            if not scope() then api.clear(); return nil end
        end
        counters.batches = counters.batches + 1
        counters.longest_batch_ms = math.max(counters.longest_batch_ms,
            math.max(0, clock() - started) * 1000)
        if heap:peek() then return 0 end -- next engine frame, not this batch
        running = false
        return nil
    end
    function api.enqueue(owner, ticket)
        if not scope() or entries[ticket] or total >= (options.capacity or 160)
            or not options.valid(owner, ticket) then return false end
        sequence = sequence + 1
        local entry = {id=sequence, run_at=ticket.due_at, owner=owner, ticket=ticket}
        entries[ticket] = entry
        local owned = owners[owner] or {}; owners[owner] = owned; owned[ticket] = entry
        total = total + 1; counters.enqueued = counters.enqueued + 1
        heap:put(entry.id, entry)
        if not running then
            running = true
            local ok, result = pcall(options.world.SetContextThink,
                options.world, options.name, pump, 0)
            if not ok or result == false then
                running = false; forget(entry, true); return false
            end
        end
        return true
    end
    function api.claim(owner, ticket)
        local entry = entries[ticket]
        if not entry or entry.owner ~= owner then return false end
        local ready = scope() and entry.ready == true and options.valid(owner, ticket)
        if ready then counters.claimed = counters.claimed + 1
        else counters.deadline_misses = counters.deadline_misses + 1 end
        forget(entry, not ready)
        return ready
    end
    function api.inspect()
        local result = {pending=total, queued=#heap.heap, worker_running=running}
        for key, value in pairs(counters) do result[key] = value end
        return result
    end
    return api
end
return M
