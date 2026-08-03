local M = {}
local tree_damage_rules = require("systems/tree_damage_rules")
local event_bus = nil
local events = nil
local repository = nil
local config = nil
local registered = false
local diagnostic_count_by_attacker = {}
local tree_diagnostic_count = 0

local function diagnostic_hero(attacker)
    local hero_id = tostring(attacker and attacker.survival_hero_id or "")
    return hero_id == "hero_slark" or hero_id == "hero_blademaster"
end

local function should_diagnose(attacker)
    if not diagnostic_hero(attacker) then return false end
    local entindex = attacker:entindex()
    local count = tonumber(diagnostic_count_by_attacker[entindex]) or 0
    if count >= 20 then return false end
    diagnostic_count_by_attacker[entindex] = count + 1
    return true
end

local function valid(entity)
    return entity and not entity:IsNull()
end

local function resolve_combatants(keys)
    local attacker_index = tonumber(
        keys.entindex_attacker_const or keys.entindex_attacker
    )
    local victim_index = tonumber(
        keys.entindex_victim_const or keys.entindex_victim
    )
    if not attacker_index or not victim_index then return nil, nil end
    return EntIndexToHScript(attacker_index), EntIndexToHScript(victim_index)
end

local function filter(_, keys)
    -- Damage always flows from attacker to the engine-provided victim. Never
    -- swap these entities based on team or unit type; this game has no implicit
    -- reflection rule. Equipment auras submit their own independent damage.
    local attacker, victim = resolve_combatants(keys)
    if not valid(attacker) or not valid(victim) then return false end
    local diagnostic = should_diagnose(attacker)
    if diagnostic then
        print(string.format(
            "[HERO_DAMAGE_FILTER] hero=%s attacker=%s victim=%s incoming=%s "
                .. "type=%s category=%s inflictor=%s",
            tostring(attacker.survival_hero_id),
            tostring(attacker:entindex()),
            tostring(victim:entindex()),
            tostring(keys.damage),
            tostring(keys.damagetype_const or keys.damagetype),
            tostring(keys.damage_category_const or keys.damage_category),
            tostring(keys.entindex_inflictor_const
                or keys.entindex_inflictor or -1)
        ))
    end
    local record = repository.consume_pending(attacker, victim)
    local transaction_id = record and record.transaction_id or nil
    if record and record.blocked then
        event_bus.emit(events.DAMAGE_BLOCKED, { transaction_id = transaction_id, reason = record.blocked })
        return false
    end
    local damage_category = keys.damage_category_const or keys.damage_category
    local inflictor_index = tonumber(
        keys.entindex_inflictor_const or keys.entindex_inflictor
    )
    local category_is_unknown = damage_category == nil
        or tonumber(damage_category) == 0
    local attack_evidence = false
    if tree_damage_rules.is_tree(victim)
        and not tree_damage_rules.is_arrow_tower(attacker)
        and (tree_damage_rules.is_basic_attack_category(damage_category)
            or category_is_unknown)
        and (not inflictor_index or inflictor_index <= 0) then
        attack_evidence = tree_damage_rules.consume_basic_attack(attacker, victim)
    end
    if not tree_damage_rules.allows_damage(
            attacker, victim, damage_category, attack_evidence) then
        if tree_damage_rules.is_tree(victim) and tree_diagnostic_count < 20 then
            tree_diagnostic_count = tree_diagnostic_count + 1
            print(string.format(
                "[TREE_DAMAGE_FILTER] allow=false attacker=%s name=%s category=%s "
                    .. "inflictor=%s evidence=%s damage=%s",
                tostring(attacker:entindex()),
                tostring(attacker.GetUnitName and attacker:GetUnitName() or "unknown"),
                tostring(damage_category),
                tostring(inflictor_index),
                tostring(attack_evidence),
                tostring(keys.damage)
            ))
        end
        event_bus.emit(events.DAMAGE_BLOCKED, {
            transaction_id = transaction_id,
            reason = "tree_requires_basic_attack",
        })
        return false
    end
    if tree_damage_rules.is_tree(victim) and tree_diagnostic_count < 20 then
        tree_diagnostic_count = tree_diagnostic_count + 1
        print(string.format(
            "[TREE_DAMAGE_FILTER] allow=true attacker=%s name=%s category=%s "
                .. "inflictor=%s evidence=%s damage=%s",
            tostring(attacker:entindex()),
            tostring(attacker.GetUnitName and attacker:GetUnitName() or "unknown"),
            tostring(damage_category),
            tostring(inflictor_index),
            tostring(attack_evidence),
            tostring(keys.damage)
        ))
    end
    if victim.survival_damage_blocked == true
        or (victim.IsInvulnerable and victim:IsInvulnerable()) then
        if tree_damage_rules.is_tree(victim) and tree_diagnostic_count < 20 then
            tree_diagnostic_count = tree_diagnostic_count + 1
            print(string.format(
                "[TREE_DAMAGE_FILTER] allow=false reason=damage_blocked "
                    .. "survival_blocked=%s invulnerable=%s",
                tostring(victim.survival_damage_blocked == true),
                tostring(victim.IsInvulnerable and victim:IsInvulnerable() or false)
            ))
        end
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
    local seven_sins_bonus = math.max(
        0,
        tonumber(attacker.survival_seven_sins_final_damage_pct) or 0
    ) / 100
    local target_reduction = record and tonumber(record.target_post_reduction_pct) or 0
    local boss_multiplier = 1
    if config.boss_rules.enabled and victim:HasModifier("modifier_boss") then
        boss_multiplier = config.boss_rules.default_damage_taken_multiplier
    end
    local multiplier = math.max(config.minimum_post_multiplier,
        1 + source_bonus + global_bonus + research_bonus + seven_sins_bonus
            - target_reduction)
        * boss_multiplier
    keys.damage = math.max(0, keys.damage * multiplier)
    if diagnostic then
        print(string.format(
            "[HERO_DAMAGE_FILTER_RESULT] hero=%s attacker=%s victim=%s "
                .. "multiplier=%s final=%s",
            tostring(attacker.survival_hero_id),
            tostring(attacker:entindex()),
            tostring(victim:entindex()),
            tostring(multiplier),
            tostring(keys.damage)
        ))
    end
    local payload = {
        transaction_id = transaction_id, engine_damage = keys.damage,
        attacker_entindex = attacker:entindex(),
        victim_entindex = victim:entindex(),
        post_multiplier = multiplier,
        research_bonus_pct = research_bonus,
        seven_sins_bonus_pct = seven_sins_bonus,
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
    diagnostic_count_by_attacker = {}
    tree_diagnostic_count = 0
    tree_damage_rules.reset_pending_attacks()
end

function M.register()
    if registered then return true end
    local mode = GameRules:GetGameModeEntity()
    if not mode or not mode.SetDamageFilter then return false end
    mode:SetDamageFilter(filter, M)
    registered = true
    return true
end

M._filter_for_test = filter

return M
