local event_bus = require("core/event_bus")
local events = require("core/events")
local damage_service = require("combat/damage_service")
local buff_manager = require("systems/buff_manager")

local M = {}

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function deal_damage(payload)
    if not valid(payload.attacker) or not valid(payload.victim) then
        return { success = false, error = "invalid_damage_entities" }
    end
    return damage_service:Deal({
        attacker = payload.attacker,
        victim = payload.victim,
        ability = payload.ability,
        base_damage = math.max(0, tonumber(payload.damage) or 0),
        damage_type = payload.damage_type or DAMAGE_TYPE_PHYSICAL,
        damage_flags = payload.damage_flags,
        source_kind = payload.source_kind or "ability",
        can_crit = false,
        tags = payload.tags or { "tower_special_skill" },
    })
end

local function apply_buff(payload)
    if not valid(payload.caster) or not valid(payload.target)
        or not payload.buff_id then
        return nil, "invalid_buff_request"
    end
    return buff_manager.apply(
        payload.caster,
        payload.target,
        payload.buff_id,
        payload.options or {}
    )
end

function M.init()
    event_bus.handle_request(events.TOWER_SKILL_DAMAGE_REQUEST, deal_damage)
    event_bus.handle_request(events.TOWER_SKILL_BUFF_REQUEST, apply_buff)
end

return M
