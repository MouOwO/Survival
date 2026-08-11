LinkLuaModifier("modifier_tower_attack_effects", "modifiers/modifier_tower_attack_effects", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_tower_explosive_gatling_buff", "modifiers/modifier_tower_attack_effects", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_tower_frost_slow", "modifiers/modifier_tower_attack_effects", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_tower_blizzard_slow", "modifiers/modifier_tower_attack_effects", LUA_MODIFIER_MOTION_NONE)
modifier_tower_attack_effects = class({})
_G.modifier_tower_attack_effects = modifier_tower_attack_effects
local M = modifier_tower_attack_effects

local tower_skills = require("systems/tower_skill_runtime")
local laser_effects = require("config/generated/tower_laser_effects")
local damage_service = require("combat/damage_service")
local scheduler = require("core/scheduler")
local event_bus = require("core/event_bus")
local events = require("core/events")
local buff_manager = require("systems/buff_manager")
local asset_catalog = require("config/asset_catalog")
local sound_service = require("core/sound_service")
local global_rules = require("config/generated/global_rules")
local tower_combat_rules = require("config/tower_combat_rules")

local detailed_diagnostics = global_rules.by_id.runtime_detailed_diagnostics
    and global_rules.by_id.runtime_detailed_diagnostics.enabled ~= false
    and tonumber(global_rules.by_id.runtime_detailed_diagnostics.value) == 1

local function detailed_log(format_string, ...)
    if detailed_diagnostics then
        print(string.format(format_string, ...))
    end
end

local MULTI_DAMAGE_MULTIPLIER = 1.00
local DEFAULT_LIGHTNING_BOUNCE_RADIUS = 200
local LIGHTNING_BOUNCE_DELAY = 0.10
local LIGHTNING_SOURCE_OFFSET_Z = 160
local LIGHTNING_TARGET_OFFSET_Z = 70
local SPLIT_ARROW_SPEED = 900
local DEFAULT_STORM_RADIUS = 500
local DEFAULT_STORM_DURATION = 5
local DEFAULT_STORM_DAMAGE_MULTIPLIER = 1
local GATLING_ATTACK_COUNT = 5
local DEFAULT_FROST_SLOW_DURATION = 2
local FROST_SLOW_PCT = 25
local DEFAULT_BLIZZARD_RADIUS = 300
local DEFAULT_BLIZZARD_DURATION = 5
local DEFAULT_BLIZZARD_INTERVAL = 1
local DEFAULT_BLIZZARD_DAMAGE_MULTIPLIER = 0.5
local BLIZZARD_SLOW_PCT = 25
local start_lightning_storm

local LIGHTNING_ASSET_ID = "tower_zuus"
local MACHINE_GUN_ASSET_IDS = {
    bounty = "tower_machine_gun_bounty_heartless",
    gatling = "tower_machine_gun_windranger_rising_gale",
}
local DEATH_TOWER_ANIMATED_ASSETS = {
    tower_death_templar_assassin = true,
    tower_death_nevermore_sundered_souls = true,
    tower_death_warlock_seam_ripper = true,
}
local DEFAULT_CHAIN_PARTICLE =
    "particles/units/heroes/hero_zuus/zuus_arc_lightning.vpcf"
local DEFAULT_STORM_CLOUD_PARTICLE =
    "particles/units/heroes/hero_disruptor/disruptor_static_storm.vpcf"
local DEFAULT_STORM_STRIKE_PARTICLE =
    "particles/units/heroes/hero_leshrac/leshrac_lightning_bolt.vpcf"

local function skill_effect_particle(unit, skill, role, fallback, fallback_asset_id)
    local skill_id = type(skill) == "table" and skill.skill_id or nil
    local valid_unit = unit and not unit:IsNull()
    local asset_id = valid_unit and unit.survival_model_asset_id or fallback_asset_id
    local function lookup(candidate_id)
        local bundle = asset_catalog.by_id[candidate_id]
        local skill_bundle = bundle and skill_id and bundle.skills[skill_id] or nil
        local effects = skill_bundle and skill_bundle.effects_by_role[role] or nil
        local effect = effects and effects[1] or nil
        return effect and effect.particle_path or nil
    end
    return lookup(asset_id) or lookup(fallback_asset_id) or fallback
end

local function play_follow_particle(owner, particle_name)
    if not owner or owner:IsNull() or not particle_name or particle_name == "" then
        return nil
    end
    local particle = ParticleManager:CreateParticle(
        particle_name,
        PATTACH_ABSORIGIN_FOLLOW,
        owner
    )
    ParticleManager:ReleaseParticleIndex(particle)
    return particle
end

local function play_tower_sound(cue_id, tower, unit, position)
    sound_service.play(cue_id, {
        source = tower,
        unit = unit or tower,
        position = position,
    })
end

local function skill_matching(unit, prefix)
    for _, row in pairs(tower_skills.get(unit)) do
        if row.skill_id and string.match(row.skill_id, "^" .. prefix) then
            return row
        end
    end
    return nil
end

local function owns_skill_ability(unit, skill)
    if not unit or unit:IsNull() or not skill or not skill.skill_id then
        return false
    end
    local ability = unit:FindAbilityByName(skill.skill_id)
    return ability ~= nil and not ability:IsNull() and ability:GetLevel() > 0
end

local function is_arrow_tower(unit)
    return unit and not unit:IsNull()
        and unit:GetUnitName() == "building_arrow_tower"
end

local function laser_config(skill)
    if not skill then return nil end
    local row = (laser_effects.by_id or {})[skill.skill_id]
    return row and row.enabled ~= false and row or nil
end

function modifier_tower_attack_effects:IsHidden() return true end
function modifier_tower_attack_effects:IsPurgable() return false end
function modifier_tower_attack_effects:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end
function modifier_tower_attack_effects:DeclareFunctions()
    return {
        MODIFIER_EVENT_ON_ATTACK_START,
        MODIFIER_EVENT_ON_ATTACK,
        MODIFIER_EVENT_ON_ATTACK_FAIL,
        MODIFIER_EVENT_ON_ATTACK_LANDED,
        MODIFIER_EVENT_ON_DEATH,
        MODIFIER_PROPERTY_ATTACK_POINT_CONSTANT,
        MODIFIER_PROPERTY_CANNOT_MISS,
        MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE,
        MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_TOTALDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE,
    }
end

function modifier_tower_attack_effects:GetModifierCannotMiss()
    return tower_combat_rules.cannot_miss(self:GetParent()) and 1 or 0
end

function modifier_tower_attack_effects:GetModifierAttackSpeedPercentage()
    local skill = skill_matching(self:GetParent(), "machine_gun_")
    return skill and (tonumber(skill.damage_multiplier) or 0) * 100 or 0
end

function modifier_tower_attack_effects:GetModifierDamageOutgoing_Percentage()
    if skill_matching(self:GetParent(), "multi_attack_") then
        return (MULTI_DAMAGE_MULTIPLIER - 1) * 100
    end
    return 0
end

function modifier_tower_attack_effects:OnCreated()
    if not IsServer() then return end
    self.gatling_target_entindex = nil
    self.gatling_target_hits = 0
    self.laser_target = nil
    self.laser_elapsed = 0
    self.laser_visual_elapsed = 0
    self.laser_particles = {}
    self.last_interval_time = GameRules:GetGameTime()
    self.current_attack_target = nil
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    self.attack_landed_diagnostic_count = 0
    self.attack_failed_diagnostic_count = 0
    self.polar_obelisk_sound_active = false
    self:StartIntervalThink(0.03)
end

local function sync_polar_obelisk_aura(tower, state)
    state = state or tower
    local skill = skill_matching(tower, "polar_obelisk_")
    if skill then
        local configured = skill.area
        if type(configured) == "table" then configured = configured[1] end
        buff_manager.apply_aura(
            tower, skill.buff_id,
            math.max(1, tonumber(configured) or 400)
        )
        if not state.polar_obelisk_sound_active then
            play_tower_sound("tower_polar_obelisk", tower, tower)
            state.polar_obelisk_sound_active = true
        end
    else
        buff_manager.remove_aura(tower, "debuff_polar_attack_slow")
        state.polar_obelisk_sound_active = false
    end
end

local function trigger_gatling_buff(tower, skill, reason)
    if not tower or tower:IsNull() or not skill then return end
    local duration = math.max(0.1, tonumber(skill.duration) or 3)
    local bonus_pct = math.max(0, (tonumber(skill.damage_multiplier) or 0) * 100)
    local modifier = buff_manager.apply(tower, tower, skill.buff_id, {
        duration = duration,
        value = bonus_pct,
    })
    if modifier then
        play_follow_particle(tower, skill_effect_particle(
            tower,
            skill,
            "skill_strike",
            "particles/units/heroes/hero_windrunner/windrunner_focusfire_start.vpcf",
            MACHINE_GUN_ASSET_IDS.gatling
        ))
        play_tower_sound("tower_explosive_gatling", tower, tower)
    end
    detailed_log(
        "[TowerMachineGun] GATLING_BUFF tower=%d reason=%s bonus_pct=%.0f duration=%.1f",
        tower:entindex(), tostring(reason), bonus_pct, duration
    )
end

function modifier_tower_attack_effects:GetModifierAttackPointConstant()
    local effect = laser_config(skill_matching(self:GetParent(), "laser_"))
    return effect and math.max(0, tonumber(effect.attack_point) or 0) or nil
end

function modifier_tower_attack_effects:GetModifierTotalDamageOutgoing_Percentage()
    return 0
end

function modifier_tower_attack_effects:OnDeath(params)
    if not IsServer() then return end
    local tower = self:GetParent()
    local victim = params.unit
    if params.attacker ~= tower then return end

    -- MODIFIER_EVENT_ON_DEATH is global. Tower effects must only react when
    -- this modifier's own tower is the actual killer; team/player ownership
    -- is deliberately insufficient because heroes and towers are isolated
    -- combat domains.
    local storm = skill_matching(tower, "lightning_storm_")
    if is_arrow_tower(tower) and owns_skill_ability(tower, storm)
        and victim and not victim:IsNull()
        and victim:GetTeamNumber() ~= tower:GetTeamNumber() then
        start_lightning_storm(tower, victim:GetAbsOrigin(), storm)
    end

    local gatling = skill_matching(tower, "explosive_gatling_")
    if gatling and victim and not victim:IsNull()
        and victim:GetTeamNumber() ~= tower:GetTeamNumber() then
        trigger_gatling_buff(tower, gatling, "kill")
    end

    local skill = skill_matching(tower, "arcane_cannon_")
    if not skill then return end
    local duration = math.max(0.1, tonumber(skill.duration) or 5)
    local max_stacks = math.max(1, tonumber(skill.max_targets) or 4)
    local modifier = buff_manager.apply(tower, tower, skill.buff_id, {
        duration = duration,
        value = (tonumber(skill.damage_multiplier) or 0) * 100,
        max_stacks = max_stacks,
    })
    if modifier then
        play_tower_sound("tower_arcane_cannon", tower, tower)
    end
    detailed_log(
        "[TowerMystery] KILL_BUFF tower=%d stacks=%d duration=%.1f",
        tower:entindex(), modifier and modifier:GetStackCount() or 0, duration
    )
end

function modifier_tower_attack_effects:GetModifierPreAttack_CriticalStrike()
    if not IsServer() then return 0 end
    if self.pending_critical_multiplier then
        return self.pending_critical_multiplier * 100
    end
    local tower = self:GetParent()
    local special = event_bus.request(events.TOWER_CRITICAL_QUERY, {
        tower = tower,
        target = self.current_attack_target,
        skills = tower_skills.get(tower),
    })
    local multiplier = special and tonumber(special.multiplier_pct) or 0
    local source = special and special.source or nil
    local inherited_chance = math.max(
        0, tonumber(tower.survival_inherited_critical_chance_pct) or 0
    )
    if multiplier <= 100 and inherited_chance > 0
        and RandomFloat(0, 100) < inherited_chance then
        multiplier = math.max(
            100,
            tonumber(tower.survival_inherited_critical_damage_pct) or 200
        )
        source = "monkey_king_r"
    end
    local research_chance = math.max(
        0, tonumber(tower.survival_super_tower_crit_chance) or 0
    )
    if RandomFloat(0, 100) < research_chance and multiplier < 200 then
        multiplier = 200
        source = "research_critical"
    end
    if multiplier > 100 then
        self.pending_critical_multiplier = multiplier / 100
        self.pending_critical_source = source
        return multiplier
    end
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    return 0
end

local function exists(u) return u and not u:IsNull() end
local function valid(u) return exists(u) and u:IsAlive() end

local function lightning_control_point(particle, control_point, unit,
        attachment_name, fallback_position, offset_z)
    local position = fallback_position
    if not position and exists(unit) then position = unit:GetAbsOrigin() end
    position = (position or Vector(0, 0, 0))
        + Vector(0, 0, tonumber(offset_z) or 0)

    local attachment_index = 0
    if exists(unit) and type(unit.ScriptLookupAttachment) == "function" then
        local ok, result = pcall(
            unit.ScriptLookupAttachment, unit, attachment_name
        )
        if ok then attachment_index = tonumber(result) or 0 end
    end
    if attachment_index > 0
        and type(ParticleManager.SetParticleControlEnt) == "function" then
        ParticleManager:SetParticleControlEnt(
            particle, control_point, unit, PATTACH_POINT_FOLLOW,
            attachment_name, position, true
        )
        return
    end
    ParticleManager:SetParticleControl(particle, control_point, position)
end

local function lightning_particle(caster, source_unit, target_unit,
        source_position, target_position, particle_name)
    local particle = ParticleManager:CreateParticle(
        particle_name or DEFAULT_CHAIN_PARTICLE,
        PATTACH_CUSTOMORIGIN, caster)
    lightning_control_point(
        particle, 0, source_unit,
        source_unit == caster and "attach_attack1" or "attach_hitloc",
        source_position,
        source_unit == caster and LIGHTNING_SOURCE_OFFSET_Z
            or LIGHTNING_TARGET_OFFSET_Z
    )
    lightning_control_point(
        particle, 1, target_unit, "attach_hitloc", target_position,
        LIGHTNING_TARGET_OFFSET_Z
    )
    ParticleManager:ReleaseParticleIndex(particle)
end

local function deal(caster, target, amount, source_kind, tags)
    if not valid(target) then return end
    damage_service:Deal({
        attacker = caster,
        victim = target,
        base_damage = math.max(0, amount),
        damage_type = DAMAGE_TYPE_PHYSICAL,
        source_kind = source_kind or "script",
        can_crit = false,
        tags = tags or {},
    })
end

local function area_radius(skill, fallback)
    local configured = skill and skill.area
    if type(configured) == "table" then configured = configured[1] end
    return math.max(1, tonumber(configured) or fallback)
end

local function enemies_in_radius(caster, position, radius)
    return FindUnitsInRadius(
        caster:GetTeamNumber(), position, nil, radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false
    ) or {}
end

local function frost_impact_particle(caster, position, radius, particle_name)
    local particle = ParticleManager:CreateParticle(
        particle_name or "particles/units/heroes/hero_lich/lich_frost_nova.vpcf",
        PATTACH_WORLDORIGIN, caster
    )
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:SetParticleControl(particle, 1, Vector(radius, 0, 0))
    ParticleManager:ReleaseParticleIndex(particle)
end

local function apply_slow(caster, target, buff_id, duration, slow_pct)
    if not valid(caster) or not valid(target) then return end
    buff_manager.apply(caster, target, buff_id, {
        duration = duration,
        value = -math.abs(slow_pct),
    })
end

local function trigger_frost_attack(caster, primary, skill, damage)
    local radius = area_radius(skill, 100)
    local duration = math.max(
        0.1, tonumber(skill.duration) or DEFAULT_FROST_SLOW_DURATION
    )
    local position = primary:GetAbsOrigin()
    local particle_name = skill_effect_particle(
        caster, skill, "skill_impact",
        "particles/units/heroes/hero_lich/lich_frost_nova.vpcf",
        "tower_frost_lich_rime_lord"
    )
    frost_impact_particle(caster, position, radius, particle_name)
    play_tower_sound("tower_frost_attack", caster, primary, position)
    local hit_count = 0
    for _, target in ipairs(enemies_in_radius(caster, position, radius)) do
        if valid(target) then
            -- 主目标已由普通攻击造成伤害，只给其施加减速；其余目标承受
            -- 与本次普通攻击相同的物理范围伤害。
            if target ~= primary then
                deal(caster, target, damage, "splash", { "tower_frost_attack" })
            end
            apply_slow(
                caster, target, skill.buff_id,
                duration, FROST_SLOW_PCT
            )
            hit_count = hit_count + 1
        end
    end
    detailed_log(
        "[TowerFrost] HIT tower=%d target=%d radius=%.0f damage=%.1f targets=%d slow=%d duration=%.1f",
        caster:entindex(), primary:entindex(), radius, damage, hit_count,
        FROST_SLOW_PCT, duration
    )
end

local function blizzard_particle(caster, position, radius, particle_name)
    local particle = ParticleManager:CreateParticle(
        particle_name or
            "particles/units/heroes/hero_crystalmaiden/maiden_freezing_field_snow.vpcf",
        PATTACH_WORLDORIGIN, caster
    )
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:SetParticleControl(particle, 1, Vector(radius, radius, radius))
    return particle
end

local function blizzard_explosion_particle(caster, position, particle_name)
    local particle = ParticleManager:CreateParticle(
        particle_name or
            "particles/units/heroes/hero_crystalmaiden/maiden_freezing_field_explosion.vpcf",
        PATTACH_WORLDORIGIN, caster
    )
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:ReleaseParticleIndex(particle)
end

local function start_blizzard(caster, position, skill)
    if not valid(caster) then return end
    local radius = area_radius(skill, DEFAULT_BLIZZARD_RADIUS)
    local duration = math.max(
        0.1, tonumber(skill.duration) or DEFAULT_BLIZZARD_DURATION
    )
    local interval = math.max(
        0.1, tonumber(skill.damage_interval) or DEFAULT_BLIZZARD_INTERVAL
    )
    local multiplier = math.max(
        0, tonumber(skill.damage_multiplier)
            or DEFAULT_BLIZZARD_DAMAGE_MULTIPLIER
    )
    local damage = caster:GetAverageTrueAttackDamage(caster) * multiplier
    local tick_limit = math.max(1, math.floor(duration / interval + 0.001))
    local slow_duration = interval + 0.1
    local instance_id = string.format(
        "blizzard_%d_%d_%d", caster:entindex(),
        math.floor(GameRules:GetGameTime() * 1000), RandomInt(1, 999999)
    )
    local snow_particle_name = skill_effect_particle(
        caster, skill, "skill_persistent",
        "particles/units/heroes/hero_crystalmaiden/maiden_freezing_field_snow.vpcf",
        "tower_frost_crystal_maiden_winter_raven"
    )
    local explosion_particle_name = skill_effect_particle(
        caster, skill, "skill_strike",
        "particles/units/heroes/hero_crystalmaiden/maiden_freezing_field_explosion.vpcf",
        "tower_frost_crystal_maiden_winter_raven"
    )
    local snow = blizzard_particle(
        caster, position, radius, snow_particle_name
    )
    play_tower_sound("tower_ice_blizzard", caster, caster, position)
    local tick = 0
    detailed_log(
        "[TowerBlizzard] START tower=%d instance=%s radius=%.0f duration=%.1f interval=%.1f damage=%.1f",
        caster:entindex(), instance_id, radius, duration, interval, damage
    )
    scheduler.every(interval, function()
        tick = tick + 1
        if not valid(caster) then
            ParticleManager:DestroyParticle(snow, false)
            ParticleManager:ReleaseParticleIndex(snow)
            return false
        end
        blizzard_explosion_particle(caster, position, explosion_particle_name)
        local hit_count = 0
        for _, target in ipairs(enemies_in_radius(caster, position, radius)) do
            if valid(target) then
                deal(caster, target, damage, "ability", {
                    "tower_ice_blizzard", instance_id,
                    "tick_" .. tostring(tick),
                })
                apply_slow(
                    caster, target, skill.buff_id,
                    slow_duration, BLIZZARD_SLOW_PCT
                )
                hit_count = hit_count + 1
            end
        end
        detailed_log(
            "[TowerBlizzard] TICK tower=%d instance=%s tick=%d targets=%d",
            caster:entindex(), instance_id, tick, hit_count
        )
        if tick >= tick_limit then
            ParticleManager:DestroyParticle(snow, false)
            ParticleManager:ReleaseParticleIndex(snow)
            return false
        end
        return interval
    end, instance_id)
end

M._start_blizzard_for_test = start_blizzard
M._sync_polar_obelisk_aura_for_test = sync_polar_obelisk_aura

local function storm_radius(skill)
    local configured = skill.area
    if type(configured) == "table" then configured = configured[1] end
    return math.max(1, tonumber(configured) or DEFAULT_STORM_RADIUS)
end

local function storm_cloud_particle(caster, position, radius, duration,
        particle_name)
    local particle = ParticleManager:CreateParticle(
        particle_name or DEFAULT_STORM_CLOUD_PARTICLE,
        PATTACH_WORLDORIGIN, caster)
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:SetParticleControl(particle, 1, Vector(radius, radius, radius))
    -- Disruptor Static Storm reads its visual lifetime from CP2.x. It is only
    -- an area marker here; storm damage is settled once before visual timing.
    ParticleManager:SetParticleControl(
        particle, 2, Vector(duration, 0, 0)
    )
    return particle
end

local function storm_strike_particle(caster, position, particle_name)
    local particle = ParticleManager:CreateParticle(
        particle_name or DEFAULT_STORM_STRIKE_PARTICLE,
        PATTACH_WORLDORIGIN, caster)
    ParticleManager:SetParticleControl(
        particle, 0, position + Vector(0, 0, 900)
    )
    ParticleManager:SetParticleControl(particle, 1, position)
    ParticleManager:ReleaseParticleIndex(particle)
end

local function random_point_in_circle(position, radius)
    local angle = RandomFloat(0, math.pi * 2)
    local distance = radius * math.sqrt(RandomFloat(0, 1))
    return position + Vector(
        math.cos(angle) * distance,
        math.sin(angle) * distance,
        0
    )
end

local function apply_lightning_storm_damage(caster, position, radius, damage,
        instance_id)
    if not valid(caster) then return false end
    local enemies = enemies_in_radius(caster, position, radius)
    local hit_count = 0
    for _, target in ipairs(enemies or {}) do
        if valid(target) then
            deal(caster, target, damage, "ability", {
                "tower_lightning_storm", instance_id,
            })
            event_bus.emit(events.TOWER_LIGHTNING_HIT, {
                tower = caster,
                target = target,
                damage = damage,
                skills = tower_skills.get(caster),
                source = "lightning_storm",
                can_trigger_diffusion = true,
                instance_id = instance_id,
            })
            hit_count = hit_count + 1
        end
    end
    detailed_log(
        "[TowerLightningStorm] DAMAGE tower=%d instance=%s radius=%.0f damage=%.1f targets=%d",
        caster:entindex(), instance_id, radius, damage, hit_count
    )
    return true
end

start_lightning_storm = function(caster, position, skill)
    if not valid(caster) then return end
    local radius = storm_radius(skill)
    local duration = math.max(
        0.1, tonumber(skill.duration) or DEFAULT_STORM_DURATION
    )
    local strike_count = math.max(
        1, math.floor(tonumber(skill.strike_count) or 1)
    )
    local interval = duration / strike_count
    local damage_multiplier = math.max(
        0, tonumber(skill.damage_multiplier)
            or DEFAULT_STORM_DAMAGE_MULTIPLIER
    )
    local attack_damage_snapshot = caster:GetAverageTrueAttackDamage(caster)
    local damage = attack_damage_snapshot * damage_multiplier
    local instance_id = string.format(
        "storm_%d_%d_%d", caster:entindex(),
        math.floor(GameRules:GetGameTime() * 1000), RandomInt(1, 999999)
    )
    local cloud_particle_name = skill_effect_particle(
        caster, skill, "skill_persistent", DEFAULT_STORM_CLOUD_PARTICLE,
        LIGHTNING_ASSET_ID
    )
    local strike_particle_name = skill_effect_particle(
        caster, skill, "skill_strike", DEFAULT_STORM_STRIKE_PARTICLE,
        LIGHTNING_ASSET_ID
    )
    local cloud = storm_cloud_particle(
        caster, position, radius, duration, cloud_particle_name
    )
    play_tower_sound("tower_lightning_storm", caster, caster, position)
    apply_lightning_storm_damage(
        caster, position, radius, damage, instance_id
    )
    detailed_log(
        "[TowerLightningStorm] START tower=%d instance=%s radius=%.0f duration=%.2f visual_strikes=%d interval=%.3f multiplier=%.2f attack_snapshot=%.1f damage=%.1f",
        caster:entindex(), instance_id, radius, duration, strike_count,
        interval, damage_multiplier, attack_damage_snapshot, damage
    )
    local tick = 0
    local task_id
    task_id = scheduler.every(interval, function()
        tick = tick + 1
        if not valid(caster) then
            ParticleManager:DestroyParticle(cloud, false)
            ParticleManager:ReleaseParticleIndex(cloud)
            return false
        end
        storm_strike_particle(
            caster, random_point_in_circle(position, radius),
            strike_particle_name
        )
        if tick >= strike_count then
            ParticleManager:DestroyParticle(cloud, false)
            ParticleManager:ReleaseParticleIndex(cloud)
            detailed_log(
                "[TowerLightningStorm] END tower=%s instance=%s ticks=%d",
                valid(caster) and tostring(caster:entindex()) or "invalid",
                instance_id, tick
            )
            return false
        end
        return interval
    end, instance_id)
    return task_id
end

local function split_arrow(caster, target, damage, projectile_name)
    if not valid(caster) or not valid(target) then return end
    local distance = (target:GetAbsOrigin() - caster:GetAbsOrigin()):Length2D()
    ProjectileManager:CreateTrackingProjectile({
        Target = target,
        Source = caster,
        Ability = nil,
        EffectName = projectile_name
            or "particles/units/heroes/hero_drow/drow_base_attack.vpcf",
        iMoveSpeed = SPLIT_ARROW_SPEED,
        bDodgeable = false,
        bProvidesVision = false,
    })
    scheduler.after(distance / SPLIT_ARROW_SPEED, function()
        if valid(caster) and valid(target) then
            detailed_log(
                "[TowerMulti] HIT tower=%d target=%d raw_attack=%.1f multiplier=%.2f",
                caster:entindex(), target:entindex(), damage,
                MULTI_DAMAGE_MULTIPLIER
            )
            deal(caster, target, damage, "splash", { "tower_multi_arrow" })
        end
    end)
end

local function multi_max_targets(skill)
    local level = tonumber(string.match(skill.skill_id or "", "lv(%d+)$")) or 1
    return math.max(1, tonumber(skill.max_targets) or 1, math.min(7, level + 3))
end

local function nearest_unhit_enemy(caster, source_position, hit, radius)
    local units = FindUnitsInRadius(
        caster:GetTeamNumber(), source_position, nil,
        radius, DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false
    )
    for _, unit in ipairs(units or {}) do
        if valid(unit) and not hit[unit:entindex()] then return unit end
    end
    return nil
end

local function continue_lightning_chain(caster, source_unit, source_position,
        source_entindex,
        base_damage, hit_count,
        max_targets, hit, radius, particle_name)
    if hit_count >= max_targets or not valid(caster) then
        return
    end
    scheduler.after(LIGHTNING_BOUNCE_DELAY, function()
        if not valid(caster) then return end
        local next_target = nearest_unhit_enemy(
            caster, source_position, hit, radius
        )
        if not next_target then
            detailed_log(
                "[TowerLightning] END tower=%d from=%s hit=%d/%d reason=no_target_in_%d",
                caster:entindex(), tostring(source_entindex), hit_count,
                max_targets, radius
            )
            return
        end
        local next_count = hit_count + 1
        local multiplier = math.max(0, 1 - (next_count - 1) * 0.10)
        local next_position = next_target:GetAbsOrigin()
        hit[next_target:entindex()] = true
        lightning_particle(
            caster, source_unit, next_target,
            source_position, next_position, particle_name
        )
        detailed_log(
            "[TowerLightning] BOUNCE tower=%d from=%d target=%d hit=%d/%d multiplier=%.2f",
            caster:entindex(), source_entindex, next_target:entindex(),
            next_count, max_targets, multiplier
        )
        deal(caster, next_target, base_damage * multiplier, "ability", {
            "tower_chain_lightning", "bounce_" .. tostring(next_count),
        })
        event_bus.emit(events.TOWER_LIGHTNING_HIT, {
            tower = caster,
            target = next_target,
            damage = base_damage * multiplier,
            skills = tower_skills.get(caster),
            source = "chain_lightning",
            can_trigger_diffusion = true,
            hit_count = next_count,
        })
        continue_lightning_chain(
            caster, next_target, next_position, next_target:entindex(), base_damage,
            next_count, max_targets, hit, radius, particle_name
        )
    end)
end

local function destroy_particle(self)
    for _, segment in ipairs(self.laser_particles or {}) do
        ParticleManager:DestroyParticle(segment.index, false)
        ParticleManager:ReleaseParticleIndex(segment.index)
    end
    self.laser_particles = {}
end

local function reset_laser(self)
    destroy_particle(self)
    self.laser_target = nil
    self.laser_elapsed = 0
    self.laser_visual_elapsed = 0
end

local function update_laser_position(self, effect)
    if not valid(self.laser_target) then return end
    local caster = self:GetParent()
    local source = caster:GetAbsOrigin()
        + Vector(0, 0, tonumber(effect.source_offset_z) or 160)
    local target = self.laser_target:GetAbsOrigin()
        + Vector(0, 0, tonumber(effect.target_offset_z) or 70)
    -- Tinker laser reads control 9 as its source. Keep control 0 synchronized
    -- for alternate particle resources configured by CSV.
    for _, segment in ipairs(self.laser_particles or {}) do
        ParticleManager:SetParticleControl(segment.index, 9, source)
        ParticleManager:SetParticleControl(segment.index, 0, source)
        ParticleManager:SetParticleControl(segment.index, 1, target)
    end
end

local function create_laser_segment(self, effect, now)
    local index = ParticleManager:CreateParticle(
        effect.particle_name or
            "particles/units/heroes/hero_tinker/tinker_laser.vpcf",
        PATTACH_CUSTOMORIGIN, self:GetParent()
    )
    table.insert(self.laser_particles, {
        index = index,
        expires_at = now + math.max(
            0.03, tonumber(effect.visual_segment_duration) or 0.18
        ),
    })
    update_laser_position(self, effect)
end

local function start_laser(self, target, effect)
    if self.laser_target == target then return end
    reset_laser(self)
    self.laser_target = target
    self.laser_ticks = 0
    create_laser_segment(self, effect, GameRules:GetGameTime())
    play_tower_sound(
        "tower_laser", self:GetParent(), target, target:GetAbsOrigin()
    )
end

function modifier_tower_attack_effects:OnIntervalThink()
    if not IsServer() then return end
    local caster = self:GetParent()
    sync_polar_obelisk_aura(caster, self)
    local now = GameRules:GetGameTime()
    local elapsed = math.max(0, now - (self.last_interval_time or now))
    self.last_interval_time = now
    local laser = skill_matching(caster, "laser_")
    local effect = laser_config(laser)
    local target = self.laser_target
    if not laser or not effect or not valid(caster) or not valid(target)
        or target:GetTeamNumber() == caster:GetTeamNumber()
        or (target:GetAbsOrigin() - caster:GetAbsOrigin()):Length2D()
            > caster:GetAcquisitionRange() + 96 then
        reset_laser(self)
        return
    end
    local update_interval = math.max(
        0.01, tonumber(effect.beam_update_interval) or 0.03
    )
    if self.current_update_interval ~= update_interval then
        self.current_update_interval = update_interval
        self:StartIntervalThink(update_interval)
    end
    local visible = {}
    for _, segment in ipairs(self.laser_particles or {}) do
        if segment.expires_at > now then
            table.insert(visible, segment)
        else
            ParticleManager:DestroyParticle(segment.index, false)
            ParticleManager:ReleaseParticleIndex(segment.index)
        end
    end
    self.laser_particles = visible
    self.laser_visual_elapsed = self.laser_visual_elapsed + elapsed
    local visual_interval = math.max(
        update_interval, tonumber(effect.visual_refresh_interval) or 0.12
    )
    if self.laser_visual_elapsed + 0.001 >= visual_interval then
        self.laser_visual_elapsed = self.laser_visual_elapsed % visual_interval
        create_laser_segment(self, effect, now)
    end
    update_laser_position(self, effect)
    self.laser_elapsed = self.laser_elapsed + elapsed
    local interval = math.max(0.1, tonumber(laser.damage_interval) or 1)
    if self.laser_elapsed + 0.001 < interval then return end
    self.laser_elapsed = self.laser_elapsed - interval
    local base_multiplier = tonumber(laser.damage_multiplier) or 1
    local increment = (tonumber(effect.damage_increment_pct) or 5) / 100
    local maximum = math.max(
        base_multiplier, tonumber(effect.max_damage_multiplier) or 5
    )
    local multiplier = math.min(
        maximum, base_multiplier + (self.laser_ticks or 0) * increment
    )
    local base_damage = caster:GetAverageTrueAttackDamage(caster)
    local amount = base_damage * multiplier
    detailed_log(
        "[TowerMystery] LASER tower=%d target=%d tick=%d multiplier=%.2f raw_damage=%.1f buff_stacks=%d",
        caster:entindex(), target:entindex(), (self.laser_ticks or 0) + 1,
        multiplier, amount, 0
    )
    deal(caster, target, amount)
    self.laser_ticks = (self.laser_ticks or 0) + 1
end

function modifier_tower_attack_effects:OnAttackStart(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local caster = self:GetParent()
    local target = params.target
    self.current_attack_target = target
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    local attack_activity = rawget(_G, "ACT_DOTA_ATTACK")
    if DEATH_TOWER_ANIMATED_ASSETS[caster.survival_model_asset_id]
        and attack_activity ~= nil
        and type(caster.StartGesture) == "function" then
        pcall(
            caster.StartGesture,
            caster,
            attack_activity
        )
    end
    event_bus.emit(events.TOWER_ATTACK_START, {
        tower = caster,
        target = target,
        skills = tower_skills.get(caster),
    })
    local laser = skill_matching(caster, "laser_")
    local effect = laser_config(laser)
    if laser and effect and valid(target)
        and target:GetTeamNumber() ~= self:GetParent():GetTeamNumber() then
        start_laser(self, target, effect)
    end
end

function modifier_tower_attack_effects:OnAttack(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local caster, primary = self:GetParent(), params.target
    if not valid(primary) or primary:GetTeamNumber() == caster:GetTeamNumber() then
        return
    end
    play_tower_sound("tower_basic_attack", caster, caster)
    local multi = skill_matching(caster, "multi_attack_")
    if not multi then return end
    local max_targets = multi_max_targets(multi)
    local range = caster.Script_GetAttackRange
        and caster:Script_GetAttackRange()
        or caster:GetAcquisitionRange()
    local units = FindUnitsInRadius(
        caster:GetTeamNumber(), caster:GetAbsOrigin(), nil, range,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false
    )
    local damage = caster:GetAverageTrueAttackDamage(caster)
    local count = 1
    for _, target in ipairs(units or {}) do
        if target ~= primary and count < max_targets then
            -- 主箭与每支分裂箭均按100%当前攻击力结算。
            split_arrow(caster, target, damage, caster.survival_projectile_model)
            count = count + 1
        end
    end
    if count > 1 then
        play_tower_sound("tower_multi_attack", caster, caster)
    end
    detailed_log(
        "[TowerMulti] FIRE tower=%d primary=%d targets=%d max_targets=%d",
        caster:entindex(), primary:entindex(), count, max_targets
    )
end

function modifier_tower_attack_effects:OnAttackFail(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    self.attack_failed_diagnostic_count =
        (tonumber(self.attack_failed_diagnostic_count) or 0) + 1
    if self.attack_failed_diagnostic_count <= 20 then
        detailed_log(
            "[TOWER_ATTACK_RESULT] result=failed tower=%d target=%s "
                .. "failed=%d landed=%d",
            self:GetParent():entindex(),
            tostring(exists(params.target) and params.target:entindex() or -1),
            self.attack_failed_diagnostic_count,
            tonumber(self.attack_landed_diagnostic_count) or 0
        )
    end
end

function modifier_tower_attack_effects:OnAttackLanded(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local caster, primary = self:GetParent(), params.target
    if not exists(primary) or primary:GetTeamNumber() == caster:GetTeamNumber() then
        return
    end
    self.attack_landed_diagnostic_count =
        (tonumber(self.attack_landed_diagnostic_count) or 0) + 1
    if self.attack_landed_diagnostic_count <= 20 then
        detailed_log(
            "[TOWER_ATTACK_RESULT] result=landed tower=%d target=%d "
                .. "failed=%d landed=%d damage=%s",
            caster:entindex(), primary:entindex(),
            tonumber(self.attack_failed_diagnostic_count) or 0,
            self.attack_landed_diagnostic_count, tostring(params.damage)
        )
    end
    local skills = tower_skills.get(caster)
    local damage = caster:GetAverageTrueAttackDamage(caster)
    local critical_multiplier = tonumber(self.pending_critical_multiplier) or 1
    local landed_damage = tonumber(params.damage) or damage * critical_multiplier
    event_bus.emit(events.TOWER_ATTACK_LANDED, {
        tower = caster,
        target = primary,
        damage = landed_damage,
        critical = critical_multiplier > 1,
        critical_multiplier = critical_multiplier,
        critical_source = self.pending_critical_source,
        skills = skills,
    })
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    local frost = skill_matching(caster, "frost_attack_")
    if frost then
        trigger_frost_attack(caster, primary, frost, damage)
    end
    local blizzard = skill_matching(caster, "ice_blizzard_")
    if blizzard then
        local chance = math.max(
            0, math.min(100, tonumber(blizzard.trigger_chance_pct) or 0)
        )
        if RollPercentage(chance) then
            start_blizzard(caster, primary:GetAbsOrigin(), blizzard)
        end
    end
    local piercing = skill_matching(caster, "piercing_ballista_")
    if piercing and piercing.buff_id then
        buff_manager.apply(caster, primary, piercing.buff_id, {
            duration = math.max(0.1, tonumber(piercing.duration) or 3),
            value = -math.abs(tonumber(piercing.attack_armor_reduction) or 0),
        })
    end
    local bounty = skill_matching(caster, "bounty_machine_gun_")
    if bounty then
        local gold = math.max(0, tonumber(bounty.damage_multiplier) or 0)
        if gold > 0 then
            local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
                team = caster:GetTeamNumber(),
                gold = gold,
                reason = "tower_bounty_machine_gun_attack",
            })
            if result and result.ok == true then
                play_follow_particle(primary, skill_effect_particle(
                    caster,
                    bounty,
                    "skill_strike",
                    "particles/units/heroes/hero_bounty_hunter/bounty_hunter_cutpurse.vpcf",
                    MACHINE_GUN_ASSET_IDS.bounty
                ))
                play_tower_sound(
                    "tower_bounty_machine_gun", caster, primary
                )
            end
            detailed_log(
                "[TowerMachineGun] BOUNTY tower=%d target=%d gold=%.0f",
                caster:entindex(), primary:entindex(), gold
            )
        end
    end

    local gatling = skill_matching(caster, "explosive_gatling_")
    if gatling then
        local target_entindex = primary:entindex()
        if self.gatling_target_entindex ~= target_entindex then
            self.gatling_target_entindex = target_entindex
            self.gatling_target_hits = 0
        end
        self.gatling_target_hits = (self.gatling_target_hits or 0) + 1
        if self.gatling_target_hits >= GATLING_ATTACK_COUNT then
            self.gatling_target_hits = 0
            trigger_gatling_buff(caster, gatling, "same_target_5_hits")
        end
    end

    local lightning = nil
    for _, row in pairs(skills) do
        if row.skill_id and string.match(row.skill_id, "^lightning_strike_") then lightning = row end
    end
    local laser = skill_matching(caster, "laser_")
    local effect = laser_config(laser)
    if laser and effect then
        start_laser(self, primary, effect)
    end
    if lightning then
        local max_targets = math.max(1, tonumber(lightning.max_targets) or 1)
        local bounce_radius = area_radius(
            lightning, DEFAULT_LIGHTNING_BOUNCE_RADIUS
        )
        local hit = { [primary:entindex()] = true }
        local primary_position = primary:GetAbsOrigin()
        local particle_name = skill_effect_particle(
            caster, lightning, "skill_chain", DEFAULT_CHAIN_PARTICLE,
            LIGHTNING_ASSET_ID
        )
        lightning_particle(
            caster, caster, primary,
            caster:GetAbsOrigin(), primary_position, particle_name
        )
        play_tower_sound(
            "tower_lightning_strike", caster, primary, primary_position
        )
        event_bus.emit(events.TOWER_LIGHTNING_HIT, {
            tower = caster,
            target = primary,
            damage = landed_damage,
            skills = skills,
            source = "chain_lightning",
            can_trigger_diffusion = true,
            hit_count = 1,
        })
        detailed_log(
            "[TowerLightning] START tower=%d target=%d hit=1/%d multiplier=1.00 particle=%s",
            caster:entindex(), primary:entindex(), max_targets,
            tostring(particle_name)
        )
        continue_lightning_chain(
            caster, primary, primary_position, primary:entindex(), damage,
            1, max_targets, hit, bounce_radius, particle_name
        )
    end
end


function modifier_tower_attack_effects:OnDestroy()
    if not IsServer() then return end
    local tower = self:GetParent()
    reset_laser(self)
    buff_manager.remove_aura(tower, "debuff_polar_attack_slow")
    self.polar_obelisk_sound_active = false
end

function modifier_tower_attack_effects:ResetAfterRelocation()
    if not IsServer() then return end
    local tower = self:GetParent()
    reset_laser(self)
    buff_manager.remove_aura(tower, "debuff_polar_attack_slow")
    self.polar_obelisk_sound_active = false
    self.gatling_target_entindex = nil
    self.gatling_target_hits = 0
    self.current_attack_target = nil
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    self.last_interval_time = GameRules:GetGameTime()
    self.current_update_interval = nil
    self:StartIntervalThink(0.03)
end

local function initialize_slow(modifier, params, fallback)
    modifier.slow_pct = math.max(
        0, tonumber(params and params.slow_pct) or fallback
    )
end

modifier_tower_frost_slow = class({})
_G.modifier_tower_frost_slow = modifier_tower_frost_slow

function modifier_tower_frost_slow:IsHidden() return false end
function modifier_tower_frost_slow:IsDebuff() return true end
function modifier_tower_frost_slow:IsPurgable() return true end
function modifier_tower_frost_slow:GetTexture() return "lich_frost_nova" end
function modifier_tower_frost_slow:OnCreated(params)
    initialize_slow(self, params, FROST_SLOW_PCT)
end
function modifier_tower_frost_slow:OnRefresh(params)
    initialize_slow(self, params, self.slow_pct or FROST_SLOW_PCT)
end
function modifier_tower_frost_slow:DeclareFunctions()
    return { MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE }
end
function modifier_tower_frost_slow:GetModifierMoveSpeedBonus_Percentage()
    return -(self.slow_pct or FROST_SLOW_PCT)
end

modifier_tower_blizzard_slow = class({})
_G.modifier_tower_blizzard_slow = modifier_tower_blizzard_slow

function modifier_tower_blizzard_slow:IsHidden() return false end
function modifier_tower_blizzard_slow:IsDebuff() return true end
function modifier_tower_blizzard_slow:IsPurgable() return true end
function modifier_tower_blizzard_slow:GetTexture() return "crystal_maiden_freezing_field" end
function modifier_tower_blizzard_slow:OnCreated(params)
    initialize_slow(self, params, BLIZZARD_SLOW_PCT)
end
function modifier_tower_blizzard_slow:OnRefresh(params)
    initialize_slow(self, params, self.slow_pct or BLIZZARD_SLOW_PCT)
end
function modifier_tower_blizzard_slow:DeclareFunctions()
    return { MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE }
end
function modifier_tower_blizzard_slow:GetModifierMoveSpeedBonus_Percentage()
    return -(self.slow_pct or BLIZZARD_SLOW_PCT)
end

modifier_tower_explosive_gatling_buff = class({})
_G.modifier_tower_explosive_gatling_buff = modifier_tower_explosive_gatling_buff

function modifier_tower_explosive_gatling_buff:IsHidden() return false end
function modifier_tower_explosive_gatling_buff:IsDebuff() return false end
function modifier_tower_explosive_gatling_buff:IsPurgable() return false end
function modifier_tower_explosive_gatling_buff:GetTexture()
    return "drow_ranger_marksmanship"
end

function modifier_tower_explosive_gatling_buff:OnCreated(params)
    self.bonus_pct = math.max(0, tonumber(params and params.bonus_pct) or 20)
end

function modifier_tower_explosive_gatling_buff:OnRefresh(params)
    self.bonus_pct = math.max(
        0, tonumber(params and params.bonus_pct) or self.bonus_pct or 20
    )
end

function modifier_tower_explosive_gatling_buff:DeclareFunctions()
    return { MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE }
end

function modifier_tower_explosive_gatling_buff:GetModifierAttackSpeedPercentage()
    return self.bonus_pct or 0
end

return M