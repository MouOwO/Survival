local M = {}
local config = nil
local transactions = {}
local pending = {}
local recent, expiry_queue, head, tail = {}, {}, 1, 0
local active_count, recent_count, serial, generation = 0, 0, 0, 0
local HISTORY_SECONDS, HISTORY_LIMIT = 10, 8192

local function prune()
    local time, work = GameRules:GetGameTime(), 0
    while head <= tail and work < 64 do
        local entry = expiry_queue[head]
        if recent[entry.transaction_id] == entry
            and entry.expires_at > time and recent_count <= HISTORY_LIMIT then break end
        expiry_queue[head], head, work = nil, head + 1, work + 1
        if recent[entry.transaction_id] == entry then
            recent[entry.transaction_id], recent_count = nil, recent_count - 1
        end
    end
    if head > tail then expiry_queue, head, tail = {}, 1, 0 end
end

local function id(value)
    if value and tostring(value) ~= "" then return tostring(value) end
    -- Unique even for thousands of same-frame hits; no random collision drops.
    serial = serial + 1
    return string.format("damage:%d:%d", generation, serial)
end

function M.init(rule_config)
    config = rule_config
    transactions = {}
    pending = {}
    recent, expiry_queue, head, tail = {}, {}, 1, 0
    active_count, recent_count, serial, generation = 0, 0, 0, generation + 1
end

function M.create(request)
    request = request or {}
    prune()
    local requested_id = request.transaction_id and tostring(request.transaction_id)
    local previous = requested_id and (transactions[requested_id] or recent[requested_id])
    if previous and (not previous.expires_at or previous.expires_at > GameRules:GetGameTime()) then
        return {
            transaction_id = tostring(request.transaction_id),
            parent_transaction_id = request.parent_transaction_id,
            recursion_depth = 0,
            source_kind = request.source_kind or "script",
            tags = request.tags or {},
            created_time = GameRules:GetGameTime(),
            blocked = "duplicate_transaction_id",
        }
    end
    local parent = request.parent_transaction_id and tostring(request.parent_transaction_id)
    local parent_record = parent and M.get(parent) or nil
    local depth = parent_record and parent_record.recursion_depth + 1 or 0
    local record = {
        transaction_id = id(request.transaction_id),
        parent_transaction_id = parent,
        recursion_depth = depth,
        source_kind = request.source_kind or "script",
        tags = request.tags or {},
        created_time = GameRules:GetGameTime(),
        attacker = request.attacker,
        victim = request.victim,
        physical_armor_ignore_pct = request.physical_armor_ignore_pct,
    }
    if depth > (config.maximum_recursion_depth or 6) then
        record.blocked = "maximum_recursion_depth"
    end
    transactions[record.transaction_id] = record
    active_count = active_count + 1
    return record
end

function M.get(transaction_id)
    if not transaction_id then return nil end
    local key = tostring(transaction_id)
    local record = transactions[key] or recent[key]
    if record and record.expires_at and record.expires_at <= GameRules:GetGameTime() then return nil end
    return record
end

function M.mark_submitted(record)
    if not record then return end
    record.submitted_time = GameRules:GetGameTime()
    pending[#pending + 1] = record
end

function M.finish(record)
    if not record or transactions[record.transaction_id] ~= record then return end
    transactions[record.transaction_id], active_count = nil, active_count - 1
    -- A zero/blocked/throwing native ApplyDamage may never invoke the filter.
    -- Remove that request so a later hit cannot consume its bonuses or flags.
    for index, value in ipairs(pending) do
        if value == record then table.remove(pending, index); break end
    end
    -- Only IDs and recursion depth survive completion, never entities/tags.
    -- Replay/parent history is explicitly limited to 10 s and 8,192 entries.
    local entry = {transaction_id=record.transaction_id,
        recursion_depth=record.recursion_depth, expires_at=GameRules:GetGameTime()+HISTORY_SECONDS}
    recent[entry.transaction_id], recent_count = entry, recent_count + 1
    tail = tail + 1
    expiry_queue[tail] = entry
    prune()
end

function M.consume_pending(attacker, victim)
    for index, record in ipairs(pending) do
        if record.attacker == attacker and record.victim == victim then
            table.remove(pending, index)
            return record
        end
    end
    return nil
end

function M.remove(transaction_id)
    local record = transactions[transaction_id]
    if record then
        transactions[transaction_id], active_count = nil, active_count - 1
        for index, value in ipairs(pending) do
            if value == record then table.remove(pending, index); break end
        end
    end
    if recent[transaction_id] then recent[transaction_id], recent_count = nil, recent_count - 1 end
end

function M.count()
    prune()
    return active_count + recent_count
end

function M.debug_snapshot()
    prune()
    return {active_records=active_count, recent_records=recent_count,
        pending_records=#pending, history_limit=HISTORY_LIMIT, history_seconds=HISTORY_SECONDS}
end

return M
