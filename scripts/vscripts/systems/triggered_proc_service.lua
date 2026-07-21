local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local seen_records, cooldowns = {}, {}

local function now()
    if GameRules and GameRules.GetGameTime then return GameRules:GetGameTime() end
    return os.clock()
end

local function attribute_total(unit)
    local total = 0
    for _, method_name in ipairs({ "GetStrength", "GetAgility", "GetIntellect" }) do
        local method = unit and unit[method_name]
        if type(method) == "function" then
            local ok, value = pcall(method, unit)
            if ok then total = total + (tonumber(value) or 0) end
        end
    end
    return total
end

local function valid_target(attacker, target)
    return attacker and target and not attacker:IsNull() and not target:IsNull()
        and attacker:GetTeamNumber() ~= target:GetTeamNumber()
end

local function damage_area(attacker, target, value)
    if not FindUnitsInRadius or not ApplyDamage then return end
    local damage = attribute_total(attacker) * (tonumber(value.multiplier) or 0)
    local units = FindUnitsInRadius(attacker:GetTeamNumber(), target:GetAbsOrigin(), nil,
        tonumber(value.range or value.radius), DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false) or {}
    for _, victim in ipairs(units) do
        ApplyDamage({ victim = victim, attacker = attacker, damage = damage,
            damage_type = DAMAGE_TYPE_MAGICAL, ability = nil })
    end
end

local function on_attack(payload)
    local player_id, record = tonumber(payload.player_id), tonumber(payload.record)
    if player_id == nil or record == nil or not valid_target(payload.attacker, payload.target) then return end
    seen_records[player_id] = seen_records[player_id] or {}
    if seen_records[player_id][record] then return end
    seen_records[player_id][record] = true
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
                    damage_area(payload.attacker, payload.target, value)
                    event_bus.emit(events.EQUIPMENT_PROC_TRIGGERED, {
                        player_id = player_id, record = record, source_id = source.source_id,
                        effect_type = effect.effect_type, target = payload.target,
                    })
                end
            end
        end
    end
end

function M.init()
    seen_records, cooldowns = {}, {}
    event_bus.subscribe(events.WEAPON_ATTACK_LANDED, on_attack)
end

return M
