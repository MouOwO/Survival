local M = {}
local event_bus = nil
local events = nil
local repository = nil
local config = nil
local registered = false

local function valid(entity)
    return entity and not entity:IsNull()
end

local function filter(_, keys)
    local attacker_index = keys.entindex_attacker_const or keys.entindex_attacker
    local victim_index = keys.entindex_victim_const or keys.entindex_victim
    local attacker = attacker_index and EntIndexToHScript(attacker_index) or nil
    local victim = victim_index and EntIndexToHScript(victim_index) or nil
    if not valid(attacker) or not valid(victim) then return false end
    local record = repository.consume_pending(attacker, victim)
    local transaction_id = record and record.transaction_id or nil
    if record and record.blocked then
        event_bus.emit(events.DAMAGE_BLOCKED, { transaction_id = transaction_id, reason = record.blocked })
        return false
    end
    if victim.survival_damage_blocked == true
        or (victim.IsInvulnerable and victim:IsInvulnerable()) then
        event_bus.emit(events.DAMAGE_BLOCKED, {
            transaction_id = transaction_id, reason = "damage_blocked",
        })
        return false
    end
    local source_bonus = record and tonumber(record.post_damage_bonus_pct) or 0
    local global_bonus = tonumber(config.global_post_bonus_pct) or 0
    local research_bonus = math.max(
        0,
        tonumber(attacker.survival_research_final_damage_pct) or 0
    ) / 100
    local target_reduction = record and tonumber(record.target_post_reduction_pct) or 0
    local boss_multiplier = 1
    if config.boss_rules.enabled and victim:HasModifier("modifier_boss") then
        boss_multiplier = config.boss_rules.default_damage_taken_multiplier
    end
    local multiplier = math.max(config.minimum_post_multiplier,
        1 + source_bonus + global_bonus + research_bonus - target_reduction)
        * boss_multiplier
    keys.damage = math.max(0, keys.damage * multiplier)
    local payload = {
        transaction_id = transaction_id, engine_damage = keys.damage,
        post_multiplier = multiplier,
        research_bonus_pct = research_bonus,
        final_damage = keys.damage, recursion_depth = record and record.recursion_depth or 0,
    }
    if record then
        record.engine_damage = payload.engine_damage
        record.post_multiplier = payload.post_multiplier
        record.final_damage = payload.final_damage
    end
    event_bus.emit(events.DAMAGE_FILTERED, payload)
    event_bus.emit(events.DAMAGE_RESOLVED, payload)
    return true
end

function M.init(deps)
    event_bus, events, repository, config = deps.event_bus, deps.events, deps.repository, deps.config
    registered = false
end

function M.register()
    if registered then return true end
    local mode = GameRules:GetGameModeEntity()
    if not mode or not mode.SetDamageFilter then return false end
    mode:SetDamageFilter(filter, M)
    registered = true
    return true
end

return M
