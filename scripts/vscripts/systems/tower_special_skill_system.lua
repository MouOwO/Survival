local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local geometry = require("systems/tower_skill_geometry")

local M = {}
local death_state = {}
local active_waves = {}
local next_wave_id = 0
local WAVE_OF_TERROR_PARTICLE =
    "particles/econ/items/vengeful/vengeful_arcana/vengeful_arcana_wave_of_terror_v2.vpcf"
local WAVE_OF_TERROR_SPEED = 1200
-- The root particle lives for one second and its visible core has a constant
-- radius of 112. Keep the engine projectile aligned with those source values.
local WAVE_OF_TERROR_DISTANCE = 1200
local WAVE_OF_TERROR_HALF_WIDTH = 112
local WAVE_CLEANUP_GRACE = 0.25
local DROW_FROST_HIT_PARTICLE =
    "particles/econ/items/drow/drow_arcana/drow_arcana_frost_arrow_debuff.vpcf"
local DROW_TOWER_ASSET_ID = "tower_multi_drow_dread_retribution"

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

local function deal(attacker, victim, damage, tag, ability)
    return event_bus.request(events.TOWER_SKILL_DAMAGE_REQUEST, {
        attacker = attacker,
        victim = victim,
        damage = damage,
        ability = ability,
        damage_type = DAMAGE_TYPE_PHYSICAL,
        damage_flags = DOTA_DAMAGE_FLAG_NO_DAMAGE_MULTIPLIERS,
        source_kind = "ability",
        tags = { "tower_special_skill", tag },
    })
end

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
    local piercing = skill_matching(payload.skills, "piercing_ballista_")
    if piercing and owns_ability(tower, piercing) and piercing.buff_id then
        event_bus.request(events.TOWER_SKILL_BUFF_REQUEST, {
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

local function trigger_death_grenade(payload)
    if not payload.critical then return end
    local skill = skill_matching(payload.skills, "death_grenade_")
    if not skill or not owns_ability(payload.tower, skill) then return end
    local radius = configured_area(skill, 300)
    local damage = math.max(0, tonumber(payload.damage) or 0)
        * math.max(0, tonumber(skill.damage_multiplier) or 2)
    for _, enemy in ipairs(geometry.enemies_in_circle(
        payload.tower, payload.target:GetAbsOrigin(), radius
    )) do
        if enemy ~= payload.target then
            deal(payload.tower, enemy, damage, "death_grenade")
        end
    end
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
    local damage = math.max(0, tonumber(payload.damage) or 0)
        * math.max(0, tonumber(skill.damage_multiplier) or 1)

    next_wave_id = next_wave_id + 1
    local wave_id = next_wave_id
    local tower_entindex = tower:entindex()
    local wave = {
        tower = tower,
        tower_entindex = tower_entindex,
        ability = ability,
        damage = damage,
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
        deal(
            wave.tower,
            target,
            wave.damage,
            "burning_great_arrow",
            wave.ability
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

local function trigger_path_skill(payload, prefix, fallback_width, tag,
        particle_callback)
    local skill = skill_matching(payload.skills, prefix)
    if not skill or not owns_ability(payload.tower, skill) then return end
    local damage = math.max(0, tonumber(payload.damage) or 0)
        * math.max(0, tonumber(skill.damage_multiplier) or 1)
    local start_pos = payload.tower:GetAbsOrigin()
    local end_pos = payload.target:GetAbsOrigin()
    local width = configured_area(skill, fallback_width)
    if particle_callback then
        particle_callback(payload.tower, start_pos, end_pos, width)
    end
    for _, enemy in ipairs(geometry.enemies_in_path(
        payload.tower, start_pos, end_pos, width, payload.target
    )) do
        deal(payload.tower, enemy, damage, tag)
    end
end

local function trigger_burning_great_arrow(payload)
    local skill = skill_matching(payload.skills, "burning_great_arrow_")
    if not skill or not owns_ability(payload.tower, skill) then return end
    launch_burning_wave(payload, skill, WAVE_OF_TERROR_HALF_WIDTH)
end

local function on_attack_landed(payload)
    -- The engine can report ON_ATTACK_LANDED after the same attack has already
    -- killed its primary target. Path effects still need the target's final
    -- position, so only the tower must remain alive here.
    if not valid(payload.tower) or not exists(payload.target) then return end
    frost_arrow_hit_particle(payload.tower, payload.target)
    update_bone_counter(payload)
    trigger_death_grenade(payload)
    trigger_path_skill(payload, "arcane_eye_", 96, "arcane_eye")
    trigger_burning_great_arrow(payload)
end

local function on_building_destroyed(payload)
    local entindex = tonumber(payload and (payload.entindex or payload.unit_entindex))
    if entindex then
        death_state[entindex] = nil
        cancel_tower_waves(entindex)
    end
end

local function on_lightning_hit(payload)
    if not valid(payload.tower) or not valid(payload.target) then return end
    local skill = skill_matching(payload.skills, "lightning_diffusion_")
    if not skill or not owns_ability(payload.tower, skill) then return end
    local chance = math.max(0, math.min(
        100, tonumber(skill.trigger_chance_pct) or 30
    ))
    if not RollPercentage(chance) then return end
    local radius = configured_area(skill, 200)
    local damage = math.max(0, tonumber(payload.damage) or 0)
        * math.max(0, tonumber(skill.damage_multiplier) or 2)
    for _, enemy in ipairs(geometry.enemies_in_circle(
        payload.tower, payload.target:GetAbsOrigin(), radius
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
    event_bus.subscribe(events.TOWER_LIGHTNING_HIT, on_lightning_hit)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
end

return M
