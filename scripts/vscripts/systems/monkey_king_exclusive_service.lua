local event_bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local scheduler = require("core/scheduler")
local config = require("config/generated/monkey_king_exclusive_runtime")

local M = {}
M.sound_service = require("core/sound_service")

local Q_SKILL = "skill_monkey_king_exclusive"
local W_SKILL = "skill_monkey_king_fury"
local E_SKILL = "skill_monkey_king_swiftness"
local Q_ABILITY = "ability_survival_monkey_king_exclusive"
local E_ABILITY = "ability_survival_monkey_king_swiftness"
local BOUNDLESS_PARTICLE =
    "particles/units/heroes/hero_monkey_king/monkey_king_strike.vpcf"
local STAFF_DROP_PARTICLE =
    "particles/survival_monkey_king/survival_monkey_king_staff_drop.vpcf"
local STAFF_DROP_HEIGHT = 1000
local STAFF_DROP_DURATION = 0.28
local STAFF_DROP_INITIAL_SPEED = 350

local q_health_hits_by_player = {}
local q_impacts = {}
local q_impact_sequence = 0
local state_by_player = {}
local wall_by_player = {}
local damage_sequence = 0

local function runtime()
    return config.by_id.monkey_king_exclusive or {}
end

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit.IsAlive and unit:IsAlive()
end

local function skill_active(player_id, skill_id)
    local result = event_bus.request(events.HERO_SKILL_STATE_GET_REQUEST, {
        player_id = player_id,
    })
    for _, skill in ipairs(result and result.snapshot
            and result.snapshot.skills or {}) do
        if skill.skill_id == skill_id then
            return skill.locked ~= 1 and (tonumber(skill.level) or 0) > 0
        end
    end
    return false
end

local function combat_snapshot(player_id)
    local result = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
        player_id = player_id,
    })
    return result and result.snapshot or {}
end

local function state(player_id)
    local result = state_by_player[player_id]
    if result then return result end
    result = {
        player_id = player_id,
        strength = 0,
        agility = 0,
        intellect = 0,
        clone = nil,
        clone_respawning = false,
        growth_started = false,
    }
    state_by_player[player_id] = result
    return result
end

local function bonus_snapshot(player_id)
    local current = state(player_id)
    return {
        strength = current.strength,
        agility = current.agility,
        intellect = current.intellect,
    }
end

local function all_attributes(player_id)
    local stats = combat_snapshot(player_id)
    return math.max(0, tonumber(stats.strength) or 0)
        + math.max(0, tonumber(stats.agility) or 0)
        + math.max(0, tonumber(stats.intellect) or 0)
end

local function normalized_direction(origin, destination, attacker)
    local delta = destination - origin
    delta.z = 0
    if delta:Length2D() > 0.01 then return delta:Normalized() end
    local forward = attacker:GetForwardVector()
    forward.z = 0
    return forward:Length2D() > 0.01 and forward:Normalized()
        or Vector(1, 0, 0)
end

local function line_targets(attacker, origin, direction, length, total_width)
    local result = {}
    local center = origin + direction * (length * 0.5)
    local candidates = FindUnitsInRadius(
        attacker:GetTeamNumber(), center, nil,
        length * 0.5 + total_width,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false
    )
    for _, enemy in ipairs(candidates or {}) do
        if alive(enemy) then
            local offset = enemy:GetAbsOrigin() - origin
            offset.z = 0
            local along = offset.x * direction.x + offset.y * direction.y
            local perpendicular = math.abs(
                offset.x * direction.y - offset.y * direction.x
            )
            local hull = enemy.GetHullRadius
                and math.max(0, tonumber(enemy:GetHullRadius()) or 0) or 0
            if along >= -hull and along <= length + hull
                and perpendicular <= total_width * 0.5 + hull then
                result[#result + 1] = enemy
            end
        end
    end
    return result
end

local function ability(attacker, name)
    return valid(attacker) and attacker:FindAbilityByName(name) or nil
end

local function deal(player_id, attacker, victim, ability_name, amount, source)
    damage_sequence = damage_sequence + 1
    return event_bus.request(combat_events.DEAL_REQUEST, {
        transaction_id = string.format(
            "monkey_king:%s:%d:%d", source, player_id, damage_sequence
        ),
        attacker = attacker,
        victim = victim,
        ability = ability(attacker, ability_name),
        source_kind = "ability",
        base_damage = math.max(0, tonumber(amount) or 0),
        damage_type = DAMAGE_TYPE_PURE,
        can_crit = false,
        tags = {
            monkey_king_exclusive = true,
            source = source,
            player_id = player_id,
        },
    })
end

local function play_boundless_visual(attacker, origin, endpoint, direction)
    if not ParticleManager or not ParticleManager.CreateParticle then return false end
    local particle = nil
    local visual_ok = pcall(function()
        local visual_origin = GetGroundPosition
            and GetGroundPosition(origin, attacker) or origin
        local visual_endpoint = GetGroundPosition
            and GetGroundPosition(endpoint, attacker) or endpoint
        particle = ParticleManager:CreateParticle(
            BOUNDLESS_PARTICLE, PATTACH_WORLDORIGIN, attacker
        )
        ParticleManager:SetParticleControl(particle, 0, visual_origin)
        ParticleManager:SetParticleControlForward(particle, 0, direction)
        ParticleManager:SetParticleControl(particle, 1, visual_endpoint)
        ParticleManager:SetParticleControl(particle, 2, visual_endpoint)
        ParticleManager:ReleaseParticleIndex(particle)
    end)
    if visual_ok then return true end
    if particle ~= nil then
        if ParticleManager.DestroyParticle then
            pcall(function()
                ParticleManager:DestroyParticle(particle, true)
            end)
        end
        if ParticleManager.ReleaseParticleIndex then
            pcall(function()
                ParticleManager:ReleaseParticleIndex(particle)
            end)
        end
    end
    return false
end

local function destroy_particle(particle)
    if particle == nil or not ParticleManager then return end
    if ParticleManager.DestroyParticle then
        pcall(function()
            ParticleManager:DestroyParticle(particle, true)
        end)
    end
    if ParticleManager.ReleaseParticleIndex then
        pcall(function()
            ParticleManager:ReleaseParticleIndex(particle)
        end)
    end
end

local function play_staff_drop(attacker, origin, direction, length)
    if not ParticleManager or not ParticleManager.CreateParticle then return nil end
    local particle = nil
    local visual_ok = pcall(function()
        local center = origin + direction * (length * 0.5)
        local ground_center = GetGroundPosition
            and GetGroundPosition(center, attacker) or center
        local start_position = ground_center + Vector(0, 0, STAFF_DROP_HEIGHT)
        particle = ParticleManager:CreateParticle(
            STAFF_DROP_PARTICLE, PATTACH_WORLDORIGIN, attacker
        )
        ParticleManager:SetParticleControl(particle, 0, start_position)
        ParticleManager:SetParticleControlForward(particle, 0, direction)
        ParticleManager:SetParticleControl(
            particle, 1, start_position + direction * length
        )
        ParticleManager:SetParticleControl(
            particle, 2,
            Vector(0, 0, -STAFF_DROP_INITIAL_SPEED)
        )
    end)
    if visual_ok then return particle end
    destroy_particle(particle)
    return nil
end

local function health_hit_count(player_id, target)
    q_health_hits_by_player[player_id] = q_health_hits_by_player[player_id] or {}
    return q_health_hits_by_player[player_id], tostring(target:entindex())
end

local function resolve_q_impact(impact_id)
    local impact = q_impacts[impact_id]
    if not impact then return false end
    q_impacts[impact_id] = nil
    impact.task = nil
    destroy_particle(impact.drop_particle)
    impact.drop_particle = nil

    if not valid(impact.attacker) then return false end
    play_boundless_visual(
        impact.attacker, impact.origin, impact.endpoint, impact.direction
    )
    local impact_position = impact.origin
        + impact.direction * (impact.length * 0.5)
    if GetGroundPosition then
        impact_position = GetGroundPosition(impact_position, impact.attacker)
    end
    M.sound_service.play("hero_monkey_boundless_impact", {
        source = impact.attacker,
        position = impact_position,
    })
    for _, enemy in ipairs(line_targets(
            impact.attacker, impact.origin, impact.direction,
            impact.length, impact.total_width)) do
        local counts, key = health_hit_count(impact.player_id, enemy)
        local count = tonumber(counts[key]) or 0
        local health_damage = 0
        if count < impact.health_hit_limit then
            health_damage = math.max(0, tonumber(enemy:GetMaxHealth()) or 0)
                * impact.max_health_pct / 100
            counts[key] = count + 1
        end
        local result = deal(
            impact.player_id, impact.attacker, enemy, Q_ABILITY,
            impact.attribute_damage + health_damage, "q"
        )
        if health_damage > 0 and (not result or result.success ~= true) then
            counts[key] = count
        end
    end
    return false
end

local function clear_q_impacts()
    local impact_ids = {}
    for impact_id, _ in pairs(q_impacts) do
        impact_ids[#impact_ids + 1] = impact_id
    end
    for _, impact_id in ipairs(impact_ids) do
        local impact = q_impacts[impact_id]
        q_impacts[impact_id] = nil
        if impact then
            if impact.task then scheduler.cancel(impact.task) end
            destroy_particle(impact.drop_particle)
        end
    end
end

local function trigger_q(player_id, attacker, target)
    if not alive(attacker) or not alive(target) then return false end
    local row = runtime()
    local chance = math.max(0, math.min(100,
        tonumber(row.q_proc_chance_pct) or 0))
    if chance <= 0 or not RollPercentage(chance) then return false end

    local origin = attacker:GetAbsOrigin()
    local direction = normalized_direction(
        origin, target:GetAbsOrigin(), attacker
    )
    local length = math.max(0, tonumber(row.q_length) or 0)
    local total_width = math.max(0, tonumber(row.q_total_width) or 0)
    local attribute_damage = all_attributes(player_id)
        * math.max(0, tonumber(row.q_attribute_multiplier) or 0)
    local limit = math.max(0,
        math.floor(tonumber(row.q_max_health_hit_limit) or 0))
    q_impact_sequence = q_impact_sequence + 1
    local impact_id = q_impact_sequence
    local impact = {
        player_id = player_id,
        attacker = attacker,
        origin = origin,
        direction = direction,
        endpoint = origin + direction * length,
        length = length,
        total_width = total_width,
        attribute_damage = attribute_damage,
        max_health_pct = math.max(0,
            tonumber(row.q_max_health_pct) or 0),
        health_hit_limit = limit,
        drop_particle = play_staff_drop(attacker, origin, direction, length),
        task = nil,
    }
    q_impacts[impact_id] = impact
    impact.task = scheduler.after(STAFF_DROP_DURATION, function()
        return resolve_q_impact(impact_id)
    end, "monkey_q_impact_" .. tostring(impact_id))
    M.sound_service.play("hero_monkey_boundless_cast", {
        unit = attacker,
        source = attacker,
    })
    return true
end

local function trigger_e(payload)
    if payload.critical ~= true then return false end
    local row = runtime()
    local damage = all_attributes(payload.player_id)
        * math.max(0, tonumber(row.e_attribute_multiplier) or 0)
    local result, request_error = deal(
        payload.player_id, payload.attacker, payload.target,
        E_ABILITY, damage, "e")
    if not result or result.success ~= true then
        print(string.format(
            "[MONKEY_KING_E_DAMAGE_FAILED] player=%s record=%s damage=%s error=%s",
            tostring(payload.player_id), tostring(payload.record),
            tostring(damage), tostring(
                result and result.blocked_reason or request_error or "no_result"
            )
        ))
        return false
    end
    return true
end

local function on_main_attack_landed(payload)
    local attacker = payload and payload.attacker
    if not alive(attacker)
        or attacker.survival_hero_id ~= "hero_monkey_king"
        or payload.is_main_attack ~= true then return end
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    if skill_active(player_id, Q_SKILL) then
        trigger_q(player_id, attacker, payload.target)
    end
end

local function on_final_critical_attack_damage(payload)
    local attacker = payload and payload.attacker
    if not alive(attacker)
        or attacker.survival_hero_id ~= "hero_monkey_king"
        or attacker.survival_monkey_king_clone == true
        or payload.is_main_attack ~= true then return end
    local player_id = tonumber(payload.player_id)
    if player_id == nil or not skill_active(player_id, E_SKILL) then return end
    trigger_e(payload)
end

local function clone_position(player_id, hero)
    local wall = wall_by_player[player_id]
    local anchor = valid(wall) and wall or hero
    local position = anchor:GetAbsOrigin() + RandomVector(128)
    return GetGroundPosition and GetGroundPosition(position, anchor) or position
end

local function remove_unwanted_clone_abilities(clone)
    local names = {}
    for index = 0, math.max(0, clone:GetAbilityCount() - 1) do
        local clone_ability = clone:GetAbilityByIndex(index)
        if clone_ability and not clone_ability:IsNull()
            and clone_ability:GetAbilityName() ~= Q_ABILITY then
            names[#names + 1] = clone_ability:GetAbilityName()
        end
    end
    for _, name in ipairs(names) do clone:RemoveAbility(name) end
    local q = clone:FindAbilityByName(Q_ABILITY) or clone:AddAbility(Q_ABILITY)
    if q then
        q:SetLevel(1)
        q:SetActivated(true)
        q:SetHidden(false)
    end
end

local function sync_clone(current, hero)
    local clone = current.clone
    if not alive(clone) or not alive(hero) then return end
    local stats = combat_snapshot(current.player_id)
    local previous_max = math.max(1, tonumber(clone:GetMaxHealth()) or 1)
    local health_pct = math.max(0, tonumber(clone:GetHealth()) or 0) / previous_max
    local maximum = math.max(1, tonumber(stats.max_health) or 1)
    local health_modifier = clone:FindModifierByName(
        "modifier_survival_hero_base_health"
    )
    local old_health_bonus = health_modifier
        and tonumber(health_modifier:GetStackCount()) or 0
    local native_maximum = math.max(1, previous_max - old_health_bonus)
    local health_bonus = math.max(0, math.floor(maximum - native_maximum))
    health_modifier = clone:AddNewModifier(
        clone, nil, "modifier_survival_hero_base_health",
        { health_bonus = health_bonus }
    ) or health_modifier
    if health_modifier and health_modifier.SetHealthBonus then
        health_modifier:SetHealthBonus(health_bonus)
    end
    if clone.CalculateStatBonus then clone:CalculateStatBonus(true) end
    local projected_maximum = math.max(1, tonumber(clone:GetMaxHealth()) or maximum)
    clone:SetHealth(math.max(1, math.min(
        projected_maximum, projected_maximum * health_pct
    )))
    clone:SetBaseDamageMin(math.max(0,
        tonumber(stats.engine_attack_min) or tonumber(stats.attack_min) or 0))
    clone:SetBaseDamageMax(math.max(0,
        tonumber(stats.engine_attack_max) or tonumber(stats.attack_max) or 0))
    local attack_speed = tonumber(stats.attack_speed) or 0
    if attack_speed > 0 then
        clone:SetBaseAttackTime(1 / attack_speed)
    end
    clone.survival_attack_speed = attack_speed
    clone.survival_strength = tonumber(stats.strength) or 0
    clone.survival_agility = tonumber(stats.agility) or 0
    clone.survival_intellect = tonumber(stats.intellect) or 0
    clone.survival_combat_refresh_version = tonumber(stats.refresh_version) or 0
    local clone_modifier = clone:FindModifierByName("modifier_monkey_king_clone")
    if clone_modifier and clone_modifier.SetCombatSnapshot then
        clone_modifier:SetCombatSnapshot(stats)
    end
    if clone.CalculateStatBonus then clone:CalculateStatBonus(true) end
end

local function create_clone(player_id)
    local current = state(player_id)
    if alive(current.clone) then return current.clone end
    local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
        player_id = player_id,
    })
    local hero = summoned and summoned.unit
    if not alive(hero) or hero.survival_hero_id ~= "hero_monkey_king"
        or not skill_active(player_id, W_SKILL) then return nil end
    local clone = CreateUnitByName(
        hero:GetUnitName(), clone_position(player_id, hero), true,
        hero, hero, hero:GetTeamNumber()
    )
    if not valid(clone) then return nil end
    if clone.SetPlayerID then clone:SetPlayerID(player_id) end
    local player = PlayerResource:GetPlayer(player_id)
    if player and clone.SetOwner then clone:SetOwner(player) end
    clone:SetControllableByPlayer(player_id, true)
    clone.survival_monkey_king_clone = true
    clone.survival_display_name = "混沌神猿分身"
    if clone.SetBaseStrength then clone:SetBaseStrength(0) end
    if clone.SetBaseAgility then clone:SetBaseAgility(0) end
    if clone.SetBaseIntellect then clone:SetBaseIntellect(0) end
    if clone.CalculateStatBonus then clone:CalculateStatBonus(true) end
    remove_unwanted_clone_abilities(clone)
    clone:AddNewModifier(clone, nil, "modifier_monkey_king_clone", {
        player_id = player_id,
    })
    current.clone = clone
    current.clone_respawning = false
    sync_clone(current, hero)
    FindClearSpaceForUnit(clone, clone:GetAbsOrigin(), true)
    return clone
end

local function schedule_clone_respawn(player_id)
    local current = state(player_id)
    if current.clone_respawning then return end
    current.clone_respawning = true
    local delay = math.max(0,
        tonumber(runtime().w_clone_respawn_delay) or 1)
    scheduler.after(delay, function()
        current.clone_respawning = false
        create_clone(player_id)
    end, "monkey_clone_respawn:" .. tostring(player_id))
end

local function growth_tick(player_id)
    if not skill_active(player_id, W_SKILL) then return end
    local stats = combat_snapshot(player_id)
    local current = state(player_id)
    local pct = math.max(0, tonumber(runtime().w_growth_pct) or 0) / 100
    current.strength = current.strength + math.max(0,
        (tonumber(stats.strength) or 0) - current.strength) * pct
    current.agility = current.agility + math.max(0,
        (tonumber(stats.agility) or 0) - current.agility) * pct
    current.intellect = current.intellect + math.max(0,
        (tonumber(stats.intellect) or 0) - current.intellect) * pct
    event_bus.emit(events.MONKEY_KING_BONUS_STATS_CHANGED, {
        player_id = player_id,
        snapshot = bonus_snapshot(player_id),
        reason = "monkey_king_w_growth",
    })
end

local function start_player_runtime(player_id)
    if not skill_active(player_id, W_SKILL) then return end
    local current = state(player_id)
    create_clone(player_id)
    if current.growth_started then return end
    current.growth_started = true
    local interval = math.max(0.1,
        tonumber(runtime().w_growth_interval) or 60)
    scheduler.every(interval, function()
        growth_tick(player_id)
        return true
    end, "monkey_growth:" .. tostring(player_id))
end

local function on_skill_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id ~= nil then start_player_runtime(player_id) end
end

local function on_building(payload)
    if payload and payload.building_id == "wall"
        and payload.player_id ~= nil and valid(payload.unit) then
        wall_by_player[tonumber(payload.player_id)] = payload.unit
    end
end

local function on_building_destroyed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if payload and payload.building_id == "wall" and player_id ~= nil
        and wall_by_player[player_id] == payload.unit then
        wall_by_player[player_id] = nil
    end
end

local function on_entity_killed(payload)
    local victim = payload and payload.victim
    if not valid(victim) or victim.survival_monkey_king_clone ~= true then return end
    local player_id = tonumber(victim:GetPlayerOwnerID())
    if player_id == nil then return end
    state(player_id).clone = nil
    if skill_active(player_id, W_SKILL) then schedule_clone_respawn(player_id) end
end

local function sync_all_clones()
    for player_id, current in pairs(state_by_player) do
        local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
            player_id = player_id,
        })
        if alive(current.clone) and summoned then
            sync_clone(current, summoned.unit)
        elseif current.clone == nil and skill_active(player_id, W_SKILL)
            and not current.clone_respawning then
            create_clone(player_id)
        end
    end
end

function M.init()
    clear_q_impacts()
    q_health_hits_by_player = {}
    q_impacts = {}
    q_impact_sequence = 0
    state_by_player = {}
    wall_by_player = {}
    damage_sequence = 0
    event_bus.handle_request(events.MONKEY_KING_BONUS_STATS_GET_REQUEST,
        function(payload)
            return { ok = true, snapshot = bonus_snapshot(tonumber(payload.player_id)) }
        end)
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_main_attack_landed)
    event_bus.subscribe(events.HERO_FINAL_CRITICAL_ATTACK_DAMAGE,
        on_final_critical_attack_damage)
    event_bus.subscribe(events.HERO_SKILL_CHANGED, on_skill_changed)
    event_bus.subscribe(events.BUILDING_CREATED, on_building)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    scheduler.every(0.1, sync_all_clones, "monkey_clone_sync")
end

function M.trigger_clone_q(player_id, attacker, target)
    if not skill_active(player_id, Q_SKILL) then return false end
    return trigger_q(player_id, attacker, target)
end
M._test = {
    line_targets = line_targets,
    play_boundless_visual = play_boundless_visual,
    play_staff_drop = play_staff_drop,
    resolve_q_impact = resolve_q_impact,
    trigger_q = trigger_q,
    health_hits = function() return q_health_hits_by_player end,
    trigger_e = trigger_e,
    on_final_critical_attack_damage = on_final_critical_attack_damage,
    impacts = function() return q_impacts end,
}

return M
