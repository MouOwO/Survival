local scheduler = require("core/scheduler")

local M = { runners = {} }
M.sound_service = require("core/sound_service")
local deal_group = nil
local exclusive_summons = {}
local shadow_raze_stacks = {}

local SHADOW_RAZE_PARTICLE =
    "particles/units/heroes/hero_nevermore/nevermore_shadowraze.vpcf"
local COUNTER_HELIX_PARTICLE =
    "particles/units/heroes/hero_axe/axe_attack_blur_counterhelix.vpcf"

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit.IsAlive and unit:IsAlive()
end

local function unit_key(unit)
    if not valid(unit) or not unit.entindex then return nil end
    return tostring(unit:entindex())
end

local function game_time()
    return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
end

local function level_value(definition, field, level, fallback)
    local values = definition[field]
    if type(values) == "table" then
        return tonumber(values[level]) or fallback or 0
    end
    return tonumber(values) or fallback or 0
end

local function base_attack_time(attack_speed)
    attack_speed = tonumber(attack_speed) or 0
    if attack_speed <= 0 then return nil end
    return 1 / attack_speed
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

local function summon_key(attacker, skill_id)
    local key = unit_key(attacker)
    return key and key .. ":" .. tostring(skill_id) or nil
end

function M.summon_locked(attacker, skill_id)
    local key = summon_key(attacker, skill_id)
    local state = key and exclusive_summons[key] or nil
    if not state then return false end
    if not alive(state.unit) or game_time() >= state.expires_at then
        exclusive_summons[key] = nil
        if alive(state.unit) then state.unit:ForceKill(false) end
        return false
    end
    return true
end

local function configure_summon(unit, context, attack, attack_speed, health, armor)
    unit:SetOwner(context.attacker)
    if unit.SetPlayerID then unit:SetPlayerID(context.player_id) end
    unit:SetControllableByPlayer(context.player_id, true)
    unit:SetBaseDamageMin(math.max(1, math.floor(attack)))
    unit:SetBaseDamageMax(math.max(1, math.floor(attack)))
    local attack_time = base_attack_time(attack_speed)
    if attack_time and unit.SetBaseAttackTime then
        unit:SetBaseAttackTime(attack_time)
        unit.survival_attack_speed = attack_speed
    end
    unit:SetPhysicalArmorBaseValue(tonumber(armor) or 0)
    unit:SetBaseMaxHealth(math.max(1, math.floor(health)))
    unit:SetMaxHealth(math.max(1, math.floor(health)))
    unit:SetHealth(math.max(1, math.floor(health)))
end

local function create_summon(context, definition, unit_name, invulnerable)
    local key = summon_key(context.attacker, context.skill_id)
    if not key or M.summon_locked(context.attacker, context.skill_id) then
        return false
    end
    local duration = level_value(definition, "duration", context.level, 10)
    local attack = (tonumber(context.attributes.attack) or 0)
        * level_value(definition, "attack_inherit_pct", context.level, 100) / 100
    local attack_speed = (tonumber(context.attributes.attack_speed) or 0)
        * level_value(
            definition, "attack_speed_inherit_pct", context.level, 100
        ) / 100
    local health = (tonumber(context.attributes.max_health) or 1)
        * level_value(definition, "health_inherit_pct", context.level, 100) / 100
    local armor = (tonumber(context.attributes.runtime_armor) or 0)
        * level_value(definition, "armor_inherit_pct", context.level, 100) / 100
    local position = context.attacker:GetAbsOrigin()
        + context.attacker:GetForwardVector() * 160
    local unit = CreateUnitByName(
        unit_name, position, true, context.attacker, context.attacker,
        context.attacker:GetTeamNumber()
    )
    if not valid(unit) then return false end
    configure_summon(unit, context, attack, attack_speed, health, armor)
    unit.survival_exclusive_summon = true
    unit.survival_summon_skill_id = context.skill_id
    if invulnerable then
        unit:AddNewModifier(
            context.attacker, nil,
            "modifier_survival_drow_companion_invulnerable", {}
        )
        unit.survival_drow_companion = true
        unit.survival_drow_max_targets = level_value(
            definition, "max_targets", context.level, 5
        )
        unit.survival_drow_attack_range = level_value(
            definition, "attack_range", context.level, 1200
        )
        unit:AddNewModifier(
            unit, nil, "modifier_weapon_attack_tracker",
            { player_id = context.player_id }
        )
    end
    local state = { unit = unit, expires_at = game_time() + duration }
    exclusive_summons[key] = state
    scheduler.after(duration, function()
        if exclusive_summons[key] ~= state then return end
        exclusive_summons[key] = nil
        if alive(unit) then unit:ForceKill(false) end
    end, "hero_exclusive_summon:" .. key)
    return true, unit
end

function M.runners.skill_doom_infernal(context, definition)
    local created, unit = create_summon(
        context, definition, "npc_survival_doom_infernal", false
    )
    if created then
        M.sound_service.play("hero_doom_infernal_spawn", {
            unit = unit,
            source = context.attacker,
        })
    end
    return created
end

function M.runners.skill_drow_companion(context, definition)
    local created = create_summon(
        context, definition, "npc_survival_drow_companion", true
    )
    return created
end

local function live_raze_layers(target, duration, maximum)
    local key = unit_key(target)
    if not key then return nil end
    local now = game_time()
    local layers = shadow_raze_stacks[key] or {}
    local kept = {}
    for _, expires_at in ipairs(layers) do
        if expires_at > now then kept[#kept + 1] = expires_at end
    end
    kept[#kept + 1] = now + duration
    while #kept > maximum do table.remove(kept, 1) end
    shadow_raze_stacks[key] = kept
    return kept
end

local function particle_at(name, owner, position)
    local ok, particle = pcall(
        ParticleManager.CreateParticle,
        ParticleManager,
        name,
        PATTACH_WORLDORIGIN,
        owner
    )
    if not ok then return end
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:ReleaseParticleIndex(particle)
end

function M.runners.skill_shadow_fiend_raze(context, definition)
    local radius = level_value(definition, "radius", context.level, 250)
    local duration = level_value(definition, "stack_duration", context.level, 3)
    local maximum = level_value(definition, "max_stacks", context.level, 5)
    local layers = live_raze_layers(context.target, duration, maximum)
    if not layers then return false end
    local base = level_value(definition, "damage_multiplier", context.level, 25)
    local bonus = level_value(
        definition, "damage_per_stack_pct", context.level, 10
    )
    local position = context.target:GetAbsOrigin()
    particle_at(SHADOW_RAZE_PARTICLE, context.attacker, position)
    M.sound_service.play("hero_shadow_raze_impact", {
        source = context.attacker,
        position = position,
    })
    deal_group(
        context,
        enemies_in_radius(context.attacker, position, radius),
        base * (1 + #layers * bonus / 100)
    )
    return true
end

function M.runners.skill_axe_counter_helix(context, definition)
    local position = context.target:GetAbsOrigin()
    particle_at(COUNTER_HELIX_PARTICLE, context.attacker, position)
    M.sound_service.play("hero_axe_counter_helix_impact", {
        source = context.attacker,
        position = position,
    })
    deal_group(
        context,
        enemies_in_radius(
            context.attacker, position,
            level_value(definition, "radius", context.level, 400)
        ),
        level_value(definition, "damage_multiplier", context.level, 30)
    )
    return true
end

function M.on_drow_companion_attack_fired(attacker, primary_target)
    if not alive(attacker) or not alive(primary_target)
        or attacker.survival_drow_companion ~= true then return false end
    M.sound_service.play("hero_drow_companion_volley", {
        unit = attacker,
        source = attacker,
    })
    local origin = attacker:GetAbsOrigin()
    local candidates = enemies_in_radius(
        attacker, origin, tonumber(attacker.survival_drow_attack_range) or 1200
    )
    table.sort(candidates, function(left, right)
        local lp, rp = left:GetAbsOrigin(), right:GetAbsOrigin()
        local ldx, ldy = lp.x - origin.x, lp.y - origin.y
        local rdx, rdy = rp.x - origin.x, rp.y - origin.y
        return ldx * ldx + ldy * ldy < rdx * rdx + rdy * rdy
    end)
    local fired = 1
    local maximum = math.max(1, tonumber(attacker.survival_drow_max_targets) or 5)
    for _, target in ipairs(candidates) do
        if fired >= maximum then break end
        if target ~= primary_target and alive(target) then
            attacker.survival_next_drow_secondary = true
            attacker:PerformAttack(
                target, false, false, true, false, true, false, false
            )
            attacker.survival_next_drow_secondary = nil
            fired = fired + 1
        end
    end
    return true
end

function M.init(dependencies)
    assert(type(dependencies and dependencies.deal_group) == "function")
    deal_group = dependencies.deal_group
    exclusive_summons = {}
    shadow_raze_stacks = {}
end

M._test = {
    base_attack_time = base_attack_time,
    live_raze_layers = live_raze_layers,
    active_summons = function() return exclusive_summons end,
}

return M