local M = {}
local config = nil
local transactions = {}
local pending = {}

local function id(value)
    if value and tostring(value) ~= "" then return tostring(value) end
    return string.format("damage:%d:%d", GameRules:GetGameTime() * 1000, RandomInt(1, 999999))
end

function M.init(rule_config)
    config = rule_config
    transactions = {}
    pending = {}
end

function M.create(request)
    request = request or {}
    if request.transaction_id and transactions[tostring(request.transaction_id)] then
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
    local parent = request.parent_transaction_id
    local parent_record = parent and transactions[parent] or nil
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
    }
    if depth > (config.maximum_recursion_depth or 6) then
        record.blocked = "maximum_recursion_depth"
    end
    transactions[record.transaction_id] = record
    return record
end

function M.get(transaction_id)
    return transaction_id and transactions[transaction_id] or nil
end

function M.mark_submitted(record)
    if not record then return end
    record.submitted_time = GameRules:GetGameTime()
    pending[#pending + 1] = record
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
    transactions[transaction_id] = nil
end

function M.count()
    local count = 0
    for _ in pairs(transactions) do count = count + 1 end
    return count
end

return M
