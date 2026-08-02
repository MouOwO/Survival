local event_bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local scheduler = require("core/scheduler")
local definitions = require("config/hero_passive_skill_definitions")
local skill_definitions = require("config/generated/hero_skill_definitions")
local hero_definitions = require("config/generated/hero_definitions")
local buff_manager = require("systems/buff_manager")

local M = {}
local processed_attacks = {}
local effect_sequence = 0
local refresh_tokens = {}
local flame_burns = {}
local flame_burn_sequence = 0
local flame_burn_task = nil
local active_arcane_barrages = {}
local arcane_barrage_sequence = 0
local active_ice_cones = {}
local ice_cone_sequence = 0
local active_moving_ice_balls = {}
local moving_ice_ball_sequence = 0
local moving_ice_ball_task = nil
local magic_slingshot_projectiles = {}
local magic_slingshot_projectile_sequence = 0
local magic_slingshot_rubble_fields = {}
local magic_slingshot_rubble_sequence = 0
local magic_slingshot_slowed_units = {}
local magic_slingshot_rubble_task = nil
local magic_slingshot_diagnostics = {}
local active_poison_clouds = {}
local poison_cloud_sequence = 0
local poison_cloud_units = {}
local poison_cloud_deaths = {}
local poison_cloud_task = nil
local blade_pulse_projectiles = {}
local blade_pulse_sequence = 0

local ARCANE_EXPLOSION_PARTICLE =
    "particles/basic_explosion/basic_explosion.vpcf"
local FLAME_MAIN_EXPLOSION_PARTICLE =
    "particles/units/heroes/hero_lina/lina_spell_light_strike_array.vpcf"
local FLAME_SMALL_FIREBALL_PARTICLE =
    "particles/units/heroes/hero_lina/lina_spell_dragon_slave.vpcf"
local FLAME_BURN_PARTICLE =
    "particles/units/heroes/hero_huskar/huskar_burning_spear_debuff.vpcf"
local FLAME_BURN_THINK_INTERVAL = 0.05
local ARCANE_MAX_HULL_RADIUS = 256
local ICE_CONE_SNOW_PARTICLE =
    "particles/econ/items/crystal_maiden/crystal_maiden_maiden_of_icewrack/maiden_freezing_field_snow_arcana1.vpcf"
local ICE_CONE_IMPACT_PARTICLE =
    "particles/econ/items/crystal_maiden/crystal_maiden_maiden_of_icewrack/maiden_freezing_field_explosion_arcana1.vpcf"
local MOVING_ICE_BALL_PARTICLE = "particles/basic_projectile/basic_projectile.vpcf"
local MOVING_ICE_BALL_EXPLOSION_PARTICLE = "particles/basic_projectile/basic_projectile_explosion.vpcf"
local MOVING_ICE_BALL_THINK_INTERVAL = 0.05
local MAGIC_SLINGSHOT_PROJECTILE_PARTICLE =
    "particles/units/heroes/hero_tiny/tiny_base_attack.vpcf"
local MAGIC_SLINGSHOT_RUBBLE_PARTICLE =
    "particles/units/heroes/hero_tiny/tiny_avalanche.vpcf"
local MAGIC_SLINGSHOT_SLOW_BUFF = "debuff_hero_magic_slingshot_move_slow"
local MAGIC_SLINGSHOT_RUBBLE_THINK_INTERVAL = 0.1
local MAGIC_SLINGSHOT_MAX_HULL_RADIUS = 256
local MAGIC_SLINGSHOT_DIAGNOSTIC_ROLL_LIMIT = 30
local POISON_CLOUD_PARTICLE =
    "particles/units/heroes/hero_viper/viper_nethertoxin.vpcf"
local POISON_CLOUD_EXPLOSION_PARTICLE =
    "particles/basic_explosion/basic_explosion.vpcf"
local POISON_CLOUD_ARMOR_MODIFIER = "modifier_hero_poison_cloud_armor"
local POISON_CLOUD_THINK_INTERVAL = 0.05
local BLADE_PULSE_PARTICLE =
    "particles/econ/items/vengeful/vengeful_arcana/vengeful_arcana_wave_of_terror_v2.vpcf"
local BLADE_PULSE_CLEANUP_GRACE = 0.25

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

local function game_time()
    return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
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

local function ice_cone_locked(attacker_key)
    local active = attacker_key and active_ice_cones[attacker_key] or nil
    if not active then return false end
    local current_time = GameRules and GameRules.GetGameTime
        and GameRules:GetGameTime() or 0
    if current_time >= (tonumber(active.unlock_at) or math.huge) then
        if active.snow_particle then
            ParticleManager:DestroyParticle(active.snow_particle, false)
            ParticleManager:ReleaseParticleIndex(active.snow_particle)
        end
        active_ice_cones[attacker_key] = nil
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

local function is_stunned(target)
    if not alive(target) then return false end
    if target.IsStunned and target:IsStunned() then return true end
    return target.HasModifier and target:HasModifier("modifier_stunned") or false
end

local function current_attack_range(attacker)
    if not valid(attacker) then return 0 end
    local maximum = math.max(
        0,
        tonumber(attacker.survival_attack_range) or 0
    )
    for _, method_name in ipairs({ "Script_GetAttackRange", "GetAttackRange" }) do
        local method = attacker[method_name]
        if type(method) == "function" then
            local ok, value = pcall(method, attacker)
            if ok then maximum = math.max(maximum, tonumber(value) or 0) end
        end
    end
    local hero_id = tostring(attacker.survival_hero_id or "")
    local definition = (hero_definitions.by_id or {})[hero_id]
    return math.max(maximum, tonumber(definition and definition.attack_range) or 0)
end

local function is_enemy(attacker, target)
    return alive(target) and valid(attacker)
        and target.GetTeamNumber and attacker.GetTeamNumber
        and target:GetTeamNumber() ~= attacker:GetTeamNumber()
end

local function magic_slingshot_targets(
    attacker, maximum, prefer_unstunned, primary_target
)
    local origin = unit_position(attacker)
    local radius = current_attack_range(attacker)
    if not origin then return {} end
    local candidates = {}
    local seen = {}
    local broad_candidates = radius > 0 and enemies_in_radius(
        attacker, origin, radius + MAGIC_SLINGSHOT_MAX_HULL_RADIUS
    ) or {}
    for _, target in ipairs(broad_candidates) do
        if is_enemy(attacker, target) then
            local position = target:GetAbsOrigin()
            local dx = position.x - origin.x
            local dy = position.y - origin.y
            local hull_radius = target.GetHullRadius
                and math.max(0, tonumber(target:GetHullRadius()) or 0) or 0
            local hit_radius = radius + hull_radius
            local key = unit_key(target)
            if key and dx * dx + dy * dy <= hit_radius * hit_radius then
                seen[key] = true
                candidates[#candidates + 1] = target
            end
        end
    end
    -- A target just hit by a legal main attack must remain eligible even when
    -- the engine's attack reach and a radius query disagree at a hull boundary.
    local primary_key = unit_key(primary_target)
    if primary_key and not seen[primary_key]
        and is_enemy(attacker, primary_target) then
        candidates[#candidates + 1] = primary_target
    end
    table.sort(candidates, function(a, b)
        if prefer_unstunned then
            local a_stunned = is_stunned(a)
            local b_stunned = is_stunned(b)
            if a_stunned ~= b_stunned then return not a_stunned end
        end
        local a_position = a:GetAbsOrigin()
        local b_position = b:GetAbsOrigin()
        local adx, ady = a_position.x - origin.x, a_position.y - origin.y
        local bdx, bdy = b_position.x - origin.x, b_position.y - origin.y
        local a_distance = adx * adx + ady * ady
        local b_distance = bdx * bdx + bdy * bdy
        if a_distance ~= b_distance then return a_distance < b_distance end
        return (tonumber(a:entindex()) or 0) < (tonumber(b:entindex()) or 0)
    end)
    local result = {}
    for _, target in ipairs(candidates) do
        if alive(target) then
            result[#result + 1] = target
            if #result >= maximum then break end
        end
    end
    return result
end

local function point_inside_rubble(position)
    if not position then return false end
    local now = game_time()
    for _, field in pairs(magic_slingshot_rubble_fields) do
        if now < field.expires_at then
            local dx = position.x - field.position.x
            local dy = position.y - field.position.y
            if dx * dx + dy * dy <= field.radius * field.radius then return true end
        end
    end
    return false
end

local function release_rubble_field(field_id)
    local field = magic_slingshot_rubble_fields[field_id]
    if not field then return end
    if field.particle then
        ParticleManager:DestroyParticle(field.particle, false)
        ParticleManager:ReleaseParticleIndex(field.particle)
    end
    magic_slingshot_rubble_fields[field_id] = nil
end

local function clear_magic_slingshot_rubble()
    for field_id, _ in pairs(magic_slingshot_rubble_fields) do
        release_rubble_field(field_id)
    end
    for _, entry in pairs(magic_slingshot_slowed_units) do
        if entry and valid(entry.target) then
            buff_manager.remove(entry.target, MAGIC_SLINGSHOT_SLOW_BUFF)
        end
    end
    magic_slingshot_slowed_units = {}
    if magic_slingshot_rubble_task then
        scheduler.cancel(magic_slingshot_rubble_task)
        magic_slingshot_rubble_task = nil
    end
end

local function sync_magic_slingshot_rubble()
    local now = game_time()
    local inside = {}
    local has_fields = false
    for field_id, field in pairs(magic_slingshot_rubble_fields) do
        if now >= field.expires_at or not valid(field.context.attacker) then
            release_rubble_field(field_id)
        else
            has_fields = true
            for _, target in ipairs(enemies_touching_radius(
                field.context.attacker, field.position, field.radius
            )) do
                local key = unit_key(target)
                if key then
                    local current = inside[key]
                    if not current or field.move_slow_pct > current.move_slow_pct then
                        inside[key] = {
                            target = target,
                            caster = field.context.attacker,
                            move_slow_pct = field.move_slow_pct,
                        }
                    end
                end
            end
        end
    end
    for key, entry in pairs(inside) do
        if not magic_slingshot_slowed_units[key] and alive(entry.target) then
            buff_manager.apply(
                entry.caster, entry.target, MAGIC_SLINGSHOT_SLOW_BUFF,
                { duration = 0, value = -math.abs(entry.move_slow_pct) }
            )
        end
    end
    for key, entry in pairs(magic_slingshot_slowed_units) do
        if not inside[key] and valid(entry.target) then
            buff_manager.remove(entry.target, MAGIC_SLINGSHOT_SLOW_BUFF)
        end
    end
    magic_slingshot_slowed_units = inside
    if not has_fields then
        magic_slingshot_rubble_task = nil
        return false
    end
    return MAGIC_SLINGSHOT_RUBBLE_THINK_INTERVAL
end

local function ensure_magic_slingshot_rubble_task()
    if magic_slingshot_rubble_task then return end
    magic_slingshot_rubble_task = scheduler.after(
        0, sync_magic_slingshot_rubble, "magic_slingshot_rubble_sync"
    )
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

local function poison_cloud_contains(cloud, target, require_alive)
    if not cloud or not valid(target) or not valid(cloud.context.attacker) then
        return false
    end
    if require_alive ~= false and not alive(target) then return false end
    if target.GetTeamNumber and cloud.context.attacker.GetTeamNumber
        and target:GetTeamNumber() == cloud.context.attacker:GetTeamNumber() then
        return false
    end
    local position = unit_position(target)
    if not position then return false end
    local dx = position.x - cloud.position.x
    local dy = position.y - cloud.position.y
    local hull_radius = target.GetHullRadius
        and math.max(0, tonumber(target:GetHullRadius()) or 0) or 0
    local hit_radius = cloud.radius + hull_radius
    return dx * dx + dy * dy <= hit_radius * hit_radius
end

local function poison_cloud_armor_values(target_key)
    local maximum_stacks = 0
    local per_stack_pct = 0
    for _, cloud in pairs(active_poison_clouds) do
        local member = cloud.members[target_key]
        if member and poison_cloud_contains(cloud, member.target, true) then
            local stacks = tonumber(member.stacks) or 0
            local reduction = stacks * cloud.armor_per_stack_pct
            if reduction > maximum_stacks * per_stack_pct then
                maximum_stacks = stacks
                per_stack_pct = cloud.armor_per_stack_pct
            end
        end
    end
    return math.min(3, maximum_stacks), per_stack_pct
end

local function sync_poison_cloud_armor(target_key, target)
    if not valid(target) then
        poison_cloud_units[target_key] = nil
        return
    end
    local stacks, per_stack_pct = poison_cloud_armor_values(target_key)
    local modifier = target.FindModifierByName
        and target:FindModifierByName(POISON_CLOUD_ARMOR_MODIFIER) or nil
    if stacks <= 0 or not alive(target) then
        if modifier and not modifier:IsNull() then modifier:Destroy() end
        poison_cloud_units[target_key] = nil
        return
    end
    if modifier and not modifier:IsNull() then
        if modifier.SetPoisonValues then
            modifier:SetPoisonValues({
                poison_stacks = stacks,
                armor_per_stack_pct = per_stack_pct,
            })
        elseif modifier.SetPoisonStacks then
            modifier:SetPoisonStacks(stacks)
        end
    else
        target:AddNewModifier(target, nil, POISON_CLOUD_ARMOR_MODIFIER, {
            poison_stacks = stacks,
            armor_per_stack_pct = per_stack_pct,
        })
    end
    poison_cloud_units[target_key] = target
end

local function release_poison_cloud(attacker_key)
    local cloud = active_poison_clouds[attacker_key]
    if not cloud then return end
    if cloud.particle then
        ParticleManager:DestroyParticle(cloud.particle, false)
        ParticleManager:ReleaseParticleIndex(cloud.particle)
    end
    active_poison_clouds[attacker_key] = nil
    for target_key, member in pairs(cloud.members) do
        sync_poison_cloud_armor(target_key, member.target)
    end
end

local function clear_poison_clouds()
    local keys = {}
    for attacker_key, _ in pairs(active_poison_clouds) do
        keys[#keys + 1] = attacker_key
    end
    for _, attacker_key in ipairs(keys) do release_poison_cloud(attacker_key) end
    for target_key, target in pairs(poison_cloud_units) do
        if valid(target) then
            local modifier = target.FindModifierByName
                and target:FindModifierByName(POISON_CLOUD_ARMOR_MODIFIER) or nil
            if modifier and not modifier:IsNull() then modifier:Destroy() end
        end
        poison_cloud_units[target_key] = nil
    end
    if poison_cloud_task then
        scheduler.cancel(poison_cloud_task)
        poison_cloud_task = nil
    end
end

local function poison_cloud_damage_tick(cloud)
    local targets = enemies_touching_radius(
        cloud.context.attacker, cloud.position, cloud.radius
    )
    deal_group(cloud.context, targets, cloud.damage_multiplier, true)
    if cloud.armor_per_stack_pct <= 0 then return end
    for _, target in ipairs(targets) do
        if alive(target) then
            local target_key = unit_key(target)
            if target_key then
                local member = cloud.members[target_key] or {
                    target = target,
                    stacks = 0,
                }
                member.target = target
                member.stacks = math.min(
                    cloud.armor_max_stacks,
                    (tonumber(member.stacks) or 0) + 1
                )
                cloud.members[target_key] = member
                sync_poison_cloud_armor(target_key, target)
            end
        end
    end
end

local function sync_poison_clouds()
    local now = game_time()
    local has_active = false
    local armor_targets = {}
    for attacker_key, cloud in pairs(active_poison_clouds) do
        if not valid(cloud.context.attacker) then
            release_poison_cloud(attacker_key)
        else
            while cloud.next_tick <= cloud.total_ticks
                and now + 0.0001 >= cloud.started_at
                    + cloud.next_tick * cloud.interval do
                poison_cloud_damage_tick(cloud)
                cloud.next_tick = cloud.next_tick + 1
            end
            if cloud.next_tick > cloud.total_ticks
                and now + 0.0001 >= cloud.expires_at then
                release_poison_cloud(attacker_key)
            else
                has_active = true
                for target_key, member in pairs(cloud.members) do
                    if poison_cloud_contains(cloud, member.target, true) then
                        armor_targets[target_key] = member.target
                    else
                        cloud.members[target_key] = nil
                        armor_targets[target_key] = member.target
                    end
                end
            end
        end
    end
    for target_key, target in pairs(poison_cloud_units) do
        armor_targets[target_key] = target
    end
    for target_key, target in pairs(armor_targets) do
        sync_poison_cloud_armor(target_key, target)
    end
    if not has_active then
        poison_cloud_task = nil
        return false
    end
    return POISON_CLOUD_THINK_INTERVAL
end

local function ensure_poison_cloud_task()
    if poison_cloud_task then return end
    poison_cloud_task = scheduler.after(
        0, sync_poison_clouds, "poison_cloud_sync"
    )
end

local function create_poison_cloud(context, position, definition)
    local attacker_key = unit_key(context.attacker)
    if not attacker_key then return false end
    release_poison_cloud(attacker_key)
    local radius = level_value(definition, "radius", context.level)
    local duration = level_value(definition, "duration", context.level)
    local interval = level_value(definition, "interval", context.level)
    local started_at = game_time()
    poison_cloud_sequence = poison_cloud_sequence + 1
    local particle = nil
    local visual_ok, visual_error = pcall(function()
        particle = ParticleManager:CreateParticle(
            POISON_CLOUD_PARTICLE, PATTACH_WORLDORIGIN, context.attacker
        )
        ParticleManager:SetParticleControl(particle, 0, position)
        ParticleManager:SetParticleControl(particle, 1, Vector(radius, 0, 0))
    end)
    if not visual_ok then
        particle = nil
        print("[HeroPassiveSkill] poison cloud visual failed: "
            .. tostring(visual_error))
    end
    active_poison_clouds[attacker_key] = {
        id = poison_cloud_sequence,
        context = context,
        position = copy_position(position),
        radius = radius,
        started_at = started_at,
        expires_at = started_at + duration,
        interval = interval,
        total_ticks = math.max(1, math.floor(duration / interval + 0.001)),
        next_tick = 1,
        damage_multiplier = level_value(definition, "damage_multiplier", context.level),
        armor_per_stack_pct = level_value(
            definition, "armor_reduction_per_stack_pct", context.level
        ),
        armor_max_stacks = math.max(1, math.floor(level_value(
            definition, "armor_max_stacks", context.level
        ) + 0.001)),
        death_explosion_radius = level_value(
            definition, "death_explosion_radius", context.level
        ),
        death_explosion_multiplier = level_value(
            definition, "death_explosion_multiplier", context.level
        ),
        members = {},
        particle = particle,
    }
    ensure_poison_cloud_task()
    return true
end

local function poison_cloud_for_death(victim)
    local selected = nil
    for _, cloud in pairs(active_poison_clouds) do
        if cloud.death_explosion_multiplier > 0
            and game_time() <= cloud.expires_at + 0.0001
            and poison_cloud_contains(cloud, victim, false)
            and (not selected or cloud.id > selected.id) then
            selected = cloud
        end
    end
    return selected
end

local function on_poison_cloud_death(payload)
    local victim = payload and payload.victim or nil
    local victim_key = unit_key(victim)
    if not victim_key or poison_cloud_deaths[victim_key] then return end
    local cloud = poison_cloud_for_death(victim)
    if not cloud then return end
    poison_cloud_deaths[victim_key] = true
    scheduler.after(10, function() poison_cloud_deaths[victim_key] = nil end)
    local position = unit_position(victim)
    if not position then return end
    position = copy_position(position)
    local visual_ok, visual_error = pcall(function()
        local particle = ParticleManager:CreateParticle(
            POISON_CLOUD_EXPLOSION_PARTICLE,
            PATTACH_WORLDORIGIN, cloud.context.attacker
        )
        ParticleManager:SetParticleControl(particle, 0, position)
        ParticleManager:SetParticleControl(
            particle, 1, Vector(cloud.death_explosion_radius, 0, 0)
        )
        ParticleManager:ReleaseParticleIndex(particle)
    end)
    if not visual_ok then
        print("[HeroPassiveSkill] poison death explosion visual failed: "
            .. tostring(visual_error))
    end
    deal_group(
        cloud.context,
        enemies_touching_radius(
            cloud.context.attacker, position, cloud.death_explosion_radius
        ),
        cloud.death_explosion_multiplier,
        true
    )
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

local function release_flame_burn(target_key)
    local state = flame_burns[target_key]
    if not state then return end
    if state.particle then
        ParticleManager:DestroyParticle(state.particle, false)
        ParticleManager:ReleaseParticleIndex(state.particle)
    end
    flame_burns[target_key] = nil
end

local function flame_burn_tick_multiplier(layer)
    local ticks = math.max(1, layer.total_ticks)
    if layer.ticks_done + 1 >= ticks then
        return layer.total_multiplier
            - layer.tick_multiplier * (ticks - 1)
    end
    return layer.tick_multiplier
end

local function sync_flame_burns()
    local now = game_time()
    local has_active = false
    for target_key, state in pairs(flame_burns) do
        if not alive(state.target) then
            release_flame_burn(target_key)
        else
            local active_layers = {}
            for _, layer in ipairs(state.layers) do
                while layer.ticks_done < layer.total_ticks
                    and now + 0.0001 >= layer.next_tick_at do
                    deal(
                        layer.context,
                        state.target,
                        flame_burn_tick_multiplier(layer),
                        true
                    )
                    layer.ticks_done = layer.ticks_done + 1
                    layer.next_tick_at = layer.started_at
                        + (layer.ticks_done + 1) * layer.interval
                end
                if layer.ticks_done < layer.total_ticks
                    and now + 0.0001 < layer.expires_at then
                    active_layers[#active_layers + 1] = layer
                end
            end
            state.layers = active_layers
            if #active_layers == 0 then
                release_flame_burn(target_key)
            else
                has_active = true
            end
        end
    end
    if not has_active or next(flame_burns) == nil then
        flame_burn_task = nil
        return false
    end
    return FLAME_BURN_THINK_INTERVAL
end

local function ensure_flame_burn_task()
    if flame_burn_task then return end
    flame_burn_task = scheduler.after(
        FLAME_BURN_THINK_INTERVAL,
        sync_flame_burns,
        "flame_burn_sync"
    )
end

local function clear_flame_burns()
    for target_key, _ in pairs(flame_burns) do
        release_flame_burn(target_key)
    end
    if flame_burn_task then scheduler.cancel(flame_burn_task) end
    flame_burn_task = nil
end

local function add_flame_burn(
    context, target, duration, interval, total_multiplier, max_stacks
)
    if not alive(target) or duration <= 0 or interval <= 0
        or total_multiplier <= 0 or max_stacks <= 0 then
        return false
    end
    local target_key = unit_key(target)
    if not target_key then return false end
    local state = flame_burns[target_key]
    if not state then
        local particle = nil
        local visual_ok, visual_error = pcall(function()
            particle = ParticleManager:CreateParticle(
                FLAME_BURN_PARTICLE,
                PATTACH_ABSORIGIN_FOLLOW,
                target
            )
        end)
        if not visual_ok then
            particle = nil
            print("[HeroPassiveSkill] flame burn visual failed: "
                .. tostring(visual_error))
        end
        state = { target = target, layers = {}, particle = particle }
        flame_burns[target_key] = state
    end

    local now = game_time()
    local total_ticks = math.max(1, math.floor(duration / interval + 0.001))
    flame_burn_sequence = flame_burn_sequence + 1
    local layer = {
        id = flame_burn_sequence,
        context = context,
        started_at = now,
        expires_at = now + duration + 0.001,
        interval = interval,
        next_tick_at = now + interval,
        total_ticks = total_ticks,
        ticks_done = 0,
        total_multiplier = total_multiplier,
        tick_multiplier = total_multiplier / total_ticks,
    }
    if #state.layers >= max_stacks then
        local oldest_index = 1
        for index = 2, #state.layers do
            if state.layers[index].expires_at
                < state.layers[oldest_index].expires_at then
                oldest_index = index
            end
        end
        state.layers[oldest_index] = layer
    else
        state.layers[#state.layers + 1] = layer
    end
    ensure_flame_burn_task()
    return true
end

local function flame_random_landing_position(center, radius)
    local angle = RandomFloat(0, math.pi * 2)
    local distance = math.sqrt(RandomFloat(0, 1)) * radius
    local position = center + Vector(
        math.cos(angle) * distance,
        math.sin(angle) * distance,
        0
    )
    if GetGroundPosition then position = GetGroundPosition(position, nil) end
    return position
end

local function flame_explosion_visual(context, position)
    local visual_ok, visual_error = pcall(function()
        local particle = ParticleManager:CreateParticle(
            FLAME_MAIN_EXPLOSION_PARTICLE,
            PATTACH_WORLDORIGIN,
            context.attacker
        )
        ParticleManager:SetParticleControl(particle, 0, position)
        ParticleManager:ReleaseParticleIndex(particle)
    end)
    if not visual_ok then
        print("[HeroPassiveSkill] flame explosion visual failed: "
            .. tostring(visual_error))
    end
end

local function run_flame(context, definition)
    local center = unit_position(context.target)
    if not center then return false end
    center = copy_position(center)
    if GetGroundPosition then center = GetGroundPosition(center, nil) end

    local radius = level_value(definition, "radius", context.level)
    local burn_duration = level_value(
        definition, "burn_duration", context.level
    )
    local burn_interval = level_value(
        definition, "burn_interval", context.level
    )
    local burn_total_multiplier = level_value(
        definition, "burn_total_multiplier", context.level
    )
    local burn_max_stacks = math.floor(level_value(
        definition, "burn_max_stacks", context.level
    ) + 0.001)
    local function burn_targets(targets)
        for _, target in ipairs(targets) do
            add_flame_burn(
                context, target, burn_duration, burn_interval,
                burn_total_multiplier, burn_max_stacks
            )
        end
    end

    flame_explosion_visual(context, center)
    local main_targets = enemies_touching_radius(
        context.attacker, center, radius
    )
    deal_group(
        context, main_targets,
        level_value(definition, "damage_multiplier", context.level),
        false
    )
    if context.level >= 2 then burn_targets(main_targets) end

    local fireball_count = math.floor(level_value(
        definition, "small_fireball_count", context.level
    ) + 0.001)
    if fireball_count <= 0 then return true end
    local landing_radius = level_value(
        definition, "small_fireball_landing_radius", context.level
    )
    local explosion_radius = level_value(
        definition, "small_fireball_explosion_radius", context.level
    )
    local fireball_multiplier = level_value(
        definition, "small_fireball_damage_multiplier", context.level
    )
    local flight_time = level_value(
        definition, "small_fireball_flight_time", context.level
    )
    local fireballs = {}
    for index = 1, fireball_count do
        local landing_position = flame_random_landing_position(
            center, landing_radius
        )
        local particle = nil
        local visual_ok, visual_error = pcall(function()
            particle = ParticleManager:CreateParticle(
                FLAME_SMALL_FIREBALL_PARTICLE,
                PATTACH_WORLDORIGIN,
                context.attacker
            )
            ParticleManager:SetParticleControl(particle, 0, center)
            ParticleManager:SetParticleControl(particle, 1, landing_position)
        end)
        if not visual_ok then
            particle = nil
            print("[HeroPassiveSkill] small fireball visual failed: "
                .. tostring(visual_error))
        end
        fireballs[index] = {
            position = landing_position,
            particle = particle,
        }
    end
    scheduler.after(flight_time, function()
        for _, fireball in ipairs(fireballs) do
            if fireball.particle then
                ParticleManager:DestroyParticle(fireball.particle, false)
                ParticleManager:ReleaseParticleIndex(fireball.particle)
            end
            flame_explosion_visual(context, fireball.position)
            if valid(context.attacker) then
                local targets = enemies_touching_radius(
                    context.attacker, fireball.position, explosion_radius
                )
                deal_group(context, targets, fireball_multiplier, true)
                burn_targets(targets)
            end
        end
    end)
    return true
end

local function moving_ice_ball_point_segment_distance_sq(point, start_position, end_position)
    local segment_x = end_position.x - start_position.x
    local segment_y = end_position.y - start_position.y
    local point_x = point.x - start_position.x
    local point_y = point.y - start_position.y
    local length_sq = segment_x * segment_x + segment_y * segment_y
    local progress = 0
    if length_sq > 0.0001 then
        progress = math.max(0, math.min(1,
            (point_x * segment_x + point_y * segment_y) / length_sq
        ))
    end
    local dx = point_x - segment_x * progress
    local dy = point_y - segment_y * progress
    return dx * dx + dy * dy
end

local function moving_ice_ball_periodic_multiplier(state)
    local collision_bonus = state.collision_stacks * state.collision_bonus_pct / 100
    local distance_stacks = math.floor(state.distance_travelled / 100 + 0.000000001)
    local distance_bonus = distance_stacks * state.distance_bonus_pct_per_100 / 100
    return state.damage_multiplier * (1 + collision_bonus + distance_bonus)
end

local function moving_ice_ball_random_target(attacker, origin, radius, primary_target)
    local candidates = {}
    local seen = {}
    for _, target in ipairs(enemies_in_radius(attacker, origin, radius)) do
        local key = unit_key(target)
        if key and is_enemy(attacker, target) and not seen[key] then
            seen[key] = true
            candidates[#candidates + 1] = target
        end
    end
    local primary_key = unit_key(primary_target)
    if primary_key and not seen[primary_key] and is_enemy(attacker, primary_target) then
        candidates[#candidates + 1] = primary_target
    end
    if #candidates == 0 then return nil end
    local index = RandomInt and RandomInt(1, #candidates) or math.random(1, #candidates)
    return candidates[index]
end

local function release_moving_ice_ball(ball_id, explode)
    local state = active_moving_ice_balls[ball_id]
    if not state then return end
    if state.particle then
        ParticleManager:DestroyParticle(state.particle, false)
        ParticleManager:ReleaseParticleIndex(state.particle)
    end
    if explode and valid(state.context.attacker) then
        local visual_ok, visual_error = pcall(function()
            local particle = ParticleManager:CreateParticle(
                MOVING_ICE_BALL_EXPLOSION_PARTICLE,
                PATTACH_WORLDORIGIN, state.context.attacker
            )
            ParticleManager:SetParticleControl(particle, 0, state.position)
            ParticleManager:ReleaseParticleIndex(particle)
        end)
        if not visual_ok then
            print("[HeroPassiveSkill] moving ice ball explosion failed: "
                .. tostring(visual_error))
        end
        if state.explosion_multiplier > 0 then
            deal_group(
                state.context,
                enemies_touching_radius(
                    state.context.attacker, state.position, state.radius
                ),
                state.explosion_multiplier,
                true
            )
        end
    end
    active_moving_ice_balls[ball_id] = nil
end

local function moving_ice_ball_collisions(state, start_position, end_position)
    local dx = end_position.x - start_position.x
    local dy = end_position.y - start_position.y
    local step_length = math.sqrt(dx * dx + dy * dy)
    local center = Vector(
        (start_position.x + end_position.x) * 0.5,
        (start_position.y + end_position.y) * 0.5,
        (start_position.z + end_position.z) * 0.5
    )
    local broad_radius = step_length * 0.5 + state.collision_width
        + ARCANE_MAX_HULL_RADIUS
    local reached_target = false
    for _, target in ipairs(enemies_in_radius(
        state.context.attacker, center, broad_radius
    )) do
        if alive(target) then
            local hull_radius = target.GetHullRadius
                and math.max(0, tonumber(target:GetHullRadius()) or 0) or 0
            local hit_radius = state.collision_width + hull_radius
            if moving_ice_ball_point_segment_distance_sq(
                target:GetAbsOrigin(), start_position, end_position
            ) <= hit_radius * hit_radius then
                local key = unit_key(target)
                if key and not state.collided[key] then
                    state.collided[key] = true
                    state.collision_stacks = math.min(
                        state.collision_max_stacks,
                        state.collision_stacks + 1
                    )
                end
                if target == state.target then reached_target = true end
            end
        end
    end
    return reached_target
end

local function sync_moving_ice_balls()
    local now = game_time()
    local has_active = false
    for ball_id, state in pairs(active_moving_ice_balls) do
        if not valid(state.context.attacker) then
            release_moving_ice_ball(ball_id, false)
        else
            has_active = true
            local elapsed = math.max(0, math.min(
                MOVING_ICE_BALL_THINK_INTERVAL * 2,
                now - state.last_update_at
            ))
            state.last_update_at = now

            if state.homing and state.target and not alive(state.target)
                and not state.target_death_position then
                local death_position = unit_position(state.target)
                    or state.last_target_position
                if death_position then
                    state.target_death_position = copy_position(death_position)
                end
            elseif state.homing and alive(state.target) then
                state.last_target_position = copy_position(state.target:GetAbsOrigin())
            end

            local destination = state.target_death_position or state.end_position
            if state.homing and alive(state.target) then
                destination = state.target:GetAbsOrigin()
            end
            local direction = normalized_direction(
                state.position, destination, state.direction
            )
            state.direction = direction
            local remaining_x = destination.x - state.position.x
            local remaining_y = destination.y - state.position.y
            local remaining_to_destination = math.sqrt(
                remaining_x * remaining_x + remaining_y * remaining_y
            )
            local remaining_distance = math.max(
                0, state.max_distance - state.distance_travelled
            )
            local move_distance = math.min(
                state.move_speed * elapsed,
                remaining_to_destination,
                remaining_distance
            )
            local start_position = copy_position(state.position)
            state.position = state.position + direction * move_distance
            state.distance_travelled = state.distance_travelled + move_distance
            if GetGroundPosition then
                state.position = GetGroundPosition(state.position, nil)
            end
            if state.particle then
                ParticleManager:SetParticleControl(state.particle, 0, state.position)
            end

            local reached_target = moving_ice_ball_collisions(
                state, start_position, state.position
            )
            while active_moving_ice_balls[ball_id]
                and now + 0.0001 >= state.next_damage_at do
                deal_group(
                    state.context,
                    enemies_touching_radius(
                        state.context.attacker, state.position, state.radius
                    ),
                    moving_ice_ball_periodic_multiplier(state),
                    true
                )
                state.next_damage_at = state.next_damage_at + state.damage_interval
            end

            local reached_destination = remaining_to_destination <= move_distance + 0.01
            local exhausted_distance = remaining_distance <= move_distance + 0.01
            if reached_target or reached_destination or exhausted_distance then
                release_moving_ice_ball(ball_id, true)
            end
        end
    end
    if not has_active or next(active_moving_ice_balls) == nil then
        moving_ice_ball_task = nil
        return false
    end
    return MOVING_ICE_BALL_THINK_INTERVAL
end

local function ensure_moving_ice_ball_task()
    if moving_ice_ball_task then return end
    moving_ice_ball_task = scheduler.after(
        MOVING_ICE_BALL_THINK_INTERVAL,
        sync_moving_ice_balls,
        "moving_ice_ball_sync"
    )
end

local function clear_moving_ice_balls()
    for ball_id, _ in pairs(active_moving_ice_balls) do
        release_moving_ice_ball(ball_id, false)
    end
    if moving_ice_ball_task then scheduler.cancel(moving_ice_ball_task) end
    moving_ice_ball_task = nil
end

local function run_frost(context, definition)
    local origin = unit_position(context.attacker)
    local initial_target_position = unit_position(context.target)
    if not origin or not initial_target_position then return false end
    origin = copy_position(origin)
    initial_target_position = copy_position(initial_target_position)
    local initial_delta = initial_target_position - origin
    initial_delta.z = 0
    local initial_distance = initial_delta:Length2D()
    if initial_distance <= 0.01 then return false end

    local maximum_distance = initial_distance * level_value(
        definition, "max_distance_multiplier", context.level, 1
    )
    local homing = level_value(definition, "homing", context.level) > 0
    local target = context.target
    if homing then
        target = moving_ice_ball_random_target(
            context.attacker, origin, maximum_distance, context.target
        )
        if not target then return false end
    end

    moving_ice_ball_sequence = moving_ice_ball_sequence + 1
    local ball_id = moving_ice_ball_sequence
    local now = game_time()
    local particle = nil
    local visual_ok, visual_error = pcall(function()
        particle = ParticleManager:CreateParticle(
            MOVING_ICE_BALL_PARTICLE, PATTACH_WORLDORIGIN, context.attacker
        )
        ParticleManager:SetParticleControl(particle, 0, origin)
    end)
    if not visual_ok then
        particle = nil
        print("[HeroPassiveSkill] moving ice ball failed: " .. tostring(visual_error))
    end
    active_moving_ice_balls[ball_id] = {
        context = context,
        position = origin,
        end_position = initial_target_position,
        direction = initial_delta:Normalized(),
        target = target,
        last_target_position = copy_position(target:GetAbsOrigin()),
        target_death_position = nil,
        homing = homing,
        move_speed = level_value(definition, "move_speed", context.level),
        max_distance = maximum_distance,
        distance_travelled = 0,
        damage_multiplier = level_value(definition, "damage_multiplier", context.level),
        damage_interval = level_value(definition, "damage_interval", context.level),
        next_damage_at = now + level_value(definition, "damage_interval", context.level),
        radius = level_value(definition, "radius", context.level),
        collision_width = level_value(definition, "collision_width", context.level),
        collision_bonus_pct = level_value(definition, "collision_bonus_pct", context.level),
        collision_max_stacks = math.floor(level_value(
            definition, "collision_max_stacks", context.level
        )),
        collision_stacks = 0,
        collided = {},
        distance_bonus_pct_per_100 = level_value(
            definition, "distance_bonus_pct_per_100", context.level
        ),
        explosion_multiplier = level_value(
            definition, "explosion_multiplier", context.level
        ),
        particle = particle,
        last_update_at = now,
    }
    ensure_moving_ice_ball_task()
    return true
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
    if not position then return false end
    position = copy_position(position)
    if GetGroundPosition then position = GetGroundPosition(position, nil) end
    return create_poison_cloud(context, position, definition)
end

local function blade_pulse_damage_multiplier(state, target)
    local multiplier = state.base_multiplier
    if state.maximum_distance_multiplier > 1 then
        local position = unit_position(target) or state.origin
        local offset_x = position.x - state.origin.x
        local offset_y = position.y - state.origin.y
        local distance = math.max(0, math.min(
            state.distance,
            offset_x * state.direction.x + offset_y * state.direction.y
        ))
        local progress = state.distance > 0 and distance / state.distance or 0
        multiplier = multiplier * (
            1 + (state.maximum_distance_multiplier - 1) * progress
        )
    end
    if not state.first_target_hit then
        multiplier = multiplier * state.first_target_multiplier
    end
    return multiplier
end

local function blade_pulse_projectile_hit(ability, target, projectile_id)
    projectile_id = tonumber(projectile_id)
    local state = projectile_id and blade_pulse_projectiles[projectile_id] or nil
    if not state then return false end
    if not target then
        blade_pulse_projectiles[projectile_id] = nil
        return false
    end
    if ability ~= state.ability or not valid(state.context.attacker)
        or not is_enemy(state.context.attacker, target) then return false end
    local target_key = unit_key(target)
    if target_key and not state.hit[target_key] then
        state.hit[target_key] = true
        local multiplier = blade_pulse_damage_multiplier(state, target)
        deal(state.context, target, multiplier, false)
        state.first_target_hit = true
    end
    return false
end

local function run_blade(context, definition)
    if not ProjectileManager or not ProjectileManager.CreateLinearProjectile then
        return false
    end
    local skill_definition = skill_definitions.by_id[context.skill_id]
    local ability = skill_definition and context.attacker:FindAbilityByName(
        skill_definition.ability_name
    ) or nil
    if not valid(ability) then return false end
    local origin = copy_position(context.attacker:GetAbsOrigin())
    local forward = context.attacker:GetForwardVector()
    local direction = Vector(forward.x, forward.y, 0)
    if direction:Length2D() <= 0.001 then return false end
    direction = direction:Normalized()
    local distance = current_attack_range(context.attacker)
        * level_value(definition, "range_multiplier", context.level)
    local duration = level_value(definition, "pulse_duration", context.level)
    local half_width = level_value(definition, "pulse_width", context.level) * 0.5
    if distance <= 0 or duration <= 0 or half_width <= 0 then return false end
    local speed = distance / duration

    local pulse_count = 1
    local triple_chance = level_value(
        definition, "triple_pulse_chance", context.level
    )
    if triple_chance > 0 and RandomFloat(0, 1) <= triple_chance then
        pulse_count = math.max(1, math.floor(level_value(
            definition, "triple_pulse_count", context.level
        ) + 0.001))
    end
    for _ = 1, pulse_count do
        blade_pulse_sequence = blade_pulse_sequence + 1
        local projectile_id = blade_pulse_sequence
        blade_pulse_projectiles[projectile_id] = {
            ability = ability,
            context = context,
            origin = copy_position(origin),
            direction = direction,
            distance = distance,
            base_multiplier = level_value(
                definition, "damage_multiplier", context.level
            ),
            first_target_multiplier = level_value(
                definition, "first_target_multiplier", context.level
            ),
            maximum_distance_multiplier = level_value(
                definition, "maximum_distance_multiplier", context.level
            ),
            first_target_hit = false,
            hit = {},
        }
        ProjectileManager:CreateLinearProjectile({
            Ability = ability,
            EffectName = BLADE_PULSE_PARTICLE,
            Source = context.attacker,
            vSpawnOrigin = origin,
            vVelocity = direction * speed,
            fDistance = distance,
            fStartRadius = half_width,
            fEndRadius = half_width,
            iUnitTargetTeam = DOTA_UNIT_TARGET_TEAM_ENEMY,
            iUnitTargetType = DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
            iUnitTargetFlags = DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
            bDeleteOnHit = false,
            bProvidesVision = false,
            ExtraData = { blade_pulse_projectile_id = projectile_id },
        })
        scheduler.after(distance / speed + BLADE_PULSE_CLEANUP_GRACE, function()
            blade_pulse_projectiles[projectile_id] = nil
        end)
    end
    return true
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

local function create_magic_slingshot_rubble(context, position, definition)
    local radius = level_value(definition, "rubble_radius", context.level)
    local duration = level_value(definition, "rubble_duration", context.level)
    local interval = level_value(definition, "rubble_interval", context.level)
    local multiplier = level_value(definition, "rubble_damage_multiplier", context.level)
    local move_slow_pct = level_value(
        definition, "rubble_move_slow_pct", context.level
    )
    if radius <= 0 or duration <= 0 or interval <= 0 or multiplier <= 0
        or point_inside_rubble(position) then return false end

    magic_slingshot_rubble_sequence = magic_slingshot_rubble_sequence + 1
    local field_id = magic_slingshot_rubble_sequence
    local particle = nil
    local visual_ok, visual_error = pcall(function()
        particle = ParticleManager:CreateParticle(
            MAGIC_SLINGSHOT_RUBBLE_PARTICLE, PATTACH_WORLDORIGIN, context.attacker
        )
        ParticleManager:SetParticleControl(particle, 0, position)
        ParticleManager:SetParticleControl(particle, 1, Vector(radius, 0, 0))
    end)
    if not visual_ok then
        particle = nil
        print("[HeroPassiveSkill] magic slingshot rubble visual failed: "
            .. tostring(visual_error))
    end
    magic_slingshot_rubble_fields[field_id] = {
        context = context,
        position = copy_position(position),
        radius = radius,
        move_slow_pct = math.max(0, move_slow_pct),
        expires_at = game_time() + duration + 0.05,
        particle = particle,
    }
    ensure_magic_slingshot_rubble_task()

    local tick_count = math.max(1, math.floor(duration / interval + 0.001))
    local next_tick = 1
    local started_at = game_time()
    local function rubble_tick()
        local field = magic_slingshot_rubble_fields[field_id]
        if not field or not valid(context.attacker) then return false end
        for _, target in ipairs(enemies_touching_radius(
            context.attacker, field.position, field.radius
        )) do
            deal(context, target, multiplier, true)
        end
        next_tick = next_tick + 1
        if next_tick > tick_count then return false end
        return math.max(0, started_at + next_tick * interval - game_time())
    end
    scheduler.after(interval, rubble_tick)
    return true
end

local function magic_slingshot_projectile_hit(ability, target, location, projectile_id)
    projectile_id = tonumber(projectile_id)
    local state = projectile_id and magic_slingshot_projectiles[projectile_id] or nil
    if not state then return true end
    magic_slingshot_projectiles[projectile_id] = nil
    if not alive(target) or not valid(state.context.attacker) then return true end

    local definition = definitions.by_id.proto_magic_slingshot
    if not definition then return true end
    print(string.format(
        "[MAGIC_SLINGSHOT_HIT] attack=%s projectile=%s target=%s",
        tostring(state.context.attack_id), tostring(projectile_id),
        tostring(target:entindex())
    ))
    local was_stunned = is_stunned(target)
    local multiplier = was_stunned
        and level_value(definition, "stunned_damage_multiplier", state.context.level)
        or level_value(definition, "damage_multiplier", state.context.level)
    deal(state.context, target, multiplier, false)
    if alive(target) then
        stun(state.context.attacker, target,
            level_value(definition, "stun_duration", state.context.level))
    end
    if state.context.level >= 5 and alive(target) then
        local position = location or unit_position(target)
        if position then
            position = copy_position(position)
            if GetGroundPosition then position = GetGroundPosition(position, nil) end
            create_magic_slingshot_rubble(state.context, position, definition)
        end
    end
    return true
end

local function run_magic_slingshot(context, definition)
    local maximum = math.max(1, math.floor(
        level_value(definition, "target_count", context.level) + 0.001
    ))
    local prefer_unstunned = level_value(
        definition, "prefer_unstunned", context.level
    ) > 0
    local targets = magic_slingshot_targets(
        context.attacker, maximum, prefer_unstunned, context.target
    )
    local skill_definition = skill_definitions.by_id[context.skill_id]
    local ability = skill_definition and context.attacker:FindAbilityByName(
        skill_definition.ability_name
    ) or nil
    if not valid(ability) then
        print(string.format(
            "[MAGIC_SLINGSHOT_FAILED] attack=%s reason=ability_missing ability=%s targets=%d",
            tostring(context.attack_id),
            tostring(skill_definition and skill_definition.ability_name or "nil"),
            #targets
        ))
        return false
    end
    if not ProjectileManager or not ProjectileManager.CreateTrackingProjectile then
        print(string.format(
            "[MAGIC_SLINGSHOT_FAILED] attack=%s reason=projectile_manager_missing targets=%d",
            tostring(context.attack_id), #targets
        ))
        return false
    end
    if #targets == 0 then
        print(string.format(
            "[MAGIC_SLINGSHOT_FAILED] attack=%s reason=no_targets range=%s primary=%s",
            tostring(context.attack_id),
            tostring(current_attack_range(context.attacker)),
            tostring(unit_key(context.target) or "nil")
        ))
        return false
    end

    local launched = 0
    for _, target in ipairs(targets) do
        if alive(target) then
            magic_slingshot_projectile_sequence = magic_slingshot_projectile_sequence + 1
            local projectile_id = magic_slingshot_projectile_sequence
            magic_slingshot_projectiles[projectile_id] = { context = context }
            ProjectileManager:CreateTrackingProjectile({
                Target = target,
                Source = context.attacker,
                Ability = ability,
                EffectName = MAGIC_SLINGSHOT_PROJECTILE_PARTICLE,
                iMoveSpeed = level_value(definition, "projectile_speed", context.level),
                bDodgeable = false,
                bProvidesVision = false,
                ExtraData = { magic_slingshot_projectile_id = projectile_id },
            })
            scheduler.after(10, function()
                magic_slingshot_projectiles[projectile_id] = nil
            end)
            launched = launched + 1
        end
    end
    print(string.format(
        "[MAGIC_SLINGSHOT_LAUNCHED] attack=%s range=%s selected=%d launched=%d",
        tostring(context.attack_id),
        tostring(current_attack_range(context.attacker)), #targets, launched
    ))
    return launched > 0
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
    local position = unit_position(context.target)
    local attacker_key = unit_key(context.attacker)
    if not position or not attacker_key or ice_cone_locked(attacker_key) then
        return false
    end
    position = copy_position(position)
    if GetGroundPosition then position = GetGroundPosition(position, nil) end

    local radius = level_value(definition, "radius", context.level)
    local impact_count = math.max(1, math.floor(
        level_value(definition, "impact_count", context.level) + 0.001
    ))
    local impact_interval = level_value(definition, "impact_interval", context.level)
    local cast_duration = level_value(definition, "cast_duration", context.level)
    local damage_multiplier = level_value(definition, "damage_multiplier", context.level)
    local attack_slow_pct = level_value(definition, "attack_slow_pct", context.level)
    local attack_slow_duration = level_value(
        definition, "attack_slow_duration", context.level
    )
    local freeze_chance = level_value(definition, "freeze_chance", context.level)
    local freeze_duration = level_value(definition, "freeze_duration", context.level)
    local current_time = GameRules and GameRules.GetGameTime
        and GameRules:GetGameTime() or 0

    ice_cone_sequence = ice_cone_sequence + 1
    local token = ice_cone_sequence
    local snow_particle = nil
    local visual_ok, visual_error = pcall(function()
        snow_particle = ParticleManager:CreateParticle(
            ICE_CONE_SNOW_PARTICLE, PATTACH_WORLDORIGIN, context.attacker
        )
        ParticleManager:SetParticleControl(snow_particle, 0, position)
        ParticleManager:SetParticleControl(snow_particle, 1, Vector(radius, 0, 0))
    end)
    if not visual_ok then
        snow_particle = nil
        print("[HeroPassiveSkill] ice cone snow field failed: "
            .. tostring(visual_error))
    end
    active_ice_cones[attacker_key] = {
        token = token,
        unlock_at = current_time + cast_duration,
        snow_particle = snow_particle,
    }

    local function release_active()
        local active = active_ice_cones[attacker_key]
        if not active or active.token ~= token then return end
        if active.snow_particle then
            ParticleManager:DestroyParticle(active.snow_particle, false)
            ParticleManager:ReleaseParticleIndex(active.snow_particle)
        end
        active_ice_cones[attacker_key] = nil
    end

    local function impact()
        if not valid(context.attacker) then return end
        local impact_visual_ok, impact_visual_error = pcall(function()
            local particle = ParticleManager:CreateParticle(
                ICE_CONE_IMPACT_PARTICLE, PATTACH_WORLDORIGIN, context.attacker
            )
            ParticleManager:SetParticleControl(particle, 0, position)
            ParticleManager:SetParticleControl(particle, 1, Vector(radius, 0, 0))
            ParticleManager:ReleaseParticleIndex(particle)
        end)
        if not impact_visual_ok then
            print("[HeroPassiveSkill] ice cone impact failed: "
                .. tostring(impact_visual_error))
        end

        local damage_ok, damage_error = pcall(function()
            local targets = enemies_touching_radius(context.attacker, position, radius)
            for _, target in ipairs(targets) do
                deal(context, target, damage_multiplier, false)
                if alive(target) and attack_slow_pct > 0 then
                    buff_manager.apply(
                        context.attacker, target,
                        "debuff_hero_ice_cone_attack_slow",
                        {
                            duration = attack_slow_duration,
                            value = -math.abs(attack_slow_pct),
                        }
                    )
                end
                if alive(target) and freeze_chance > 0
                    and RandomFloat(0, 1) < freeze_chance then
                    stun(context.attacker, target, freeze_duration)
                end
            end
        end)
        if not damage_ok then
            print("[HeroPassiveSkill] ice cone impact damage failed: "
                .. tostring(damage_error))
        end
    end

    impact()
    local next_impact = 2
    local function run_next_impact()
        if next_impact > impact_count then return false end
        impact()
        next_impact = next_impact + 1
        if next_impact > impact_count then return false end
        local now = GameRules and GameRules.GetGameTime
            and GameRules:GetGameTime() or current_time
        local following_time = current_time + (next_impact - 1) * impact_interval
        return math.max(0, following_time - now)
    end
    if impact_count > 1 then scheduler.after(impact_interval, run_next_impact) end
    scheduler.after(cast_duration, release_active)
    return true
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
    proto_magic_slingshot = run_magic_slingshot,
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
    local succeeded = runner(context, definition) ~= false
    if not succeeded then return false end
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
    return true
end

local function roll(payload, skill_id, level, attributes, target_position)
    local definition = definitions.by_id[skill_id]
    if not definition then return false end
    if skill_id == "proto_arcane_barrage" then
        local attacker_key = unit_key(payload.attacker)
        if arcane_barrage_locked(attacker_key) then return false end
    elseif skill_id == "proto_ice_cone" then
        local attacker_key = unit_key(payload.attacker)
        if ice_cone_locked(attacker_key) then return false end
    end
    local chance = definition.trigger_chance[level]
    event_bus.emit(events.HERO_PASSIVE_SKILL_ROLL_REQUESTED, {
        player_id = payload.player_id,
        attack_id = payload.attack_id,
        skill_id = skill_id,
        level = level,
        trigger_chance = chance,
    })
    local random_value = RandomFloat(0, 1)
    if skill_id == "proto_magic_slingshot" then
        local key = unit_key(payload.attacker) or tostring(payload.player_id or "unknown")
        local count = (magic_slingshot_diagnostics[key] or 0) + 1
        magic_slingshot_diagnostics[key] = count
        if count <= MAGIC_SLINGSHOT_DIAGNOSTIC_ROLL_LIMIT
            or random_value < chance then
            print(string.format(
                "[MAGIC_SLINGSHOT_ROLL] attack=%s count=%d random=%.6f chance=%.6f success=%s",
                tostring(payload.attack_id), count, random_value, chance,
                tostring(random_value < chance)
            ))
        end
    end
    if random_value >= chance then return false end
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

end

function M.on_tracking_projectile_hit(ability, target, location, extra_data)
    extra_data = extra_data or {}
    if extra_data.blade_pulse_projectile_id then
        return blade_pulse_projectile_hit(
            ability, target, extra_data.blade_pulse_projectile_id
        )
    end
    if extra_data.magic_slingshot_projectile_id then
        return magic_slingshot_projectile_hit(
            ability, target, location, extra_data.magic_slingshot_projectile_id
        )
    end
    return true
end

function M.init()
    definitions.validate()
    clear_flame_burns()
    clear_moving_ice_balls()
    clear_poison_clouds()
    processed_attacks = {}
    refresh_tokens = {}
    flame_burns = {}
    flame_burn_sequence = 0
    flame_burn_task = nil
    active_arcane_barrages = {}
    arcane_barrage_sequence = 0
    active_ice_cones = {}
    ice_cone_sequence = 0
    active_moving_ice_balls = {}
    moving_ice_ball_sequence = 0
    moving_ice_ball_task = nil
    magic_slingshot_projectiles = {}
    magic_slingshot_projectile_sequence = 0
    clear_magic_slingshot_rubble()
    magic_slingshot_rubble_fields = {}
    magic_slingshot_rubble_sequence = 0
    magic_slingshot_diagnostics = {}
    magic_slingshot_slowed_units = {}
    magic_slingshot_rubble_task = nil
    active_poison_clouds = {}
    poison_cloud_sequence = 0
    poison_cloud_units = {}
    poison_cloud_deaths = {}
    poison_cloud_task = nil
    blade_pulse_projectiles = {}
    blade_pulse_sequence = 0
    effect_sequence = 0
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_main_attack)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_poison_cloud_death)
end

M._test = {
    attribute_snapshot = attribute_snapshot,
    vulnerability_pct = vulnerability_pct,
    enemies_touching_radius = enemies_touching_radius,
    active_arcane_barrages = function() return active_arcane_barrages end,
    active_ice_cones = function() return active_ice_cones end,
    active_moving_ice_balls = function() return active_moving_ice_balls end,
    sync_moving_ice_balls = sync_moving_ice_balls,
    moving_ice_ball_periodic_multiplier = moving_ice_ball_periodic_multiplier,
    moving_ice_ball_point_segment_distance_sq = moving_ice_ball_point_segment_distance_sq,
    moving_ice_ball_random_target = moving_ice_ball_random_target,
    magic_slingshot_targets = magic_slingshot_targets,
    magic_slingshot_projectiles = function() return magic_slingshot_projectiles end,
    magic_slingshot_rubble_fields = function() return magic_slingshot_rubble_fields end,
    point_inside_rubble = point_inside_rubble,
    runners = runners,
    flame_burns = function() return flame_burns end,
    add_flame_burn = add_flame_burn,
    sync_flame_burns = sync_flame_burns,
    flame_burn_tick_multiplier = flame_burn_tick_multiplier,
    flame_random_landing_position = flame_random_landing_position,
    active_poison_clouds = function() return active_poison_clouds end,
    poison_cloud_units = function() return poison_cloud_units end,
    create_poison_cloud = create_poison_cloud,
    release_poison_cloud = release_poison_cloud,
    sync_poison_clouds = sync_poison_clouds,
    poison_cloud_contains = poison_cloud_contains,
    poison_cloud_for_death = poison_cloud_for_death,
    on_poison_cloud_death = on_poison_cloud_death,
    blade_pulse_damage_multiplier = blade_pulse_damage_multiplier,
    blade_pulse_projectiles = function() return blade_pulse_projectiles end,
    blade_pulse_projectile_hit = blade_pulse_projectile_hit,
}

return M