local M = {}
local event_bus, events, context, rules, repository, adapter, debug = nil

local function chance(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function blocked(request, transaction, reason)
    local result = { success = false, transaction_id = transaction.transaction_id,
        requested_damage = request.base_damage, calculated_damage = 0,
        damage_type = request.damage_type, critical = false, critical_multiplier = 1,
        blocked_reason = reason, trace = { recursion_depth = transaction.recursion_depth } }
    event_bus.emit(events.DAMAGE_BLOCKED, result)
    debug.log(result)
    return result
end

function M.init(deps)
    event_bus, events, context, rules, repository, adapter, debug = deps.event_bus, deps.events, deps.context, deps.rules, deps.repository, deps.adapter, deps.debug
end

function M:Deal(request)
    local valid, reason = context.validate(request)
    if not valid then
        local fake = repository.create({ source_kind = request and request.source_kind or "script" })
        return blocked(request or { base_damage = 0, damage_type = DAMAGE_TYPE_PURE }, fake, reason)
    end
    local transaction = repository.create(request)
    if transaction.blocked then return blocked(request, transaction, transaction.blocked) end
    transaction.attacker = request.attacker
    transaction.victim = request.victim
    local rule = rules.source_kind_rules[request.source_kind] or {}
    local pre = context.number(request.pre_damage_bonus_pct)
    local fixed = context.number(request.fixed_damage_bonus)
    local damage = (request.base_damage + fixed) * (1 + pre)
    local critical = false
    local critical_multiplier = context.number(request.crit_multiplier, 1)
    if request.can_crit and rule.can_crit ~= false and chance(request.crit_chance) > 0
        and RandomFloat(0, 1) < chance(request.crit_chance) then
        critical = true
        damage = damage * critical_multiplier
    end
    transaction.post_damage_bonus_pct = context.number(request.post_damage_bonus_pct)
    transaction.target_post_reduction_pct = context.number(request.target_post_reduction_pct)
    local result = { success = true, transaction_id = transaction.transaction_id,
        requested_damage = request.base_damage, calculated_damage = damage,
        damage_type = request.damage_type, critical = critical,
        critical_multiplier = critical_multiplier, blocked_reason = nil,
        attacker = request.attacker:entindex(), victim = request.victim:entindex(),
        source_kind = request.source_kind, base_damage = request.base_damage,
        pre_bonus_pct = pre, submitted_damage = damage,
        recursion_depth = transaction.recursion_depth,
        trace = { base_damage = request.base_damage, fixed_damage_bonus = fixed,
            pre_damage_bonus_pct = pre } }
    event_bus.emit(events.DAMAGE_REQUESTED, request)
    event_bus.emit(events.DAMAGE_CALCULATED, result)
    repository.mark_submitted(transaction)
    local applied = adapter:Apply({ attacker = request.attacker, victim = request.victim,
        ability = request.ability, damage = damage, damage_type = request.damage_type,
        damage_flags = request.damage_flags })
    if not applied.ok then return blocked(request, transaction, applied.error) end
    result.engine_damage = transaction.engine_damage
    result.post_multiplier = transaction.post_multiplier
    result.final_damage = transaction.final_damage
    result.trace.engine_damage = transaction.engine_damage
    result.trace.post_multiplier = transaction.post_multiplier
    result.trace.final_damage = transaction.final_damage
    event_bus.emit(events.DAMAGE_SUBMITTED, result)
    debug.log(result)
    return result
end

return M
