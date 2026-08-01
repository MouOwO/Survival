local event_bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local scheduler = require("core/scheduler")
local definitions = require("config/hero_passive_skill_definitions")
local skill_definitions = require("config/generated/hero_skill_definitions")
local buff_manager = require("systems/buff_manager")

local M = {}
local processed_attacks = {}
local effect_sequence = 0
local refresh_tokens = {}
local active_arcane_barrages = {}
local arcane_barrage_sequence = 0

local ARCANE_EXPLOSION_PARTICLE =
    "particles/basic_explosion/basic_explosion.vpcf"
local ARCANE_MAX_HULL_RADIUS = 256

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit.IsAlive and unit:IsAlive()
end

local function copy_position(position)
    return Vector(position.x, position.y, position.z)
end

local function unit_key(unit)
    if not valid(unit) or not unit.entindex then return nil end
    return tostring(unit:entindex())
end

local function arcane_barrage_locked(attacker_key)
    local active = attacker_key and active_arcane_barrages[attacker_key] or nil
    if not active then return false end
    local current_time = GameRules and GameRules.GetGameTime
        and GameRules:GetGameTime() or 0
    if current_time >= (tonumber(active.unlock_at) or math.huge) then
        active_arcane_barrages[attacker_key] = nil
        return false
    end
    return true
end

local function level_value(definition, field, level, fallback)
    local values = definition[field]
    if type(values) == "table" then
        return tonumber(values[level]) or fallback or 0
    end
    return tonumber(values) or fallback or 0
end

local function owned_passives(player_id)
    local result = event_bus.request(events.HERO_SKILL_STATE_GET_REQUEST, {
        player_id = player_id,
    })
    local owned = {}
    for _, item in ipairs(result and result.snapshot and result.snapshot.skills or {}) do
        if definitions.by_id[item.skill_id] then
            local maximum = definitions.by_id[item.skill_id].max_level or 1
            owned[item.skill_id] = math.max(1, math.min(maximum, tonumber(item.level) or 1))
        end
    end
    return owned
end

local function attribute_snapshot(player_id)
    local result = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
        player_id = player_id,
    })
    local stats = result and result.snapshot or nil
    if not stats then return nil end
    local strength = tonumber(stats.strength) or 0
    local agility = tonumber(stats.agility) or 0
    local intelligence = tonumber(stats.intellect) or 0
    return {
        strength = strength,
        agility = agility,
        intelligence = intelligence,
        all_attributes = strength + agility + intelligence,
    }
end

local function enemies_in_radius(attacker, position, radius)
    if not valid(attacker) or not FindUnitsInRadius then return {} end
    return FindUnitsInRadius(
        attacker:GetTeamNumber(), position, nil, math.max(1, radius),
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false
    ) or {}
end

local function enemies_touching_radius(attacker, position, radius)
    local result = {}
    if not valid(attacker) or not FindUnitsInRadius then return result end
    radius = math.max(1, tonumber(radius) or 1)
    local search_radius = radius + ARCANE_MAX_HULL_RADIUS
    local candidates = FindUnitsInRadius(
        attacker:GetTeamNumber(), position, nil, search_radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false
    ) or {}
    for _, enemy in ipairs(candidates) do
        if alive(enemy) then
            local enemy_position = enemy:GetAbsOrigin()
            local dx = enemy_position.x - position.x
            local dy = enemy_position.y - position.y
            local hull_radius = enemy.GetHullRadius
                and math.max(0, tonumber(enemy:GetHullRadius()) or 0) or 0
            local hit_radius = radius + hull_radius
            if dx * dx + dy * dy <= hit_radius * hit_radius then
                result[#result + 1] = enemy
            end
        end
    end
    return result
end

local function unit_position(unit)
    return valid(unit) and unit:GetAbsOrigin() or nil
end

local function normalized_direction(origin, destination, fallback)
    local delta = destination - origin
    delta.z = 0
    if delta:Length2D() <= 0.01 then return fallback end
    return delta:Normalized()
end

local function line_targets(attacker, origin, direction, length, width)
    local result = {}
    local center = origin + direction * (length * 0.5)
    for _, enemy in ipairs(enemies_in_radius(attacker, center, length * 0.6 + width)) do
        local offset = enemy:GetAbsOrigin() - origin
        offset.z = 0
        local along = offset.x * direction.x + offset.y * direction.y
        local perpendicular = math.abs(offset.x * direction.y - offset.y * direction.x)
        if along >= 0 and along <= length and perpendicular <= width * 0.5 then
            result[#result + 1] = enemy
        end
    end
    return result
end

local function cone_targets(attacker, origin, direction, distance, angle)
    local result = {}
    local cosine = math.cos(math.rad(angle * 0.5))
    for _, enemy in ipairs(enemies_in_radius(attacker, origin, distance)) do
        local offset = enemy:GetAbsOrigin() - origin
        offset.z = 0
        local length = offset:Length2D()
        if length > 0.01 then
            local dot = (offset.x * direction.x + offset.y * direction.y) / length
            if dot >= cosine then
                result[#result + 1] = { unit = enemy, direction_dot = dot }
            end
        end
    end
    return result
end

local function effect_modifiers(target)
    if not valid(target) or not target.FindAllModifiersByName then return {} end
    return target:FindAllModifiersByName("modifier_hero_passive_skill_effect") or {}
end

local function vulnerability_pct(target)
    local maximum = 0
    for _, modifier in ipairs(effect_modifiers(target)) do
        if not modifier:IsNull() and modifier.effect_type == "skill_vulnerability" then
            maximum = math.max(maximum, tonumber(modifier.effect_value) or 0)
        end
    end
    return maximum
end

local function apply_effect(attacker, target, effect_type, value, duration, skill_id)
    if not alive(target) then return nil end
    for _, modifier in ipairs(effect_modifiers(target)) do
        if not modifier:IsNull()
            and modifier.effect_type == effect_type
            and modifier.source_skill_id == skill_id then
            modifier:Configure({
                effect_type = effect_type,
                effect_value = math.max(
                    math.abs(tonumber(modifier.effect_value) or 0),
                    math.abs(tonumber(value) or 0)
                ),
                source_skill_id = skill_id,
            })
            modifier:SetDuration(math.max(0.01, tonumber(duration) or 0.01), true)
            return modifier
        end
    end
    return target:AddNewModifier(attacker, nil, "modifier_hero_passive_skill_effect", {
        duration = math.max(0.01, tonumber(duration) or 0.01),
        effect_type = effect_type,
        effect_value = tonumber(value) or 0,
        source_skill_id = skill_id,
    })
end

local function stun(attacker, target, duration)
    if alive(target) then
        target:AddNewModifier(attacker, nil, "modifier_stunned", {
            duration = math.max(0.01, tonumber(duration) or 0.01),
        })
    end
end

local function effect_payload(context, target, multiplier, secondary)
    return {
        player_id = context.player_id,
        attacker = context.attacker,
        target = target,
        source_skill_id = context.skill_id,
        source_attack_id = context.attack_id,
        skill_level = context.level,
        attribute_snapshot = context.attributes,
        damage_multiplier = multiplier,
        is_secondary_effect = secondary == true,
    }
end

local function deal(context, target, multiplier, secondary)
    if not alive(target) then return nil end
    effect_sequence = effect_sequence + 1
    local metadata = effect_payload(context, target, multiplier, secondary)
    local event_name = secondary
        and events.HERO_PASSIVE_SKILL_SECONDARY_EFFECT_REQUESTED
        or events.HERO_PASSIVE_SKILL_EFFECT_REQUESTED
    event_bus.emit(event_name, metadata)
    local base_damage = context.attributes.all_attributes * math.max(0, multiplier)
    local skill_definition = skill_definitions.by_id[context.skill_id]
    local ability = skill_definition and context.attacker:FindAbilityByName(
        skill_definition.ability_name
    ) or nil
    return event_bus.request(combat_events.DEAL_REQUEST, {
        transaction_id = string.format(
            "passive:%s:%s:%d",
            context.attack_id, context.skill_id, effect_sequence
        ),
        attacker = context.attacker,
        victim = target,
        ability = ability,
        source_kind = secondary and "dot" or "ability",
        base_damage = base_damage,
        damage_type = DAMAGE_TYPE_PURE,
        can_crit = false,
        post_damage_bonus_pct = vulnerability_pct(target) / 100,
        tags = {
            hero_passive_skill = true,
            source_skill_id = context.skill_id,
            source_attack_id = context.attack_id,
            is_secondary_effect = secondary == true,
            attribute_snapshot = context.attributes,
        },
    })
end

local function deal_group(context, targets, multiplier, secondary)
    local hit = 0
    for _, target in ipairs(targets or {}) do
        if alive(target) then
            deal(context, target, multiplier, secondary)
            hit = hit + 1
        end
    end
    return hit
end

local function periodic_on_target(context, target, duration, interval, multiplier, finish, refresh_existing)
    local ticks = math.max(1, math.floor(duration / interval + 0.001))
    local key = tostring(context.player_id) .. ":" .. context.skill_id
        .. ":" .. tostring(target:entindex())
    if not refresh_existing then key = key .. ":" .. tostring(context.attack_id) end
    refresh_tokens[key] = refresh_existing and ((refresh_tokens[key] or 0) + 1) or 1
    local token = refresh_tokens[key]
    for tick = 1, ticks do
        scheduler.after(interval * tick, function()
            if refresh_tokens[key] ~= token then return end
            if alive(target) then deal(context, target, multiplier, true) end
            if tick == ticks and finish then finish(target) end
        end)
    end
end

local function periodic_area(context, position, radius, duration, interval, multiplier, on_tick)
    local ticks = math.max(1, math.floor(duration / interval + 0.001))
    for tick = 1, ticks do
        scheduler.after(interval * tick, function()
            local targets = enemies_in_radius(context.attacker, position, radius)
            deal_group(context, targets, multiplier, true)
            if on_tick then on_tick(targets) end
        end)
    end
end

local function run_flame(context, definition)
    local center = unit_position(context.target)
    if not center then return end
    local targets = enemies_in_radius(context.attacker, center, level_value(definition, "radius", context.level))
    deal_group(context, targets, definition.damage_multiplier[context.level], false)
    if context.level >= 2 then
        local effect = definition.level_effects[context.level]
        for _, target in ipairs(targets) do
            periodic_on_target(context, target, effect.duration, effect.interval, effect.dot_multiplier,
                context.level == 3 and function(unit)
                    local position = unit_position(unit)
                    if position then
                        deal_group(context, enemies_in_radius(context.attacker, position,
                            level_value(definition, "radius", context.level)), effect.secondary_multiplier, true)
                    end
                end or nil)
        end
    end
end

local function run_frost(context, definition)
    local center = unit_position(context.target)
    if not center then return end
    local targets = enemies_in_radius(context.attacker, center, level_value(definition, "radius", context.level))
    deal_group(context, targets, definition.damage_multiplier[context.level], false)
    if context.level == 2 then
        for _, unit in ipairs(targets) do apply_effect(context.attacker, unit, "move_slow", 30, 2, context.skill_id) end
    elseif context.level == 3 then
        for _, unit in ipairs(targets) do
            stun(context.attacker, unit, 1)
            scheduler.after(1, function()
                apply_effect(context.attacker, unit, "move_slow", 45, 3, context.skill_id)
            end)
        end
    end
end

local function run_chain(context, definition)
    local primary = context.target
    if not alive(primary) then return end
    local radius = level_value(definition, "radius", context.level)
    local strike_count = math.max(1, math.floor(level_value(definition, "strike_count", context.level)))
    local base_multiplier = level_value(definition, "damage_multiplier", context.level)
    local splash_multiplier = level_value(definition, "splash_multiplier", context.level)
    local mark_duration = level_value(definition, "mark_duration", context.level)
    local mark_bonus = level_value(definition, "mark_bonus_multiplier", context.level)
    local mark_reduction = level_value(definition, "mark_attack_reduction_pct", context.level)
    local nearby = enemies_in_radius(context.attacker, primary:GetAbsOrigin(), radius)
    local strike_targets = { primary }
    for _, candidate in ipairs(nearby) do
        if #strike_targets >= strike_count then break end
        if candidate ~= primary and alive(candidate) then
            strike_targets[#strike_targets + 1] = candidate
        end
    end
    while #strike_targets < strike_count do strike_targets[#strike_targets + 1] = primary end
    local target_hit_counts = {}

    local function execute_strike(target, strike_multiplier)
        if not alive(target) or not valid(context.attacker) then return end
        local position = unit_position(target)
        if not position then return end
        local particle = ParticleManager:CreateParticle(
            "particles/units/heroes/hero_zuus/zuus_lightning_bolt.vpcf",
            PATTACH_WORLDORIGIN, context.attacker
        )
        ParticleManager:SetParticleControl(particle, 0, position + Vector(0, 0, 900))
        ParticleManager:SetParticleControl(particle, 1, position)
        ParticleManager:ReleaseParticleIndex(particle)

        local was_marked = context.level >= 2
            and buff_manager.has(target, "debuff_hero_fury_thunder_mark")
        deal(context, target, strike_multiplier, false)
        if was_marked and mark_bonus > 0 then deal(context, target, mark_bonus, true) end
        for _, splash_target in ipairs(enemies_in_radius(context.attacker, position, radius)) do
            if splash_target ~= target and alive(splash_target) then
                local splash_marked = context.level >= 2
                    and buff_manager.has(splash_target, "debuff_hero_fury_thunder_mark")
                deal(context, splash_target, strike_multiplier * splash_multiplier, true)
                if splash_marked and mark_bonus > 0 then
                    deal(context, splash_target, mark_bonus, true)
                end
                if context.level >= 2 then
                    buff_manager.apply(
                        context.attacker, splash_target,
                        "debuff_hero_fury_thunder_mark",
                        { duration = mark_duration, value = -math.abs(mark_reduction) }
                    )
                end
            end
        end
        if context.level >= 2 then
            buff_manager.apply(
                context.attacker, target, "debuff_hero_fury_thunder_mark",
                { duration = mark_duration, value = -math.abs(mark_reduction) }
            )
        end
    end

    for strike = 1, strike_count do
        local target = strike_targets[strike]
        local target_key = tostring(target:entindex())
        local prior_hits = target_hit_counts[target_key] or 0
        target_hit_counts[target_key] = prior_hits + 1
        local repeated = prior_hits > 0
        local strike_multiplier = base_multiplier * (repeated and 0.5 or 1)
        if strike == 1 then
            execute_strike(target, strike_multiplier)
        else
            scheduler.after(0.12 * (strike - 1), function()
                execute_strike(target, strike_multiplier)
            end)
        end
    end
end

local function run_poison(context, definition)
    local position = unit_position(context.target)
    if not position then return end
    position = copy_position(position)
    local effect = definition.level_effects[context.level]
    periodic_area(context, position, level_value(definition, "radius", context.level),
        level_value(definition, "duration", context.level),
        level_value(definition, "interval", context.level),
        definition.damage_multiplier[context.level], context.level >= 2 and function(targets)
            local keep = math.max(1.1, tonumber(effect.linger_duration) or 0)
            for _, unit in ipairs(targets) do
                apply_effect(context.attacker, unit, "attack_slow", effect.attack_slow_pct, keep, context.skill_id)
            end
        end or nil)
end

local function run_blade(context, definition)
    local targets = enemies_in_radius(context.attacker, context.attacker:GetAbsOrigin(),
        level_value(definition, "radius", context.level))
    deal_group(context, targets, definition.damage_multiplier[context.level], false)
    if context.level >= 2 then
        local effect = definition.level_effects[context.level]
        for _, target in ipairs(targets) do
            periodic_on_target(context, target, effect.duration, effect.interval,
                effect.dot_multiplier, nil, context.level == 3)
        end
    end
end

local function run_earth(context, definition)
    local origin = copy_position(context.attacker:GetAbsOrigin())
    local target_position = unit_position(context.target) or origin + context.attacker:GetForwardVector() * 100
    local direction = normalized_direction(origin, target_position, context.attacker:GetForwardVector())
    local length = level_value(definition, "length", context.level)
    local width = level_value(definition, "width", context.level)
    local targets = line_targets(context.attacker, origin, direction, length, width)
    deal_group(context, targets, definition.damage_multiplier[context.level], false)
    if context.level >= 2 then
        for _, unit in ipairs(targets) do
            stun(context.attacker, unit, definition.level_effects[context.level].stun_duration)
        end
    end
    if context.level == 3 then
        local effect = definition.level_effects[3]
        scheduler.after(effect.secondary_delay, function()
            deal_group(context, line_targets(context.attacker, origin, direction, length, width),
                effect.secondary_multiplier, true)
        end)
    end
end

local function run_meteor(context, definition)
    local position = unit_position(context.target)
    if not position then return end
    position = copy_position(position)
    scheduler.after(level_value(definition, "delay", context.level), function()
        local radius = level_value(definition, "radius", context.level)
        local targets = enemies_in_radius(context.attacker, position, radius)
        deal_group(context, targets, definition.damage_multiplier[context.level], true)
        if context.level == 3 then
            local effect = definition.level_effects[3]
            for _, unit in ipairs(enemies_in_radius(context.attacker, position, radius * effect.center_radius_pct)) do
                stun(context.attacker, unit, effect.stun_duration)
            end
        end
        if context.level >= 2 then
            local effect = definition.level_effects[context.level]
            periodic_area(context, position, radius, effect.duration, effect.interval, effect.dot_multiplier)
        end
    end)
end

local function run_arcane(context, definition)
    local position = unit_position(context.target)
    local attacker_key = unit_key(context.attacker)
    if not position or not attacker_key or arcane_barrage_locked(attacker_key) then
        return false
    end
    position = copy_position(position)

    local landing_radius = level_value(definition, "landing_radius", context.level)
    local missile_count = math.max(1, math.floor(
        level_value(definition, "missile_count", context.level) + 0.001
    ))
    local explosion_radius = level_value(definition, "explosion_radius", context.level)
    local barrage_count = math.max(1, math.floor(
        level_value(definition, "barrage_count", context.level) + 0.001
    ))
    local barrage_interval = level_value(definition, "barrage_interval", context.level)
    local missile_window = level_value(definition, "missile_window", context.level)
    local damage_multiplier = level_value(definition, "damage_multiplier", context.level)
    local total_missiles = missile_count * barrage_count
    local cast_duration = (barrage_count - 1) * barrage_interval + missile_window
    local current_time = GameRules and GameRules.GetGameTime
        and GameRules:GetGameTime() or 0

    arcane_barrage_sequence = arcane_barrage_sequence + 1
    local token = arcane_barrage_sequence
    active_arcane_barrages[attacker_key] = {
        token = token,
        remaining_missiles = total_missiles,
        unlock_at = current_time + cast_duration + 0.25,
    }

    local function random_landing_position()
        local angle = RandomFloat(0, math.pi * 2)
        local distance = math.sqrt(RandomFloat(0, 1)) * landing_radius
        local landing_position = position + Vector(
            math.cos(angle) * distance,
            math.sin(angle) * distance,
            0
        )
        if GetGroundPosition then
            landing_position = GetGroundPosition(landing_position, nil)
        end
        return landing_position
    end

    local function finish_missile()
        local active = active_arcane_barrages[attacker_key]
        if not active or active.token ~= token then return end
        active.remaining_missiles = active.remaining_missiles - 1
        if active.remaining_missiles <= 0 then
            active_arcane_barrages[attacker_key] = nil
        end
    end

    local function impact(landing_position)
        if valid(context.attacker) then
            local visual_ok, visual_error = pcall(function()
                local explosion = ParticleManager:CreateParticle(
                    ARCANE_EXPLOSION_PARTICLE,
                    PATTACH_WORLDORIGIN,
                    context.attacker
                )
                ParticleManager:SetParticleControl(explosion, 0, landing_position)
                ParticleManager:SetParticleControl(
                    explosion, 1, Vector(explosion_radius, 0, 0)
                )
                ParticleManager:ReleaseParticleIndex(explosion)
            end)
            if not visual_ok then
                print("[HeroPassiveSkill] arcane barrage explosion failed: "
                    .. tostring(visual_error))
            end

            local damage_ok, damage_error = pcall(function()
                deal_group(
                    context,
                    enemies_touching_radius(
                        context.attacker,
                        landing_position,
                        explosion_radius
                    ),
                    damage_multiplier,
                    false
                )
            end)
            if not damage_ok then
                print("[HeroPassiveSkill] arcane barrage damage failed: "
                    .. tostring(damage_error))
            end
        end
        finish_missile()
    end

    local impacts = {}
    for barrage = 1, barrage_count do
        local barrage_delay = (barrage - 1) * barrage_interval
        for missile = 1, missile_count do
            local missile_delay = (missile / missile_count) * missile_window
            local impact_delay = barrage_delay + missile_delay
            impacts[#impacts + 1] = {
                delay = impact_delay,
                position = random_landing_position(),
            }
        end
    end
    table.sort(impacts, function(a, b) return a.delay < b.delay end)
    local next_impact = 1
    local function run_next_impact()
        local current = impacts[next_impact]
        if not current then return false end
        impact(current.position)
        next_impact = next_impact + 1
        local following = impacts[next_impact]
        if not following then return false end
        local now = GameRules and GameRules.GetGameTime
            and GameRules:GetGameTime() or current_time
        return math.max(0, current_time + following.delay - now)
    end
    scheduler.after(impacts[1].delay, run_next_impact)
    scheduler.after(cast_duration + 0.5, function()
        local active = active_arcane_barrages[attacker_key]
        if active and active.token == token then
            active_arcane_barrages[attacker_key] = nil
            print("[HeroPassiveSkill] arcane barrage lock released by failsafe")
        end
    end)
    return true
end

local function run_shadow(context, definition)
    local position = context.target_position
    local targets = enemies_in_radius(context.attacker, position,
        level_value(definition, "radius", context.level))
    local hit = deal_group(context, targets, definition.damage_multiplier[context.level], false)
    if context.level >= 2 then
        local effect = definition.level_effects[context.level]
        for _, unit in ipairs(targets) do
            apply_effect(context.attacker, unit, "move_slow", effect.move_slow_pct, effect.duration, context.skill_id)
        end
        if context.level == 3 and hit >= effect.minimum_targets then
            deal_group(context, targets, effect.secondary_multiplier, true)
        end
    end
end

local function run_holy(context, definition)
    local position = copy_position(context.attacker:GetAbsOrigin())
    local radius = level_value(definition, "radius", context.level)
    local targets = enemies_in_radius(context.attacker, position, radius)
    deal_group(context, targets, definition.damage_multiplier[context.level], false)
    if context.level >= 2 then
        local effect = definition.level_effects[context.level]
        for _, unit in ipairs(targets) do
            apply_effect(context.attacker, unit, "attack_slow", effect.attack_slow_pct, effect.duration, context.skill_id)
        end
        if context.level == 3 then
            scheduler.after(effect.secondary_delay, function()
                deal_group(context, enemies_in_radius(context.attacker, position, radius),
                    effect.secondary_multiplier, true)
            end)
        end
    end
end

local function run_ice_cone(context, definition)
    local origin = copy_position(context.attacker:GetAbsOrigin())
    local destination = unit_position(context.target) or origin + context.attacker:GetForwardVector() * 100
    local direction = normalized_direction(origin, destination, context.attacker:GetForwardVector())
    local angle = level_value(definition, "angle", context.level)
    local entries = cone_targets(context.attacker, origin, direction,
        level_value(definition, "distance", context.level), angle)
    for _, entry in ipairs(entries) do deal(context, entry.unit, definition.damage_multiplier[context.level], false) end
    if context.level == 2 then
        for _, entry in ipairs(entries) do apply_effect(context.attacker, entry.unit, "move_slow", 30, 2, context.skill_id) end
    elseif context.level == 3 then
        local effect = definition.level_effects[3]
        local center_cosine = math.cos(math.rad(angle * effect.center_angle_pct * 0.5))
        for _, entry in ipairs(entries) do
            if entry.direction_dot >= center_cosine then
                stun(context.attacker, entry.unit, effect.freeze_duration)
            else
                apply_effect(context.attacker, entry.unit, "move_slow",
                    effect.move_slow_pct, effect.duration, context.skill_id)
            end
        end
    end
end

local function run_void(context, definition)
    local position = unit_position(context.target)
    if not position then return end
    position = copy_position(position)
    local radius = level_value(definition, "radius", context.level)
    local center_radius = radius * level_value(definition, "center_radius_pct", context.level)
    for _, unit in ipairs(enemies_in_radius(context.attacker, position, radius)) do
        local multiplier = definition.damage_multiplier[context.level]
        if (unit:GetAbsOrigin() - position):Length2D() <= center_radius then
            multiplier = multiplier * (1 + level_value(definition, "center_bonus_pct", context.level))
        end
        deal(context, unit, multiplier, false)
        if context.level >= 2 then
            local effect = definition.level_effects[context.level]
            apply_effect(context.attacker, unit, "attack_slow", effect.attack_slow_pct, effect.duration, context.skill_id)
        end
    end
    if context.level == 3 then
        local effect = definition.level_effects[3]
        scheduler.after(effect.secondary_delay, function()
            deal_group(context, enemies_in_radius(context.attacker, position, center_radius),
                effect.secondary_multiplier, true)
        end)
    end
end

local runners = {
    proto_flame_burst = run_flame,
    proto_frost_nova = run_frost,
    proto_chain_lightning = run_chain,
    proto_poison_cloud = run_poison,
    proto_blade_nova = run_blade,
    proto_earth_line = run_earth,
    proto_meteor = run_meteor,
    proto_arcane_barrage = run_arcane,
    proto_shadow_blast = run_shadow,
    proto_holy_pulse = run_holy,
    proto_ice_cone = run_ice_cone,
    proto_void_pulse = run_void,
}

local function trigger(payload, skill_id, level, attributes, target_position)
    local definition = definitions.by_id[skill_id]
    local runner = runners[skill_id]
    if not definition or not runner then return false end
    local context = {
        player_id = payload.player_id,
        attacker = payload.attacker,
        target = payload.target,
        target_position = target_position,
        attack_id = payload.attack_id,
        skill_id = skill_id,
        level = level,
        attributes = attributes,
    }
    event_bus.emit(events.HERO_PASSIVE_SKILL_TRIGGERED, {
        player_id = payload.player_id,
        attacker = payload.attacker,
        target = payload.target,
        attack_id = payload.attack_id,
        source_attack_id = payload.attack_id,
        skill_id = skill_id,
        level = level,
        attribute_snapshot = attributes,
        is_secondary_effect = false,
    })
    return runner(context, definition) ~= false
end

local function roll(payload, skill_id, level, attributes, target_position)
    local definition = definitions.by_id[skill_id]
    if not definition then return false end
    if skill_id == "proto_arcane_barrage" then
        local attacker_key = unit_key(payload.attacker)
        if arcane_barrage_locked(attacker_key) then return false end
    end
    local chance = definition.trigger_chance[level]
    event_bus.emit(events.HERO_PASSIVE_SKILL_ROLL_REQUESTED, {
        player_id = payload.player_id,
        attack_id = payload.attack_id,
        skill_id = skill_id,
        level = level,
        trigger_chance = chance,
    })
    if RandomFloat(0, 1) >= chance then return false end
    return trigger(payload, skill_id, level, attributes, target_position)
end

local function on_main_attack(payload)
    if payload.is_multishot_secondary == true or payload.is_main_attack == false then return end
    if not alive(payload.attacker) or not valid(payload.target) then return end
    local attack_id = tostring(payload.attack_id or "")
    if attack_id == "" or processed_attacks[attack_id] then return end
    processed_attacks[attack_id] = true
    scheduler.after(10, function() processed_attacks[attack_id] = nil end)

    local owned = owned_passives(tonumber(payload.player_id))
    local attributes = attribute_snapshot(tonumber(payload.player_id))
    if not attributes then return end
    for _, definition in ipairs(definitions.rows) do
        local level = owned[definition.skill_id]
        if level and definition.trigger_type == "main_attack_landed" then
            roll(payload, definition.skill_id, level, attributes)
        end
    end

    local shadow_level = owned.proto_shadow_blast
    if shadow_level and payload.target_was_killed == true then
        roll(payload, "proto_shadow_blast", shadow_level, attributes,
            copy_position(payload.target:GetAbsOrigin()))
    end
end

function M.init()
    definitions.validate()
    processed_attacks = {}
    refresh_tokens = {}
    active_arcane_barrages = {}
    arcane_barrage_sequence = 0
    effect_sequence = 0
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_main_attack)
end

M._test = {
    attribute_snapshot = attribute_snapshot,
    vulnerability_pct = vulnerability_pct,
    enemies_touching_radius = enemies_touching_radius,
    active_arcane_barrages = function() return active_arcane_barrages end,
    runners = runners,
}

return M