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
local anti_air_rules = require("systems/anti_air_rules")
local tower_multi_damage = require("systems/tower_multi_damage")
local tower_laser_damage = require("systems/tower_laser_damage")

local detailed_diagnostics = global_rules.by_id.runtime_detailed_diagnostics
    and global_rules.by_id.runtime_detailed_diagnostics.enabled ~= false
    and tonumber(global_rules.by_id.runtime_detailed_diagnostics.value) == 1

local function detailed_log(format_string, ...)
    if detailed_diagnostics then
        print(string.format(format_string, ...))
    end
end

local DEFAULT_LIGHTNING_BOUNCE_RADIUS = 200
local LIGHTNING_BOUNCE_DELAY = 0.10
local LIGHTNING_SOURCE_OFFSET_Z = 160
local LIGHTNING_TARGET_OFFSET_Z = 70
local SPLIT_ARROW_SPEED = 1250
local DEFAULT_STORM_RADIUS = 500
local DEFAULT_STORM_DURATION = 5
local DEFAULT_STORM_DAMAGE_MULTIPLIER = 1
local GATLING_ATTACK_COUNT = 5
local DEFAULT_FROST_SLOW_DURATION = 2
local FROST_SLOW_PCT = 25
local DEFAULT_BLIZZARD_RADIUS = 300
local DEFAULT_BLIZZARD_DURATION = 4
local DEFAULT_BLIZZARD_INTERVAL = 1
local DEFAULT_BLIZZARD_DAMAGE_MULTIPLIER = 0.5
local BLIZZARD_SLOW_PCT = 25
local BLIZZARD_ICE_FALL_HEIGHT = 700
local BLIZZARD_ICE_FALL_DURATION = 0.35
local BLIZZARD_ICE_FALL_STEP = 0.03
local AIRSPACE_AURA_REFRESH_INTERVAL = 0.20
local AIRSPACE_AURA_BUFF_DURATION = 0.35
local start_lightning_storm
local exists
local valid
local area_radius
local enemies_in_radius

local LIGHTNING_ASSET_ID = "tower_zuus"
local MACHINE_GUN_ASSET_IDS = {
    bounty = "tower_machine_gun_bounty_heartless",
    gatling = "tower_machine_gun_windranger_rising_gale",
}
local MULTI_REPLACEMENT_ASSET_IDS = {
    tower_multi_medusa_anamnessa = true,
    tower_multi_drow_dread_retribution = true,
}
local LIGHTNING_ATTACK_PLAYBACK_RATE = 2
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

local function uses_multi_replacement_arrows(unit)
    return unit and MULTI_REPLACEMENT_ASSET_IDS[unit.survival_model_asset_id]
        and skill_matching(unit, "multi_attack_") ~= nil
end

local function uses_machine_gun_attack(unit)
    if unit and unit.survival_ultimate_tower then return false end
    return skill_matching(unit, "machine_gun_") ~= nil
        or skill_matching(unit, "bounty_machine_gun_") ~= nil
        or skill_matching(unit, "explosive_gatling_") ~= nil
end

local function laser_config(unit, skill)
    if not skill then return nil end
    local by_id = laser_effects.by_id or {}
    local asset_id = unit and unit.survival_model_asset_id or nil
    local row = asset_id and by_id[skill.skill_id .. ":" .. asset_id] or nil
    row = row or by_id[skill.skill_id .. ":default"] or by_id[skill.skill_id]
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
        MODIFIER_PROPERTY_BASE_ATTACK_TIME_CONSTANT,
        MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE,
    }
end

function modifier_tower_attack_effects:GetModifierCannotMiss()
    return tower_combat_rules.cannot_miss(self:GetParent()) and 1 or 0
end

function modifier_tower_attack_effects:GetModifierAttackSpeedPercentage()
    return 0
end

function modifier_tower_attack_effects:GetModifierBaseAttackTimeConstant()
    return nil
end

function modifier_tower_attack_effects:GetModifierDamageOutgoing_Percentage()
    local parent = self:GetParent()
    local skill = skill_matching(parent, "multi_attack_")
    if skill and not uses_multi_replacement_arrows(parent) then
        local multiplier = tower_multi_damage.multiplier(
            skill, self.current_attack_target
        )
        return (multiplier - 1) * 100
    end
    if skill_matching(parent, "anti_air_missile_") then
        return 90
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
    self.anti_air_sequence = 0
    self.anti_air_task_ids = {}
    self.anti_air_secondary_attack = false
    self.machine_gun_sequence = 0
    self.machine_gun_task_ids = {}
    if uses_machine_gun_attack(self:GetParent())
        and type(self:GetParent().SetRangedProjectileName) == "function" then
        self:GetParent():SetRangedProjectileName("")
        self:GetParent().survival_projectile_model = ""
    end
    self.airspace_aura_elapsed = AIRSPACE_AURA_REFRESH_INTERVAL
    self:StartIntervalThink(0.03)
end

local function sync_airspace_aura(modifier, tower, elapsed)
    modifier.airspace_aura_elapsed =
        (tonumber(modifier.airspace_aura_elapsed) or 0) + elapsed
    if modifier.airspace_aura_elapsed < AIRSPACE_AURA_REFRESH_INTERVAL then
        return
    end
    modifier.airspace_aura_elapsed = 0
    local skill = skill_matching(tower, "airspace_overlord_")
    if not skill or not valid(tower) then return end
    local radius = area_radius(skill, 500)
    for _, target in ipairs(enemies_in_radius(
            tower, tower:GetAbsOrigin(), radius)) do
        if valid(target) then
            buff_manager.apply(
                tower, target, "debuff_airspace_damage_taken",
                { duration = AIRSPACE_AURA_BUFF_DURATION }
            )
            if anti_air_rules.is_flying(target) then
                buff_manager.apply(
                    tower, target, "debuff_airspace_attack_slow",
                    { duration = AIRSPACE_AURA_BUFF_DURATION }
                )
            end
        end
    end
end

local function stop_anti_air_sequence(modifier)
    modifier.anti_air_sequence = (tonumber(modifier.anti_air_sequence) or 0) + 1
    for task_id in pairs(modifier.anti_air_task_ids or {}) do
        scheduler.cancel(task_id)
    end
    modifier.anti_air_task_ids = {}
    modifier.anti_air_secondary_attack = false
end

function modifier_tower_attack_effects:ResetAntiAirSequence()
    if not IsServer() then return end
    stop_anti_air_sequence(self)
end

local function start_anti_air_sequence(modifier, tower, target, skill)
    if not valid(target) or not anti_air_rules.is_flying(target) then
        return
    end
    local missile_count = math.max(1, math.floor(tonumber(skill.max_targets) or 1))
    if missile_count <= 1 then return end
    modifier.anti_air_sequence = (tonumber(modifier.anti_air_sequence) or 0) + 1
    local sequence = modifier.anti_air_sequence
    local interval = math.max(0.01, tonumber(skill.barrage_interval) or 0.1)
    modifier.anti_air_task_ids = modifier.anti_air_task_ids or {}
    for missile_index = 2, missile_count do
        local task_id = string.format(
            "tower_anti_air_sequence_%d_%d_%d",
            tower:entindex(), sequence, missile_index
        )
        modifier.anti_air_task_ids[task_id] = true
        scheduler.after(interval * (missile_index - 1), function()
            modifier.anti_air_task_ids[task_id] = nil
            if not valid(tower) or not valid(target)
                or not anti_air_rules.is_flying(target) then
                return false
            end
            modifier.anti_air_secondary_attack = true
            tower:PerformAttack(
                target, false, false, true, false, true, false, false
            )
            modifier.anti_air_secondary_attack = false
            return false
        end, task_id)
    end
end

local function trigger_drag_net(caster, target, skill)
    if not skill or not anti_air_rules.is_flying(target) then return false end
    local chance = math.max(
        0, math.min(100, tonumber(skill.trigger_chance_pct) or 0)
    )
    if not RollPercentage(chance) then return false end
    target:AddNewModifier(caster, nil, "modifier_stunned", {
        duration = math.max(0.1, tonumber(skill.duration) or 3),
    })
    return true
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
    local parent = self:GetParent()
    local effect = laser_config(parent, skill_matching(parent, "laser_"))
    return effect and math.max(0, tonumber(effect.attack_point) or 0) or nil
end

function modifier_tower_attack_effects:GetModifierTotalDamageOutgoing_Percentage(params)
    if self.machine_gun_instant_damage then
        return 0
    end
    if params and params.damage_category == DOTA_DAMAGE_CATEGORY_ATTACK
        and (uses_multi_replacement_arrows(self:GetParent())
            or skill_matching(self:GetParent(), "burning_great_arrow_")
            or uses_machine_gun_attack(self:GetParent())) then
        return -100
    end
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

local function roll_tower_critical(tower, target)
    local special = event_bus.request(events.TOWER_CRITICAL_QUERY, {
        tower = tower,
        target = target,
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
        multiplier = math.max(200,
            tonumber(tower.survival_gameplay_critical_damage_pct) or 200)
        source = "research_critical"
    end
    return multiplier > 100 and multiplier / 100 or 1, source
end

function modifier_tower_attack_effects:GetModifierPreAttack_CriticalStrike()
    if not IsServer() then return 0 end
    local tower = self:GetParent()
    if skill_matching(tower, "burning_great_arrow_")
        or uses_machine_gun_attack(tower) then
        return 0
    end
    if self.pending_critical_multiplier then
        return self.pending_critical_multiplier * 100
    end
    local multiplier, source = roll_tower_critical(
        tower, self.current_attack_target
    )
    if multiplier > 1 then
        self.pending_critical_multiplier = multiplier
        self.pending_critical_source = source
        return multiplier * 100
    end
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    return 0
end

exists = function(u) return u and not u:IsNull() end
valid = function(u) return exists(u) and u:IsAlive() end

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

local function deal(caster, target, amount, source_kind, tags, damage_type,
        physical_armor_ignore_pct)
    if not valid(target) then return nil end
    return damage_service:Deal({
        attacker = caster,
        victim = target,
        base_damage = math.max(0, amount),
        damage_type = damage_type or DAMAGE_TYPE_PHYSICAL,
        source_kind = source_kind or "script",
        can_crit = false,
        tags = tags or {},
        physical_armor_ignore_pct = physical_armor_ignore_pct,
    })
end

local function apply_machine_gun_hit_effects(modifier, tower, target)
    local bounty = skill_matching(tower, "bounty_machine_gun_")
    if bounty then
        local gold = math.max(0, tonumber(bounty.damage_multiplier) or 0)
        if gold > 0 then
            local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
                player_id = tonumber(tower.survival_player_id),
                team = tower:GetTeamNumber(),
                gold = gold,
                reason = "tower_bounty_machine_gun_attack",
            })
            if result and result.ok == true then
                play_follow_particle(target, skill_effect_particle(
                    tower, bounty, "skill_strike",
                    "particles/units/heroes/hero_bounty_hunter/bounty_hunter_cutpurse.vpcf",
                    MACHINE_GUN_ASSET_IDS.bounty
                ))
                play_tower_sound("tower_bounty_machine_gun", tower, target)
            end
        end
    end

    local gatling = skill_matching(tower, "explosive_gatling_")
    if not gatling then return end
    local target_entindex = target:entindex()
    if modifier.gatling_target_entindex ~= target_entindex then
        modifier.gatling_target_entindex = target_entindex
        modifier.gatling_target_hits = 0
    end
    modifier.gatling_target_hits = (modifier.gatling_target_hits or 0) + 1
    if modifier.gatling_target_hits >= GATLING_ATTACK_COUNT then
        modifier.gatling_target_hits = 0
        trigger_gatling_buff(tower, gatling, "same_target_5_hits")
    end
end

local function machine_gun_interval(tower, skill)
    local interval = math.max(0.01, tonumber(skill.barrage_interval) or 0.125)
    local bonus_pct = math.max(
        0, tonumber(buff_manager.value(
            tower, "buff_explosive_gatling_attack_speed"
        )) or 0
    )
    return interval / (1 + bonus_pct / 100)
end

local function fire_machine_gun_hit(modifier, tower, target, hit_index)
    if not valid(tower) or not valid(target)
        or target:GetTeamNumber() == tower:GetTeamNumber() then
        return false
    end
    local multiplier, source = roll_tower_critical(tower, target)
    modifier.machine_gun_instant_damage = true
    local ok, result = pcall(function()
        return deal(
            tower, target,
            tower:GetAverageTrueAttackDamage(tower) * multiplier,
            "script",
            { "tower_machine_gun_attack", "hit_" .. tostring(hit_index) }
        )
    end)
    modifier.machine_gun_instant_damage = false
    if not ok or not result or result.success ~= true then return false end
    event_bus.emit(events.TOWER_ATTACK_LANDED, {
        tower = tower,
        target = target,
        damage = tonumber(result.final_damage)
            or tower:GetAverageTrueAttackDamage(tower) * multiplier,
        critical = multiplier > 1,
        critical_multiplier = multiplier,
        critical_source = source,
        skills = tower_skills.get(tower),
    })
    apply_machine_gun_hit_effects(modifier, tower, target)
    return true
end

local function machine_gun_sequence_is_current(modifier, tower, sequence)
    if not modifier or modifier.machine_gun_sequence ~= sequence
        or not valid(tower) then
        return false
    end
    local ok, parent = pcall(function() return modifier:GetParent() end)
    return ok and parent == tower and valid(parent)
end

local function stop_machine_gun_sequences(modifier)
    modifier.machine_gun_sequence =
        (tonumber(modifier.machine_gun_sequence) or 0) + 1
    for task_id in pairs(modifier.machine_gun_task_ids or {}) do
        scheduler.cancel(task_id)
    end
    modifier.machine_gun_task_ids = {}
end

local function start_machine_gun_sequence(modifier, tower, target, skill)
    if not valid(tower) or not valid(target) then return end
    local hit_count = math.max(1, math.floor(tonumber(skill.max_targets) or 1))
    modifier.machine_gun_sequence =
        (tonumber(modifier.machine_gun_sequence) or 0) + 1
    local sequence = modifier.machine_gun_sequence
    modifier.machine_gun_task_ids = modifier.machine_gun_task_ids or {}
    local function fire(hit_index)
        if not machine_gun_sequence_is_current(modifier, tower, sequence) then
            return
        end
        if not fire_machine_gun_hit(modifier, tower, target, hit_index)
            or hit_index >= hit_count then
            return
        end
        local next_index = hit_index + 1
        local task_id = string.format(
            "tower_machine_gun_sequence_%d_%d_%d",
            tower:entindex(), sequence, next_index
        )
        modifier.machine_gun_task_ids[task_id] = true
        scheduler.after(machine_gun_interval(tower, skill), function()
            modifier.machine_gun_task_ids[task_id] = nil
            if not machine_gun_sequence_is_current(modifier, tower, sequence) then
                return false
            end
            fire(next_index)
            return false
        end, task_id)
    end
    fire(1)
end

local function trigger_chain_kill_storm(caster, target)
    if not exists(target) or target:IsAlive() or not is_arrow_tower(caster) then
        return
    end
    local storm = skill_matching(caster, "lightning_storm_")
    if storm and owns_skill_ability(caster, storm) then
        start_lightning_storm(caster, target:GetAbsOrigin(), storm)
    end
end

area_radius = function(skill, fallback)
    local configured = skill and skill.area
    if type(configured) == "table" then configured = configured[1] end
    return math.max(1, tonumber(configured) or fallback)
end

enemies_in_radius = function(caster, position, radius)
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
    local splash_multiplier = math.max(
        0, tonumber(skill.damage_multiplier) or 0.5
    )
    local splash_damage = damage * splash_multiplier
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
            if target ~= primary then
                deal(caster, target, splash_damage, "splash", {
                    "tower_frost_attack",
                })
            end
            apply_slow(
                caster, target, skill.buff_id,
                duration, FROST_SLOW_PCT
            )
            hit_count = hit_count + 1
        end
    end
    detailed_log(
        "[TowerFrost] HIT tower=%d target=%d radius=%.0f primary_damage=%.1f splash_damage=%.1f targets=%d slow=%d duration=%.1f",
        caster:entindex(), primary:entindex(), radius, damage, splash_damage,
        hit_count, FROST_SLOW_PCT, duration
    )
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

local function falling_ice_particle(caster, position, particle_name, on_impact)
    local particle = ParticleManager:CreateParticle(
        particle_name or
            "particles/units/heroes/hero_crystalmaiden/maiden_freezing_field_explosion.vpcf",
        PATTACH_WORLDORIGIN, caster
    )
    local elapsed = 0
    ParticleManager:SetParticleControl(
        particle, 0, position + Vector(0, 0, BLIZZARD_ICE_FALL_HEIGHT)
    )
    scheduler.every(BLIZZARD_ICE_FALL_STEP, function()
        if not valid(caster) then
            ParticleManager:DestroyParticle(particle, false)
            ParticleManager:ReleaseParticleIndex(particle)
            return false
        end
        elapsed = math.min(
            BLIZZARD_ICE_FALL_DURATION, elapsed + BLIZZARD_ICE_FALL_STEP
        )
        local progress = elapsed / BLIZZARD_ICE_FALL_DURATION
        ParticleManager:SetParticleControl(
            particle, 0,
            position + Vector(
                0, 0, BLIZZARD_ICE_FALL_HEIGHT * (1 - progress)
            )
        )
        if progress < 1 then return BLIZZARD_ICE_FALL_STEP end
        ParticleManager:DestroyParticle(particle, false)
        ParticleManager:ReleaseParticleIndex(particle)
        on_impact()
        return false
    end)
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
    local explosion_particle_name = skill_effect_particle(
        caster, skill, "skill_strike",
        "particles/units/heroes/hero_crystalmaiden/maiden_freezing_field_explosion.vpcf",
        "tower_frost_crystal_maiden_winter_raven"
    )
    local falling_particle_name = skill_effect_particle(
        caster, skill, "skill_chain",
        "particles/econ/items/crystal_maiden/crystal_maiden_maiden_of_icewrack/maiden_freezing_field_snow_arcana1_shard.vpcf",
        "tower_frost_crystal_maiden_winter_raven"
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
            return false
        end
        local angle = RandomFloat(0, math.pi * 2)
        local distance = radius * math.sqrt(RandomFloat(0, 1))
        local impact_position = position + Vector(
            math.cos(angle) * distance,
            math.sin(angle) * distance,
            0
        )
        local wave = tick
        falling_ice_particle(caster, impact_position, falling_particle_name,
            function()
                if not valid(caster) then return end
                blizzard_explosion_particle(
                    caster, impact_position, explosion_particle_name
                )
                local hit_count = 0
                for _, target in ipairs(
                        enemies_in_radius(caster, position, radius)) do
                    if valid(target) then
                        deal(caster, target, damage, "ability", {
                            "tower_ice_blizzard", instance_id,
                            "tick_" .. tostring(wave),
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
                    caster:entindex(), instance_id, wave, hit_count
                )
            end
        )
        if tick >= tick_limit then
            return false
        end
        return interval
    end, instance_id)
end

M._start_blizzard_for_test = start_blizzard
M._trigger_frost_attack_for_test = trigger_frost_attack
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

M._start_lightning_storm_for_test = start_lightning_storm

local function multi_attack_multiplier(skill, target)
    return tower_multi_damage.multiplier(skill, target)
end

local function split_arrow(caster, target, damage, projectile_name, multiplier,
        armor_ignore_pct)
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
                multiplier
            )
            deal(caster, target, damage * multiplier, "splash", {
                "tower_multi_arrow",
            }, nil, armor_ignore_pct)
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
        local result = deal(caster, next_target, base_damage * multiplier, "ability", {
            "tower_chain_lightning", "bounce_" .. tostring(next_count),
        })
        if result and result.success then
            trigger_chain_kill_storm(caster, next_target)
        end
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
        expires_at = effect.beam_mode == "continuous" and math.huge
            or now + math.max(
                0.03, tonumber(effect.visual_segment_duration) or 0.18
            ),
    })
    update_laser_position(self, effect)
end

local function start_laser(self, target, effect)
    if self.laser_target == target then return false end
    reset_laser(self)
    self.laser_target = target
    self.laser_ticks = 0
    create_laser_segment(self, effect, GameRules:GetGameTime())
    play_tower_sound(
        "tower_laser", self:GetParent(), target, target:GetAbsOrigin()
    )
    return true
end

local function deal_laser_tick(self, caster, target, laser, effect)
    local interval = math.max(0.1, tonumber(laser.damage_interval) or 1)
    local base_multiplier = tonumber(laser.damage_multiplier) or 1
    local increment = (tonumber(effect.damage_increment_pct) or 5) / 100
    local maximum = math.max(
        base_multiplier, tonumber(effect.max_damage_multiplier) or 5
    )
    local multiplier = tower_laser_damage.multiplier(
        base_multiplier, increment, maximum,
        self.laser_ticks or 0, interval
    )
    local amount = caster:GetAverageTrueAttackDamage(caster) * multiplier
    detailed_log(
        "[TowerMystery] LASER tower=%d target=%d tick=%d multiplier=%.2f raw_damage=%.1f buff_stacks=%d",
        caster:entindex(), target:entindex(), (self.laser_ticks or 0) + 1,
        multiplier, amount, 0
    )
    deal(caster, target, amount)
    event_bus.emit(events.TOWER_LASER_HIT, {
        tower = caster,
        target = target,
        damage = amount,
        skills = tower_skills.get(caster),
    })
    self.laser_ticks = (self.laser_ticks or 0) + 1
end

function modifier_tower_attack_effects:OnIntervalThink()
    if not IsServer() then return end
    local caster = self:GetParent()
    sync_polar_obelisk_aura(caster, self)
    local now = GameRules:GetGameTime()
    local elapsed = math.max(0, now - (self.last_interval_time or now))
    self.last_interval_time = now
    sync_airspace_aura(self, caster, elapsed)
    local laser = skill_matching(caster, "laser_")
    local effect = laser_config(caster, laser)
    local target = self.laser_target
    local active_attack_target = type(caster.GetAttackTarget) == "function"
        and caster:GetAttackTarget() or self.current_attack_target
    if not laser or not effect or not valid(caster) or not valid(target)
        or active_attack_target ~= target
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
    if effect.beam_mode ~= "continuous" then
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
    end
    update_laser_position(self, effect)
    self.laser_elapsed = self.laser_elapsed + elapsed
    local interval = math.max(0.1, tonumber(laser.damage_interval) or 1)
    if self.laser_elapsed + 0.001 < interval then return end
    self.laser_elapsed = self.laser_elapsed - interval
    deal_laser_tick(self, caster, target, laser, effect)
end

function modifier_tower_attack_effects:OnAttackStart(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local caster = self:GetParent()
    local target = params.target
    self.current_attack_target = target
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    local attack_activity = rawget(_G, "ACT_DOTA_ATTACK")
    local visual_asset = asset_catalog.get(caster.survival_model_asset_id)
    if visual_asset and visual_asset.native_wearable_stage
        and attack_activity ~= nil then
        if skill_matching(caster, "lightning_strike_")
            and type(caster.StartGestureWithPlaybackRate) == "function" then
            pcall(
                caster.StartGestureWithPlaybackRate,
                caster,
                attack_activity,
                LIGHTNING_ATTACK_PLAYBACK_RATE
            )
        elseif type(caster.StartGesture) == "function" then
            pcall(caster.StartGesture, caster, attack_activity)
        end
    end
    event_bus.emit(events.TOWER_ATTACK_START, {
        tower = caster,
        target = target,
        skills = tower_skills.get(caster),
    })
    local laser = skill_matching(caster, "laser_")
    local effect = laser_config(caster, laser)
    if laser and effect and valid(target)
        and target:GetTeamNumber() ~= self:GetParent():GetTeamNumber() then
        if start_laser(self, target, effect) then
            deal_laser_tick(self, caster, target, laser, effect)
        end
    end
end

function modifier_tower_attack_effects:OnAttack(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local caster, primary = self:GetParent(), params.target
    if not valid(primary) or primary:GetTeamNumber() == caster:GetTeamNumber() then
        return
    end
    local replacement_multi = uses_multi_replacement_arrows(caster)
    if not replacement_multi
        and not skill_matching(caster, "burning_great_arrow_")
        and not uses_machine_gun_attack(caster) then
        play_tower_sound("tower_basic_attack", caster, caster)
    end
    local machine_gun = skill_matching(caster, "machine_gun_")
    if machine_gun then
        start_machine_gun_sequence(self, caster, primary, machine_gun)
    end
    local anti_air = skill_matching(caster, "anti_air_missile_")
    if anti_air and not self.anti_air_secondary_attack then
        start_anti_air_sequence(self, caster, primary, anti_air)
    end
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
    if not replacement_multi then
        local burning = skill_matching(caster, "burning_great_arrow_") ~= nil
        local count = burning and 0 or 1
        local asset = asset_catalog.by_id[caster.survival_model_asset_id]
        local projectile_name = asset and asset.attack
            and asset.attack.projectile or caster.survival_projectile_model
        for _, target in ipairs(units or {}) do
            if target ~= primary and count < max_targets and valid(target) then
                split_arrow(
                    caster, target, damage, projectile_name,
                    multi_attack_multiplier(multi, target), 0
                )
                count = count + 1
            end
        end
        if count > 0 then
            play_tower_sound("tower_multi_attack", caster, caster)
        end
        return
    end
    local piercing = skill_matching(caster, "piercing_ballista_")
    local armor_ignore_pct = math.max(
        0, tonumber(piercing and piercing.attack_armor_reduction) or 0
    )
    local asset = asset_catalog.by_id[caster.survival_model_asset_id]
    local projectile_name = asset and asset.attack
        and asset.attack.projectile or caster.survival_projectile_model
    split_arrow(
        caster, primary, damage, projectile_name,
        multi_attack_multiplier(multi, primary), armor_ignore_pct
    )
    local count = 1
    for _, target in ipairs(units or {}) do
        if target ~= primary and count < max_targets and valid(target) then
            split_arrow(
                caster,
                target,
                damage,
                projectile_name,
                multi_attack_multiplier(multi, target),
                armor_ignore_pct
            )
            count = count + 1
        end
    end
    if count > 0 then
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
    if skill_matching(caster, "burning_great_arrow_") then
        self.pending_critical_multiplier = nil
        self.pending_critical_source = nil
        return
    end
    if uses_machine_gun_attack(caster) then
        self.pending_critical_multiplier = nil
        self.pending_critical_source = nil
        return
    end
    local skills = tower_skills.get(caster)
    local damage = caster:GetAverageTrueAttackDamage(caster)
    local critical_multiplier = tonumber(self.pending_critical_multiplier) or 1
    local lightning = skill_matching(caster, "lightning_strike_")
    local frost = skill_matching(caster, "frost_attack_")
    local landed_damage = damage * critical_multiplier
    if lightning then
        trigger_chain_kill_storm(caster, primary)
    end
    event_bus.emit(events.TOWER_ATTACK_LANDED, {
        tower = caster,
        target = primary,
        damage = landed_damage,
        critical = critical_multiplier > 1,
        critical_multiplier = critical_multiplier,
        critical_source = self.pending_critical_source,
        skills = skills,
    })
    if caster.survival_ultimate_tower then
        -- The ultimate tower keeps the bounty/gatling effects but deliberately
        -- does not enter the machine-gun multi-hit attack sequence.
        apply_machine_gun_hit_effects(self, caster, primary)
    end
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    local drag_net = skill_matching(caster, "drag_net_")
    trigger_drag_net(caster, primary, drag_net)
    if frost then
        trigger_frost_attack(caster, primary, frost, landed_damage)
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
    if piercing and piercing.buff_id
        and not uses_multi_replacement_arrows(caster)
        and not skill_matching(caster, "burning_great_arrow_") then
        buff_manager.apply(caster, primary, piercing.buff_id, {
            duration = math.max(0.1, tonumber(piercing.duration) or 3),
            value = -math.abs(tonumber(piercing.attack_armor_reduction) or 0),
        })
    end
    local lightning = nil
    for _, row in pairs(skills) do
        if row.skill_id and string.match(row.skill_id, "^lightning_strike_") then lightning = row end
    end
    local laser = skill_matching(caster, "laser_")
    local effect = laser_config(caster, laser)
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
    stop_anti_air_sequence(self)
    stop_machine_gun_sequences(self)
    reset_laser(self)
    buff_manager.remove_aura(tower, "debuff_polar_attack_slow")
    self.polar_obelisk_sound_active = false
end

function modifier_tower_attack_effects:OnRefresh()
    if not IsServer() then return end
    stop_anti_air_sequence(self)
    stop_machine_gun_sequences(self)
    self.gatling_target_entindex = nil
    self.gatling_target_hits = 0
    self.current_attack_target = nil
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
end

M._start_anti_air_sequence_for_test = start_anti_air_sequence
M._start_machine_gun_sequence_for_test = start_machine_gun_sequence
M._fire_machine_gun_hit_for_test = fire_machine_gun_hit
M._machine_gun_interval_for_test = machine_gun_interval
M._trigger_drag_net_for_test = trigger_drag_net
M._sync_airspace_aura_for_test = sync_airspace_aura
M._start_laser_for_test = start_laser
M._deal_laser_tick_for_test = deal_laser_tick
M._split_arrow_speed_for_test = SPLIT_ARROW_SPEED

function modifier_tower_attack_effects:ResetAfterRelocation()
    if not IsServer() then return end
    local tower = self:GetParent()
    stop_anti_air_sequence(self)
    stop_machine_gun_sequences(self)
    reset_laser(self)
    buff_manager.remove_aura(tower, "debuff_polar_attack_slow")
    self.polar_obelisk_sound_active = false
    self.gatling_target_entindex = nil
    self.gatling_target_hits = 0
    self.current_attack_target = nil
    self.pending_critical_multiplier = nil
    self.pending_critical_source = nil
    if uses_machine_gun_attack(tower)
        and type(tower.SetRangedProjectileName) == "function" then
        tower:SetRangedProjectileName("")
        tower.survival_projectile_model = ""
    end
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
