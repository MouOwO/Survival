local event_bus = require("core/event_bus")
local events = require("core/events")
local geometry = require("systems/tower_skill_geometry")

local M = {}
local death_state = {}

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
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

local function deal(attacker, victim, damage, tag)
    return event_bus.request(events.TOWER_SKILL_DAMAGE_REQUEST, {
        attacker = attacker,
        victim = victim,
        damage = damage,
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

local function trigger_path_skill(payload, prefix, fallback_width, tag)
    local skill = skill_matching(payload.skills, prefix)
    if not skill or not owns_ability(payload.tower, skill) then return end
    local damage = math.max(0, tonumber(payload.damage) or 0)
        * math.max(0, tonumber(skill.damage_multiplier) or 1)
    local start_pos = payload.tower:GetAbsOrigin()
    local end_pos = payload.target:GetAbsOrigin()
    for _, enemy in ipairs(geometry.enemies_in_path(
        payload.tower, start_pos, end_pos, fallback_width, payload.target
    )) do
        deal(payload.tower, enemy, damage, tag)
    end
end

local function on_attack_landed(payload)
    if not valid(payload.tower) or not valid(payload.target) then return end
    update_bone_counter(payload)
    trigger_death_grenade(payload)
    trigger_path_skill(payload, "arcane_eye_", 96, "arcane_eye")
    trigger_path_skill(
        payload, "burning_great_arrow_", 110, "burning_great_arrow"
    )
end

local function on_building_destroyed(payload)
    local entindex = tonumber(payload and (payload.entindex or payload.unit_entindex))
    if entindex then death_state[entindex] = nil end
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
    death_state = {}
    event_bus.handle_request(events.TOWER_CRITICAL_QUERY, critical_query)
    event_bus.subscribe(events.TOWER_ATTACK_START, on_attack_start)
    event_bus.subscribe(events.TOWER_ATTACK_LANDED, on_attack_landed)
    event_bus.subscribe(events.TOWER_LIGHTNING_HIT, on_lightning_hit)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
end

return M
