local event_bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")

local M = {}
local seen_records, cooldowns = {}, {}
local diagnostic_count = 0
local DIAGNOSTIC_LIMIT = 40
local SEEN_ATTACK_LIMIT = 512
local FLAME_BURST_PARTICLE =
    "particles/units/heroes/hero_warlock/warlock_rain_of_chaos_explosion.vpcf"
local FLAME_BURST_SOUND = "Hero_Warlock.RainOfChaos"

local function now()
    if GameRules and GameRules.GetGameTime then return GameRules:GetGameTime() end
    return os.clock()
end

local function attribute_snapshot(player_id)
    local response = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
        player_id = player_id,
    })
    local stats = response and response.snapshot
    if not stats then return nil end
    local strength = tonumber(stats.strength) or 0
    local agility = tonumber(stats.agility) or 0
    local intellect = tonumber(stats.intellect) or 0
    return {
        strength = strength,
        agility = agility,
        intellect = intellect,
        total = strength + agility + intellect,
    }
end

local function valid_target(attacker, target)
    return attacker and target and not attacker:IsNull() and not target:IsNull()
        and attacker:GetTeamNumber() ~= target:GetTeamNumber()
end

local function play_flame_burst(attacker, position)
    if ParticleManager and ParticleManager.CreateParticle
        and ParticleManager.SetParticleControl
        and ParticleManager.ReleaseParticleIndex then
        pcall(function()
            local particle = ParticleManager:CreateParticle(
                FLAME_BURST_PARTICLE,
                PATTACH_WORLDORIGIN,
                attacker
            )
            ParticleManager:SetParticleControl(particle, 0, position)
            ParticleManager:ReleaseParticleIndex(particle)
        end)
    end
    if attacker.EmitSound then
        pcall(attacker.EmitSound, attacker, FLAME_BURST_SOUND)
    end
end

local function damage_area(player_id, attacker, value)
    if not FindUnitsInRadius then
        return { damage = 0, targets = 0, successes = 0, failures = 0,
            error = "find_units_unavailable" }
    end
    local attributes = attribute_snapshot(player_id)
    if not attributes then
        return { damage = 0, targets = 0, successes = 0, failures = 0,
            error = "hero_combat_snapshot_missing" }
    end
    local multiplier = tonumber(value.multiplier) or 0
    local damage = attributes.total * multiplier
    local position = attacker:GetAbsOrigin()
    local units = FindUnitsInRadius(attacker:GetTeamNumber(), position, nil,
        tonumber(value.range or value.radius), DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false) or {}
    local successes, failures, failure_reasons = 0, 0, {}
    for _, victim in ipairs(units) do
        local result = event_bus.request(combat_events.DEAL_REQUEST, {
            attacker = attacker, victim = victim, ability = nil,
            source_kind = "splash", base_damage = damage,
            damage_type = DAMAGE_TYPE_MAGICAL, can_crit = false,
            tags = { equipment_proc = true },
        })
        if result and result.success == true then
            successes = successes + 1
        else
            failures = failures + 1
            local reason = tostring(result and result.blocked_reason
                or "damage_request_unavailable")
            failure_reasons[reason] = (failure_reasons[reason] or 0) + 1
        end
    end
    play_flame_burst(attacker, position)
    return {
        attributes = attributes,
        damage = damage,
        multiplier = multiplier,
        radius = tonumber(value.range or value.radius) or 0,
        targets = #units,
        successes = successes,
        failures = failures,
        failure_reasons = failure_reasons,
    }
end

local function diagnose(player_id, record, source_id, result)
    if diagnostic_count >= DIAGNOSTIC_LIMIT then return end
    diagnostic_count = diagnostic_count + 1
    local attributes = result.attributes or {}
    local reasons = {}
    for reason, count in pairs(result.failure_reasons or {}) do
        reasons[#reasons + 1] = tostring(reason) .. ":" .. tostring(count)
    end
    table.sort(reasons)
    print(string.format(
        "[EQUIPMENT_FLAME_BURST] player=%s record=%s source=%s "
            .. "strength=%.1f agility=%.1f intellect=%.1f total=%.1f "
            .. "multiplier=%.1f damage=%.1f radius=%.1f targets=%s "
            .. "successes=%s failures=%s error=%s failure_reasons=%s",
        tostring(player_id), tostring(record), tostring(source_id),
        tonumber(attributes.strength) or 0,
        tonumber(attributes.agility) or 0,
        tonumber(attributes.intellect) or 0,
        tonumber(attributes.total) or 0,
        tonumber(result.multiplier) or 0,
        tonumber(result.damage) or 0,
        tonumber(result.radius) or 0,
        tostring(result.targets or 0),
        tostring(result.successes or 0),
        tostring(result.failures or 0),
        tostring(result.error or "none"),
        #reasons > 0 and table.concat(reasons, ",") or "none"
    ))
end

local function remember_attack(player_id, attack_key)
    local bucket = seen_records[player_id]
    if not bucket then
        bucket = { keys = {}, order = {} }
        seen_records[player_id] = bucket
    end
    if bucket.keys[attack_key] then return false end
    bucket.keys[attack_key] = true
    bucket.order[#bucket.order + 1] = attack_key
    if #bucket.order > SEEN_ATTACK_LIMIT then
        local expired = table.remove(bucket.order, 1)
        bucket.keys[expired] = nil
    end
    return true
end

local function on_attack(payload)
    local player_id, record = tonumber(payload.player_id), tonumber(payload.record)
    if player_id == nil or record == nil or payload.is_main_attack == false
        or payload.is_multishot_secondary == true
        or not valid_target(payload.attacker, payload.target) then return end
    local attack_key = tostring(payload.attack_id or record)
    if not remember_attack(player_id, attack_key) then return end
    local response = event_bus.request(events.EQUIPMENT_EFFECT_SNAPSHOT_GET_REQUEST,
        { player_id = player_id })
    local snapshot = response and response.snapshot
    if not snapshot or snapshot.enabled == false then return end
    cooldowns[player_id] = cooldowns[player_id] or {}
    for _, source in ipairs(snapshot.sources or {}) do
        for index, effect in ipairs(source.effects or {}) do
            if effect.effect_type == "proc_attribute_damage" then
                local value = effect.value
                local key = tostring(source.source_id) .. ":" .. tostring(index)
                local clock = now()
                local ready = cooldowns[player_id][key] or 0
                local chance = tonumber(value.probability or value.chance_pct
                    or value.chance) or 0
                if clock >= ready and RandomFloat(0, 100) < chance then
                    cooldowns[player_id][key] = clock
                        + (tonumber(value.internal_cooldown or value.cooldown) or 0)
                    local result = damage_area(player_id, payload.attacker, value)
                    diagnose(player_id, record, source.source_id, result)
                    event_bus.emit(events.EQUIPMENT_PROC_TRIGGERED, {
                        player_id = player_id, record = record,
                        source_id = source.source_id,
                        effect_type = effect.effect_type, target = payload.target,
                        center = payload.attacker,
                        damage = result.damage,
                        target_count = result.targets,
                        success_count = result.successes,
                        failure_count = result.failures,
                        error = result.error,
                    })
                end
            end
        end
    end
end

function M.init()
    seen_records, cooldowns, diagnostic_count = {}, {}, 0
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_attack)
end

return M
