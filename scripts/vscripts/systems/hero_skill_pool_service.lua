local event_bus = require("core/event_bus")
local events = require("core/events")
local skills = require("config/generated/hero_skill_definitions")
local passive_skills = require("config/hero_passive_skill_definitions")
local pool_members = require("config/generated/hero_skill_pool_members")

local M = {}
local PUBLIC_SKILL_CAPACITY = 3

local function owned_map(snapshot)
    local result = {}
    for _, item in ipairs(snapshot.skills or {}) do
        result[item.skill_id] = tonumber(item.level) or 0
    end
    return result
end

local function public_skill_count(snapshot)
    local count = tonumber(snapshot and snapshot.public_skill_count)
    if count ~= nil then return math.max(0, math.floor(count)) end
    for _, item in ipairs(snapshot and snapshot.skills or {}) do
        local definition = skills.by_id[item.skill_id]
        if definition and definition.is_public == true
            and (tonumber(item.level) or 0) > 0 then
            count = (count or 0) + 1
        end
    end
    return count or 0
end

local function progression_level(player_id)
    local result = event_bus.request(
        events.HERO_PROGRESSION_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot
        and tonumber(result.snapshot.rebirth_level) or 0
end

local function vip_enabled(player_id)
    local result = event_bus.request(
        events.PLAYER_ENTITLEMENT_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot
        and result.snapshot.vip == 1
end

local function state_for(player_id)
    local result = event_bus.request(
        events.HERO_SKILL_STATE_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot or nil
end

local function eligible(payload)
    local state = state_for(payload.player_id)
    if not state or state.hero_ready ~= 1 then
        return nil, "combat_hero_not_ready"
    end

    local rebirth = tonumber(payload.rebirth_level)
        or progression_level(payload.player_id)
    local owned = owned_map(state)
    local public_count = public_skill_count(state)
    local public_capacity = tonumber(state.public_skill_capacity)
        or PUBLIC_SKILL_CAPACITY
    local vip = vip_enabled(payload.player_id)
    local result = {}

    for _, member in ipairs(pool_members.rows or {}) do
        local definition = skills.by_id[member.skill_id]
        local minimum = tonumber(member.min_rebirth_level) or 0
        local maximum = tonumber(member.max_rebirth_level) or 999
        local current = owned[member.skill_id] or 0
        local can_add = current == 0
            and state.skill_count < state.skill_capacity
            and public_count < public_capacity

        if member.enabled ~= false
            and member.pool_id == payload.pool_id
            and definition
            and definition.enabled ~= false
            and definition.is_public == true
            and rebirth >= minimum
            and rebirth <= maximum
            and (definition.vip_only ~= true or vip)
            and can_add then
            table.insert(result, {
                member = member,
                definition = definition,
                current_level = current,
            })
        end
    end
    return result, nil
end

local function choose_weighted(candidates)
    local total = 0
    for _, item in ipairs(candidates) do
        total = total + math.max(
            0,
            tonumber(item.member.weight)
                or tonumber(item.definition.base_weight)
                or 0
        )
    end
    if total <= 0 then
        return table.remove(candidates, 1)
    end

    local roll = RandomFloat and RandomFloat(0, total)
        or math.random() * total
    local cursor = 0
    for index, item in ipairs(candidates) do
        cursor = cursor + math.max(
            0,
            tonumber(item.member.weight)
                or tonumber(item.definition.base_weight)
                or 0
        )
        if roll <= cursor then
            return table.remove(candidates, index)
        end
    end
    return table.remove(candidates, #candidates)
end

local function project(item)
    local definition = item.definition
    local passive = passive_skills.by_id[definition.skill_id]
    local next_level = item.current_level + 1
    return {
        skill_id = definition.skill_id,
        ability_name = definition.ability_name,
        display_name = definition.display_name,
        description = definition.description,
        icon_name = definition.icon_name,
        current_level = item.current_level,
        next_level = item.current_level + 1,
        max_level = tonumber(definition.max_level) or 1,
        is_upgrade = item.current_level > 0 and 1 or 0,
        passive = passive and 1 or 0,
        trigger_type = passive and passive.trigger_type or "",
        trigger_chance = passive and passive.trigger_chance[next_level] or 0,
        damage_multiplier = passive and passive.damage_multiplier[next_level] or 0,
        effect = passive and passive.level_text[next_level] or definition.description,
        current_trigger_chance = passive and item.current_level > 0
            and passive.trigger_chance[item.current_level] or 0,
        current_damage_multiplier = passive and item.current_level > 0
            and passive.damage_multiplier[item.current_level] or 0,
        current_effect = passive and item.current_level > 0
            and passive.level_text[item.current_level] or "",
    }
end

local function draw_request(payload)
    local candidates, error_code = eligible(payload)
    if not candidates then
        return { ok = false, error = error_code }
    end

    local count = math.max(1, tonumber(payload.choice_count) or 3)
    local selected = {}
    while #selected < count and #candidates > 0 do
        table.insert(selected, project(choose_weighted(candidates)))
    end

    if #selected == 0 then
        return { ok = false, error = "skill_pool_empty" }
    end
    return { ok = true, candidates = selected }
end

function M.init()
    event_bus.handle_request(
        events.HERO_SKILL_POOL_DRAW_REQUEST,
        draw_request
    )
end

return M
