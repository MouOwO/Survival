local M = {}
local pending_attacks = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

local function now()
    if GameRules and GameRules.GetGameTime then
        return GameRules:GetGameTime()
    end
    return 0
end

local function entity_index(unit)
    if not valid(unit) or not unit.entindex then return nil end
    return tonumber(unit:entindex())
end

local function attack_indices(attacker, victim)
    local attacker_index = entity_index(attacker)
    local victim_index = entity_index(victim)
    if not attacker_index or not victim_index then return nil end
    return attacker_index, victim_index
end

function M.is_tree(unit)
    return valid(unit) and unit.GetUnitName
        and unit:GetUnitName() == "enemy_tree"
end

function M.is_arrow_tower(unit)
    if not valid(unit) then return false end
    local building_id = tostring(unit.survival_building_id or "")
    -- Ultimate towers retain their own business identity while sharing the
    -- stationary tower order/target restrictions. Names cover creation before
    -- Lua identity fields have been applied to the new entity.
    if building_id == "arrow_tower" or building_id == "ultimate_tower"
        or unit.survival_ultimate_tower == true then return true end
    local unit_name = unit.GetUnitName and unit:GetUnitName() or ""
    return unit_name == "building_arrow_tower"
        or unit_name == "npc_dota_unit_ultimate_tower"
end

function M.is_lumberjack(unit)
    return valid(unit) and unit.GetUnitName
        and unit:GetUnitName() == "npc_survival_lumberjack"
end

function M.is_real_hero(unit)
    if not valid(unit) or not unit.IsRealHero or not unit:IsRealHero() then
        return false
    end
    return not unit.IsIllusion or not unit:IsIllusion()
end

function M.is_allowed_tree_attacker(unit)
    if not valid(unit) or M.is_arrow_tower(unit)
        or unit.survival_is_building == true
        or unit.survival_is_native_wearable_visual == true
        or unit.survival_is_native_wearable == true then
        return false
    end
    -- A native hero used only to display a tower skin is not a gameplay hero,
    -- even when the engine reports IsRealHero().
    return M.is_lumberjack(unit) or M.is_real_hero(unit)
end

function M.is_basic_attack_category(category)
    return DOTA_DAMAGE_CATEGORY_ATTACK ~= nil
        and tonumber(category) == tonumber(DOTA_DAMAGE_CATEGORY_ATTACK)
end

local function prune_entries(entries, current, record_key, clear_all)
    local write = 1
    for _, entry in ipairs(entries) do
        if entry.expires_at >= current and not clear_all
            and (record_key == nil or entry.record ~= record_key) then
            entries[write] = entry
            write = write + 1
        end
    end
    for index = #entries, write, -1 do entries[index] = nil end
end

function M.mark_basic_attack(attacker, victim, record)
    if not M.is_allowed_tree_attacker(attacker) or not M.is_tree(victim) then
        return false
    end
    local attacker_index, victim_index = attack_indices(attacker, victim)
    if not attacker_index then return false end
    local bucket = pending_attacks[attacker_index]
    if not bucket or bucket.attacker ~= attacker then
        bucket = { attacker = attacker, victims = {} }
        pending_attacks[attacker_index] = bucket
    end
    local queue = bucket.victims[victim_index]
    if not queue or queue.victim ~= victim then
        queue = { attacker_index = attacker_index, victim_index = victim_index,
            victim = victim, entries = {} }
        bucket.victims[victim_index] = queue
    end
    -- Canceled starts may never reach the damage filter. Keep only this
    -- attacker's current target window, even when the start omitted a record.
    local current = now()
    prune_entries(queue.entries, current)
    queue.entries[#queue.entries + 1] = {
        record = record ~= nil and tostring(record) or nil,
        expires_at = current + 3,
    }
    -- The queue is also a cleanup token. Its cached indices remain usable after
    -- either engine handle is invalid; identity checks reject reused indices.
    return true, queue
end

local function current_queue(attacker, victim)
    local attacker_index, victim_index = attack_indices(attacker, victim)
    local bucket = attacker_index and pending_attacks[attacker_index] or nil
    if not bucket or bucket.attacker ~= attacker then return nil end
    local queue = bucket.victims[victim_index]
    return queue and queue.victim == victim and queue or nil
end

local function detach_empty_queue(queue, bucket)
    if #queue.entries ~= 0 then return end
    bucket.victims[queue.victim_index] = nil
    if next(bucket.victims) == nil then pending_attacks[queue.attacker_index] = nil end
end

function M.consume_basic_attack(attacker, victim)
    local queue = current_queue(attacker, victim)
    if not queue then return false end
    local entries = queue.entries
    local bucket = pending_attacks[queue.attacker_index]
    local current = now()
    while #entries > 0 and entries[1].expires_at < current do
        table.remove(entries, 1)
    end
    if #entries == 0 then
        detach_empty_queue(queue, bucket)
        return false
    end
    table.remove(entries, 1)
    detach_empty_queue(queue, bucket)
    return true
end

function M.clear_basic_attack_token(queue, record)
    if type(queue) ~= "table" then return false end
    local bucket = pending_attacks[queue.attacker_index]
    if not bucket or bucket.victims[queue.victim_index] ~= queue then return false end
    local record_key = record ~= nil and tostring(record) or nil
    local entries = queue.entries
    prune_entries(entries, now(), record_key, record_key == nil)
    detach_empty_queue(queue, bucket)
    return #entries > 0
end

function M.clear_basic_attack(attacker, victim, record)
    if victim then
        return M.clear_basic_attack_token(current_queue(attacker, victim), record)
    end
    local attacker_index = entity_index(attacker)
    local bucket = attacker_index and pending_attacks[attacker_index] or nil
    if not bucket or bucket.attacker ~= attacker then return false end
    -- Legacy callers can omit a victim; only visit this attacker's queues.
    for _, queue in pairs(bucket.victims) do
        M.clear_basic_attack_token(queue, record)
    end
    return next(bucket.victims) ~= nil
end

function M.reset_pending_attacks()
    pending_attacks = {}
end

function M.allows_damage(attacker, victim, damage_category, attack_evidence)
    if not M.is_tree(victim) then return true end
    if not M.is_allowed_tree_attacker(attacker) then return false end
    if M.is_basic_attack_category(damage_category) then return true end
    return attack_evidence == true
end

return M
