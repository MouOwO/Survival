local event_bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local scheduler = require("core/scheduler")
local runtime_config = require("config/generated/blademaster_exclusive_runtime")

local M = {}
local states = {}
local sequence = 0
local storms = {}
local create_clone

local Q_SKILL = "skill_blademaster_exclusive"
local W_SKILL = "skill_blademaster_agility"
local R_SKILL = "skill_blademaster_mobility"
local Q_ABILITY = "ability_survival_blademaster_exclusive"
local E_ABILITY = "ability_survival_blademaster_swiftness"
local Q_PARTICLE = "particles/units/heroes/hero_legion_commander/legion_commander_odds.vpcf"
local E_PARTICLE = "particles/units/heroes/hero_juggernaut/juggernaut_blade_fury.vpcf"

local function row()
    return runtime_config.by_id.blademaster_exclusive or {}
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

local function stats(player_id)
    local result = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
        player_id = player_id,
    })
    return result and result.snapshot or {}
end

local function state(player_id)
    states[player_id] = states[player_id] or {
        attack_pct = 0,
        clone = nil,
        clone_respawning = false,
        growth_started = false,
    }
    return states[player_id]
end

local function all_attributes(snapshot)
    return math.max(0, tonumber(snapshot.strength) or 0)
        + math.max(0, tonumber(snapshot.agility) or 0)
        + math.max(0, tonumber(snapshot.intellect) or 0)
end

local function ability(unit, name)
    return valid(unit) and unit:FindAbilityByName(name) or nil
end

local function destroy_particle(particle, immediate)
    if not particle then return end
    ParticleManager:DestroyParticle(particle, immediate == true)
    ParticleManager:ReleaseParticleIndex(particle)
end

local function q_impact_visual(position, owner)
    if not position or not ParticleManager then return end
    local particle = ParticleManager:CreateParticle(
        Q_PARTICLE, PATTACH_WORLDORIGIN, owner
    )
    if not particle then return end
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:ReleaseParticleIndex(particle)
end

local function create_storm_visual(position, owner)
    if not position or not ParticleManager then return nil end
    local particle = ParticleManager:CreateParticle(
        E_PARTICLE, PATTACH_WORLDORIGIN, owner
    )
    if not particle then return nil end
    ParticleManager:SetParticleControl(particle, 0, position)
    local radius = math.max(1, tonumber(row().e_visual_radius) or 600)
    ParticleManager:SetParticleControl(particle, 1, Vector(radius, 0, 0))
    return particle
end

local function deal(player_id, attacker, target, ability_name, damage, source)
    sequence = sequence + 1
    return event_bus.request(combat_events.DEAL_REQUEST, {
        transaction_id = string.format("blademaster:%s:%d:%d",
            source, player_id, sequence),
        attacker = attacker,
        victim = target,
        ability = ability(attacker, ability_name),
        source_kind = "ability",
        base_damage = math.max(0, tonumber(damage) or 0),
        damage_type = DAMAGE_TYPE_PURE,
        can_crit = false,
        tags = {
            blademaster_exclusive = true,
            source = source,
            non_recursive = true,
        },
    })
end

local function q_replicate(payload)
    if not payload or tonumber(payload.player_id) == nil
        or not skill_active(payload.player_id, Q_SKILL)
        or payload.critical ~= true
        or payload.is_main_attack ~= true
        or payload.blademaster_secondary == true then return false end
    local target = payload.target
    local attacker = payload.attacker
    if not alive(attacker) or not alive(target)
        or attacker.survival_hero_id ~= "hero_blademaster"
        or attacker.survival_blademaster_clone == true then return false end
    local damage = math.max(0, tonumber(payload.final_damage) or 0)
    if damage <= 0 then return false end
    q_impact_visual(target:GetAbsOrigin(), attacker)
    for _, enemy in ipairs(FindUnitsInRadius(
        attacker:GetTeamNumber(), target:GetAbsOrigin(), nil,
        math.max(1, tonumber(row().q_radius) or 600),
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false) or {}) do
        if alive(enemy) then
            deal(payload.player_id, attacker, enemy, Q_ABILITY, damage, "q_copy")
        end
    end
    return true
end

local function storm_tick(id)
    local storm = storms[id]
    if not storm or not alive(storm.attacker)
        or GameRules:GetGameTime() >= storm.expires_at then
        if storm then destroy_particle(storm.particle, true) end
        storms[id] = nil
        return false
    end
    local snapshot = storm.snapshot
    local damage = all_attributes(snapshot)
        * math.max(0, tonumber(row().e_attribute_multiplier) or 0)
    for _, enemy in ipairs(FindUnitsInRadius(
        storm.attacker:GetTeamNumber(), storm.position, nil,
        math.max(1, tonumber(row().e_radius) or 600),
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false) or {}) do
        if alive(enemy) then
            deal(storm.player_id, storm.attacker, enemy, E_ABILITY, damage, "e_tick")
        end
    end
    return true
end

local function start_storm(payload)
    local id = tostring(payload.player_id) .. ":" .. tostring(payload.attacker:entindex())
    if storms[id] then return false end
    local duration = math.max(0.1, tonumber(row().e_duration) or 3)
    storms[id] = {
        player_id = payload.player_id,
        attacker = payload.attacker,
        position = payload.target:GetAbsOrigin(),
        snapshot = stats(payload.player_id),
        expires_at = GameRules:GetGameTime() + duration,
    }
    storms[id].particle = create_storm_visual(
        storms[id].position, payload.attacker
    )
    scheduler.every(math.max(0.1, tonumber(row().e_tick_interval) or 1),
        function() return storm_tick(id) end, "blademaster_storm:" .. id)
    return true
end

local function on_attack_landed(payload)
    local attacker = payload and payload.attacker
    if not alive(attacker) or payload.is_main_attack ~= true
        or attacker.survival_hero_id ~= "hero_blademaster"
        or attacker.survival_blademaster_clone == true
        or payload.is_multishot_secondary == true then return end
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    if skill_active(player_id, "skill_blademaster_swiftness")
        and RollPercentage(tonumber(row().e_proc_chance_pct) or 0) then
        start_storm({ player_id = player_id, attacker = attacker, target = payload.target })
    end
end

create_clone = function(player_id)
    local current = state(player_id)
    local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, { player_id = player_id })
    local hero = summoned and summoned.unit
    if alive(current.clone) or not alive(hero) or not skill_active(player_id, W_SKILL) then return nil end
    local clone = CreateUnitByName(hero:GetUnitName(), hero:GetAbsOrigin(), true,
        hero, hero, hero:GetTeamNumber())
    if not valid(clone) then return nil end
    clone:SetPlayerID(player_id)
    clone:SetControllableByPlayer(player_id, true)
    clone.survival_blademaster_clone = true
    clone.survival_permanent_summon = true
    clone.survival_hero_id = "hero_blademaster"
    local snapshot = stats(player_id)
    clone:SetBaseDamageMin(tonumber(snapshot.attack_min) or 1)
    clone:SetBaseDamageMax(tonumber(snapshot.attack_max) or 1)
    clone:SetBaseAttackTime(math.max(0.1, tonumber(snapshot.base_attack_time) or 1))
    clone.survival_critical_chance_pct = math.max(0,
        tonumber(snapshot.critical_chance_pct) or 0)
    clone.survival_critical_damage_pct = math.max(100,
        tonumber(snapshot.critical_damage_pct) or 200)
        + math.max(0, tonumber(row().w_clone_critical_damage_bonus_pct) or 0)
    local q_ability = clone:AddAbility(Q_ABILITY)
    if q_ability then q_ability:SetLevel(1) end
    current.clone = clone
    return clone
end

local function growth_tick(player_id)
    if not skill_active(player_id, R_SKILL) then return end
    state(player_id).attack_pct = state(player_id).attack_pct
        + math.max(0, tonumber(row().r_growth_pct) or 0)
    event_bus.emit(events.BLADEMASTER_BONUS_STATS_CHANGED, {
        player_id = player_id,
        snapshot = { attack_pct = state(player_id).attack_pct },
        reason = "blademaster_r_growth",
    })
end

local function on_entity_killed(payload)
    local victim = payload and payload.victim
    if not valid(victim) or victim.survival_blademaster_clone ~= true then return end
    local player_id = tonumber(victim:GetPlayerOwnerID())
    if player_id == nil then return end
    local current = state(player_id)
    current.clone = nil
    if current.clone_respawning or not skill_active(player_id, W_SKILL) then return end
    current.clone_respawning = true
    scheduler.after(1, function()
        current.clone_respawning = false
        create_clone(player_id)
    end, "blademaster_clone_respawn:" .. tostring(player_id))
end

function M.init()
    states = {}
    storms = {}
    sequence = 0
    event_bus.handle_request(events.BLADEMASTER_BONUS_STATS_GET_REQUEST,
        function(payload)
            local current = state(tonumber(payload and payload.player_id))
            return { ok = true, snapshot = { attack_pct = current.attack_pct } }
        end)
    event_bus.subscribe(events.HERO_FINAL_CRITICAL_ATTACK_DAMAGE, q_replicate)
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_attack_landed)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    event_bus.subscribe(events.HERO_SKILL_CHANGED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if player_id and skill_active(player_id, W_SKILL) then create_clone(player_id) end
    end)
    scheduler.every(1, function()
        for player_id, current in pairs(states) do
            if skill_active(player_id, R_SKILL)
                and GameRules:GetGameTime() % math.max(1, tonumber(row().r_growth_interval) or 150) < 1 then
                if not current._growth_second or current._growth_second ~= math.floor(GameRules:GetGameTime()) then
                    current._growth_second = math.floor(GameRules:GetGameTime())
                    growth_tick(player_id)
                end
            end
        end
        return true
    end, "blademaster_growth")
end

M._test = { q_replicate = q_replicate, start_storm = start_storm, growth_tick = growth_tick }
return M