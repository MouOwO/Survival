local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local geometry = require("systems/tower_skill_geometry")
local sound_service = require("core/sound_service")
local anti_air_rules = require("systems/anti_air_rules")
local tower_skill_damage_rules = require("config/generated/tower_skill_damage_rules")

local M = {}
local death_state = {}
local active_waves = {}
local next_wave_id = 0
local WAVE_OF_TERROR_PARTICLE =
    "particles/econ/items/vengeful/vengeful_arcana/vengeful_arcana_wave_of_terror_v2.vpcf"
local WAVE_OF_TERROR_SPEED = 1560
-- Keep the source particle's 1200 length and 112 core radius while playing
-- its travel at the approved 1.3x speed.
local WAVE_OF_TERROR_DISTANCE = 1200
local WAVE_OF_TERROR_HALF_WIDTH = 112
local WAVE_CLEANUP_GRACE = 0.25
local DROW_FROST_HIT_PARTICLE =
    "particles/econ/items/drow/drow_arcana/drow_arcana_frost_arrow_debuff.vpcf"
local DROW_TOWER_ASSET_ID = "tower_multi_drow_dread_retribution"
local DEATH_CRITICAL_ASSET_IDS = {
    bone_cannon = "tower_death_nevermore_sundered_souls",
}
local DEATH_GRENADE_ASSET_ID = "tower_death_warlock_seam_ripper"
local LIGHTNING_ASSET_ID = "tower_zuus"
local DEFAULT_DIFFUSION_PARTICLE =
    "particles/units/heroes/hero_razor/razor_plasmafield.vpcf"
local DIFFUSION_PARTICLE_DURATION = 0.4
local asset_catalog = require("config/asset_catalog")

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function exists(unit)
    return unit and not unit:IsNull()
end

local function skill_matching(skills, prefix)
    for _, row in pairs(skills or {}) do
        if row.skill_id and string.match(row.skill_id, "^" .. prefix) then
            return row
        end
    end
    return nil
end

local function owns_ability(tower, skill)
    if not valid(tower) or not skill or not skill.skill_id then return false end
    local ability = tower:FindAbilityByName(skill.skill_id)
    return ability and not ability:IsNull() and ability:GetLevel() > 0
end

local function configured_area(skill, fallback)
    local value = skill and skill.area
    if type(value) == "table" then value = value[1] end
    return math.max(1, tonumber(value) or fallback)
end

local function skill_effect_particle(skill, role, asset_id)
    local bundle = asset_catalog.by_id[asset_id]
    local skill_bundle = bundle and skill and bundle.skills[skill.skill_id]
    local effects = skill_bundle and skill_bundle.effects_by_role[role]
    local effect = effects and effects[1]
    return effect and effect.particle_path or nil
end

local function play_world_particle(tower, position, particle_path)
    if not particle_path then return end
    local particle = ParticleManager:CreateParticle(
        particle_path, PATTACH_WORLDORIGIN, tower
    )
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:ReleaseParticleIndex(particle)
end

local function play_tower_sound(cue_id, tower, unit, position)
    sound_service.play(cue_id, {
        source = tower,
        unit = unit or tower,
        position = position,
    })
end

local function diffusion_particle_path(skill)
    local bundle = asset_catalog.by_id[LIGHTNING_ASSET_ID]
    local skill_bundle = bundle and skill and bundle.skills[skill.skill_id]
    local effects = skill_bundle
        and skill_bundle.effects_by_role["skill_strike"]
    local effect = effects and effects[1]
    return effect and effect.particle_path or DEFAULT_DIFFUSION_PARTICLE
end

local function play_diffusion_particle(tower, position, radius, skill)
    local particle = ParticleManager:CreateParticle(
        diffusion_particle_path(skill), PATTACH_WORLDORIGIN, tower
    )
    ParticleManager:SetParticleControl(particle, 0, position)
    -- Razor Plasma Field reads CP1 as outward speed, maximum radius, and force
    -- scale. Keep z at 1: the VPCF uses that component to scale radial force.
    ParticleManager:SetParticleControl(
        particle, 1, Vector(
            radius / DIFFUSION_PARTICLE_DURATION, radius, 1
        )
    )
    ParticleManager:SetParticleControl(
        particle, 2, Vector(DIFFUSION_PARTICLE_DURATION, 0, 0)
    )
    scheduler.after(DIFFUSION_PARTICLE_DURATION + 0.2, function()
        ParticleManager:DestroyParticle(particle, false)
        ParticleManager:ReleaseParticleIndex(particle)
    end)
end

local function deal(attacker, victim, damage, tag, ability, damage_type,
        physical_armor_ignore_pct)
    local secondary = tag == "lightning_diffusion"
    return event_bus.request(events.TOWER_SKILL_DAMAGE_REQUEST, {
        attacker = attacker,
        victim = victim,
        damage = damage,
        ability = ability,
        damage_type = damage_type or DAMAGE_TYPE_PHYSICAL,
        damage_flags = DOTA_DAMAGE_FLAG_NO_DAMAGE_MULTIPLIERS,
        physical_armor_ignore_pct = physical_armor_ignore_pct,
        source_kind = "ability",
        source = tag,
        is_secondary = secondary,
        can_trigger_diffusion = not secondary,
        tags = { "tower_special_skill", tag },
    })
end

local trigger_burning_great_arrow

local function death_data(tower)
    local key = tower:entindex()
    death_state[key] = death_state[key] or { hits = 0, ready = false }
    return death_state[key]
end

local function critical_query(payload)
    local tower = payload.tower
    if not valid(tower) then return nil end
    local skills = payload.skills or {}
    local bone = skill_matching(skills, "bone_cannon_")
    local state = death_data(tower)
    if bone and owns_ability(tower, bone) and state.ready then
        state.ready = false
        return { multiplier_pct = 1000, source = "bone_cannon" }
    end
    local critical = skill_matching(skills, "critical_strike_")
    if critical and owns_ability(tower, critical) then
        local chance = math.max(0, math.min(
            100, tonumber(critical.trigger_chance_pct) or 0
        ))
        if RollPercentage(chance) then
            return {
                multiplier_pct = math.max(
                    100, (tonumber(critical.damage_multiplier) or 5) * 100
                ),
                source = "critical_strike",
            }
        end
    end
    return nil
end

local function on_attack_start(payload)
    local tower, target = payload.tower, payload.target
    if not valid(tower) or not valid(target) then return end
    local burning = skill_matching(payload.skills, "burning_great_arrow_")
    if burning then
        trigger_burning_great_arrow(payload)
        return
    end
    local piercing = skill_matching(payload.skills, "piercing_ballista_")
    if piercing and owns_ability(tower, piercing) and piercing.buff_id then
        local modifier = event_bus.request(events.TOWER_SKILL_BUFF_REQUEST, {
            caster = tower,
            target = target,
            buff_id = piercing.buff_id,
            options = {
                duration = math.max(0.1, tonumber(piercing.duration) or 3),
                value = -math.abs(
                    tonumber(piercing.attack_armor_reduction) or 0
                ),
            },
        })
        if modifier then
            play_tower_sound("tower_piercing_ballista", tower, target)
        end
    end
end

local function update_bone_counter(payload)
    local bone = skill_matching(payload.skills, "bone_cannon_")
    if not bone or not owns_ability(payload.tower, bone) then return end
    local state = death_data(payload.tower)
    state.hits = state.hits + 1
    local required = math.max(1, tonumber(bone.trigger_attack_count) or 9)
    if state.hits >= required then
        state.hits = 0
        state.ready = true
    end
end

local function trigger_death_critical_particle(payload)
    if not payload.critical then return end
    local source = tostring(payload.critical_source or "")
    local sound_cue = source == "bone_cannon" and "tower_bone_cannon"
        or source == "critical_strike" and "tower_critical_strike"
        or nil
    if sound_cue then
        play_tower_sound(
            sound_cue, payload.tower, payload.target,
            payload.target:GetAbsOrigin()
        )
    end
    local asset_id = DEATH_CRITICAL_ASSET_IDS[source]
    if not asset_id then return end
    local skill = skill_matching(payload.skills, "bone_cannon_")
    if not skill or not owns_ability(payload.tower, skill) then return end
    play_world_particle(
        payload.tower,
        payload.target:GetAbsOrigin(),
        skill_effect_particle(skill, "skill_strike", asset_id)
    )
end

local function trigger_death_grenade(payload)
    if not payload.critical then return end
    local skill = skill_matching(payload.skills, "death_grenade_")
    if not skill or not owns_ability(payload.tower, skill) then return end
    local chance = math.max(0, math.min(
        100, tonumber(skill.trigger_chance_pct) or 10
    ))
    if not RollPercentage(chance) then return end
    local damage = math.max(0, tonumber(payload.damage) or 0)
        * math.max(0, tonumber(skill.damage_multiplier) or 1)
    local position = payload.target:GetAbsOrigin()
    play_world_particle(
        payload.tower,
        position,
        skill_effect_particle(skill, "skill_strike", DEATH_GRENADE_ASSET_ID)
    )
    play_tower_sound(
        "tower_death_grenade", payload.tower, payload.target, position
    )
    deal(payload.tower, payload.target, damage, "death_grenade")
end

local function clear_wave(wave_id, destroy_projectile)
    local wave = active_waves[wave_id]
    if not wave then return end
    active_waves[wave_id] = nil
    if wave.cleanup_task_id then scheduler.cancel(wave.cleanup_task_id) end
    if destroy_projectile and wave.projectile_id and ProjectileManager then
        ProjectileManager:DestroyLinearProjectile(wave.projectile_id)
    end
end

local function cancel_tower_waves(tower_entindex)
    local wave_ids = {}
    for wave_id, wave in pairs(active_waves) do
        if wave.tower_entindex == tower_entindex then
            wave_ids[#wave_ids + 1] = wave_id
        end
    end
    for _, wave_id in ipairs(wave_ids) do clear_wave(wave_id, true) end
end

local function launch_burning_wave(payload, skill, fallback_width)
    local tower = payload.tower
    local target = payload.target
    local ability = tower:FindAbilityByName(skill.skill_id)
    if not ability or ability:IsNull() then return end
    local start_pos = tower:GetAbsOrigin()
    local target_pos = target:GetAbsOrigin()
    local direction = target_pos - start_pos
    direction.z = 0
    if direction:Length2D() <= 0.001 then return end
    direction = direction:Normalized()

    local width = configured_area(skill, fallback_width)
    local damage = math.max(
        0,
        tonumber(payload.damage) or tower:GetAverageTrueAttackDamage(tower)
    )
    local rule = tower_skill_damage_rules.by_id[skill.skill_id]
    local piercing = skill_matching(payload.skills, "piercing_ballista_")

    next_wave_id = next_wave_id + 1
    local wave_id = next_wave_id
    local tower_entindex = tower:entindex()
    local wave = {
        tower = tower,
        tower_entindex = tower_entindex,
        ability = ability,
        damage = damage,
        base_multiplier = math.max(0, tonumber(skill.damage_multiplier) or 1),
        penetration_decay = math.max(
            0, tonumber(rule and rule.penetration_decay) or 1
        ),
        armor_ignore_pct = math.max(
            0, tonumber(piercing and piercing.attack_armor_reduction) or 0
        ),
        hit_count = 0,
        hit = {},
    }
    active_waves[wave_id] = wave

    wave.projectile_id = ProjectileManager:CreateLinearProjectile({
        Ability = ability,
        EffectName = WAVE_OF_TERROR_PARTICLE,
        Source = tower,
        vSpawnOrigin = start_pos,
        vVelocity = direction * WAVE_OF_TERROR_SPEED,
        fDistance = WAVE_OF_TERROR_DISTANCE,
        fStartRadius = width,
        fEndRadius = width,
        iUnitTargetTeam = DOTA_UNIT_TARGET_TEAM_ENEMY,
        iUnitTargetType = DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        iUnitTargetFlags = DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        bDeleteOnHit = false,
        bProvidesVision = false,
        ExtraData = {
            burning_great_arrow = 1,
            burning_wave_id = wave_id,
        },
    })
    play_tower_sound("tower_burning_great_arrow", tower, tower)

    local task_id = "burning_great_arrow_cleanup_"
        .. tostring(tower_entindex) .. "_" .. tostring(wave_id)
    wave.cleanup_task_id = scheduler.after(
        WAVE_OF_TERROR_DISTANCE / WAVE_OF_TERROR_SPEED + WAVE_CLEANUP_GRACE,
        function()
            clear_wave(wave_id, false)
            return false
        end,
        task_id
    )
end

function M.on_burning_wave_projectile_hit(ability, target, _, extra_data)
    if type(extra_data) ~= "table"
        or tonumber(extra_data.burning_great_arrow) ~= 1 then
        return false
    end
    local wave_id = tonumber(extra_data.burning_wave_id)
    local wave = wave_id and active_waves[wave_id] or nil
    if not wave then return false end
    if not target then
        clear_wave(wave_id, false)
        return false
    end
    if not valid(wave.tower) or not valid(target) then return false end
    if ability ~= wave.ability then return false end

    local enemy_index = target:entindex()
    if not wave.hit[enemy_index] then
        wave.hit[enemy_index] = true
        local multiplier = wave.base_multiplier
            * math.pow(wave.penetration_decay, wave.hit_count)
        wave.hit_count = wave.hit_count + 1
        deal(
            wave.tower,
            target,
            wave.damage * multiplier,
            "burning_great_arrow",
            wave.ability,
            nil,
            wave.armor_ignore_pct
        )
    end
    -- A linear projectile only pierces subsequent units when every unit-hit
    -- callback declines deletion.
    return false
end

local function frost_arrow_hit_particle(tower, target)
    if tower.survival_model_asset_id ~= DROW_TOWER_ASSET_ID then return end
    local particle = ParticleManager:CreateParticle(
        DROW_FROST_HIT_PARTICLE,
        PATTACH_ABSORIGIN_FOLLOW,
        target
    )
    local function cleanup()
        ParticleManager:DestroyParticle(particle, false)
        ParticleManager:ReleaseParticleIndex(particle)
    end
    if target.SetContextThink then
        target:SetContextThink(
            "survival_drow_frost_hit_" .. tostring(particle),
            cleanup,
            0.45
        )
    else
        cleanup()
    end
end

trigger_burning_great_arrow = function(payload)
    local skill = skill_matching(payload.skills, "burning_great_arrow_")
    if not skill or not owns_ability(payload.tower, skill) then return end
    launch_burning_wave(payload, skill, WAVE_OF_TERROR_HALF_WIDTH)
end

local function on_laser_hit(payload)
    if not valid(payload.tower) or not exists(payload.target) then return end
    local skill = skill_matching(payload.skills, "arcane_eye_")
    if not skill or not owns_ability(payload.tower, skill) then return end
    local radius = configured_area(skill, 150)
    local damage = math.max(0, tonumber(payload.damage) or 0)
        * math.max(0, tonumber(skill.damage_multiplier) or 0.3)
    local position = payload.target:GetAbsOrigin()
    play_tower_sound(
        "tower_arcane_eye", payload.tower, payload.target, position
    )
    for _, enemy in ipairs(geometry.enemies_in_circle(
        payload.tower, position, radius
    )) do
        if enemy ~= payload.target then
            deal(payload.tower, enemy, damage, "arcane_eye", nil,
                DAMAGE_TYPE_PHYSICAL)
        end
    end
end

local function on_attack_landed(payload)
    -- The engine can report ON_ATTACK_LANDED after the same attack has already
    -- killed its primary target. Path effects still need the target's final
    -- position, so only the tower must remain alive here.
    if not valid(payload.tower) or not exists(payload.target) then return end
    frost_arrow_hit_particle(payload.tower, payload.target)
    update_bone_counter(payload)
    trigger_death_critical_particle(payload)
    trigger_death_grenade(payload)
end

local function on_building_destroyed(payload)
    local entindex = tonumber(payload and (payload.entindex or payload.unit_entindex))
    if entindex then
        death_state[entindex] = nil
        cancel_tower_waves(entindex)
    end
end

local function on_lightning_hit(payload)
    if not valid(payload.tower) or not exists(payload.target) then return end
    -- Only Lightning Storm impacts may proc diffusion. Diffusion damage is sent
    -- through the damage request only and never republishes TOWER_LIGHTNING_HIT.
    if payload.source ~= "lightning_storm"
        or payload.can_trigger_diffusion ~= true then return end
    local skill = skill_matching(payload.skills, "lightning_diffusion_")
    if not skill or not owns_ability(payload.tower, skill) then return end
    local chance = math.max(0, math.min(
        100, tonumber(skill.trigger_chance_pct) or 30
    ))
    if not RollPercentage(chance) then return end
    local radius = configured_area(skill, 200)
    local damage = math.max(0, tonumber(payload.damage) or 0)
        * math.max(0, tonumber(skill.damage_multiplier) or 2)
    local position = payload.target:GetAbsOrigin()
    play_diffusion_particle(payload.tower, position, radius, skill)
    play_tower_sound(
        "tower_lightning_diffusion", payload.tower, payload.target, position
    )
    for _, enemy in ipairs(geometry.enemies_in_circle(
        payload.tower, position, radius
    )) do
        if enemy ~= payload.target then
            deal(payload.tower, enemy, damage, "lightning_diffusion")
        end
    end
end

function M.init()
    local wave_ids = {}
    for wave_id in pairs(active_waves) do wave_ids[#wave_ids + 1] = wave_id end
    for _, wave_id in ipairs(wave_ids) do clear_wave(wave_id, true) end
    death_state = {}
    active_waves = {}
    next_wave_id = 0
    event_bus.handle_request(events.TOWER_CRITICAL_QUERY, critical_query)
    event_bus.subscribe(events.TOWER_ATTACK_START, on_attack_start)
    event_bus.subscribe(events.TOWER_ATTACK_LANDED, on_attack_landed)
    event_bus.subscribe(events.TOWER_LASER_HIT, on_laser_hit)
    event_bus.subscribe(events.TOWER_LIGHTNING_HIT, on_lightning_hit)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
end

return M
