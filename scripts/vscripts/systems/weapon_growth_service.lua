local event_bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local technology_stat_manager = require("systems/technology_stat_manager")
local player_profile_service = require("systems/player_profile_service")

local M = {}
local state_by_player = {}
local FORGING_HAMMER_ID = "item_forging_hammer"
local FORGING_HAMMER_LIMIT = 4

local function requirement_reduction(player_id)
    local projected = event_bus.request(
        events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
        { player_id = player_id }
    )
    local totals = projected and projected.totals or {}
    local result = tonumber(totals.weapon_upgrade_requirement_reduction)
    if result == nil then
        local profile = player_profile_service.get_profile(player_id)
        local stats = profile and profile.save
            and profile.save.gameplay_stats or {}
        result = tonumber(stats.weapon_upgrade_requirement_reduction)
    end
    return math.max(0, math.floor(tonumber(result) or 0))
end

local function requirement_for(player_id, definition)
    local target = tonumber(definition and definition.progression_value) or 0
    if target <= 0 then target = 200 end
    return math.max(1, target - requirement_reduction(player_id))
end

local function state(player_id)
    state_by_player[player_id] = state_by_player[player_id] or {
        hero = nil,
        content_id = "",
        series_id = "",
        stage_attack_count = 0,
        lifetime_attack_count = 0,
        growth_attack = 0,
        growth_strength = 0,
        growth_agility = 0,
        growth_intellect = 0,
    }
    return state_by_player[player_id]
end

local function snapshot(player_id)
    local current = state(player_id)
    local definition = weapons.by_id[current.content_id] or {}
    local target = requirement_for(player_id, definition)
    local inventory = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    local counts = inventory and inventory.snapshot
        and inventory.snapshot.counts or {}
    local hammer_count = math.min(FORGING_HAMMER_LIMIT, math.max(
        0,
        math.floor(tonumber(counts[FORGING_HAMMER_ID]) or 0)
    ))
    local damage_growth = current.series_id == "ice_blade"
        or current.series_id == "epic_icefire"
        or current.series_id == "legend_abyss"
    return {
        player_id = player_id,
        content_id = current.content_id,
        series_id = current.series_id,
        stage = tonumber(definition.stage) or 0,
        stage_attack_count = current.stage_attack_count,
        stage_attack_target = target,
        stage_attack_remaining = math.max(0, target - current.stage_attack_count),
        forging_hammer_count = hammer_count,
        progress_per_attack = 1 + hammer_count,
        lifetime_attack_count = current.lifetime_attack_count,
        growth_attack = current.growth_attack,
        growth_strength = current.growth_strength,
        growth_agility = current.growth_agility,
        growth_intellect = current.growth_intellect,
        attack_gain_per_attack =
            tonumber(definition.attack_gain_per_attack) or 0,
        damage_gain_attack = damage_growth
            and (tonumber(definition.attack_gain_per_attack) or 0) or 0,
        damage_gain_all_attributes = damage_growth
            and (tonumber(definition.strength_gain_per_attack) or 0) or 0,
    }
end

local function publish(player_id, reason)
    event_bus.emit(events.WEAPON_GROWTH_CHANGED, {
        player_id = player_id,
        reason = reason or "changed",
        snapshot = snapshot(player_id),
    })
end

local function on_equipped(payload)
    if payload.slot ~= "main_hand" then
        return
    end
    local player_id = tonumber(payload.player_id)
    local current = state(player_id)
    local next_definition = weapons.by_id[payload.content_id] or {}
    local previous_definition = weapons.by_id[payload.previous_content_id] or {}
    local preserve = next_definition.preserve_growth_on_upgrade == true
        or (next_definition.series_id ~= ""
            and next_definition.series_id == previous_definition.series_id)
    if not preserve then
        current.growth_attack = 0
        current.growth_strength = 0
        current.growth_agility = 0
        current.growth_intellect = 0
        current.lifetime_attack_count = 0
    end
    if payload.content_id ~= payload.previous_content_id
        and payload.reason ~= "weapon_attack_upgrade" then
        current.stage_attack_count = 0
    end
    current.content_id = tostring(payload.content_id or "")
    current.series_id = tostring(next_definition.series_id or "")
    publish(player_id, "weapon_equipped")
end

local function upgrade_if_ready(player_id, current, definition)
    local target = requirement_for(player_id, definition)
    local next_id = tostring(definition.next_content_id or "")
    if definition.progression_type ~= "normal_attack_count"
        or target <= 0 or next_id == ""
        or current.stage_attack_count < target then
        return false
    end
    current.stage_attack_count = current.stage_attack_count - target
    local result = event_bus.request(
        events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
        {
            player_id = player_id,
            consume = { [current.content_id] = 1 },
            grant = { [next_id] = 1 },
            reason = "weapon_attack_upgrade",
        }
    )
    if not result or not result.ok then
        current.stage_attack_count = current.stage_attack_count + target
        return false
    end
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = "武器成长完成：" .. next_id,
        level = "info",
    })
    return true
end

local function add_attacks(
    player_id,
    progress_amount,
    reason,
    income_multiplier,
    growth_amount
)
    local current = state(player_id)
    local definition = weapons.by_id[current.content_id]
    if not definition or definition.enabled == false then
        return { ok = false, error = "weapon_not_equipped" }
    end
    local progress_count = math.max(
        0,
        math.floor(tonumber(progress_amount) or 0)
    )
    local growth_count = math.max(
        0,
        math.floor(tonumber(growth_amount) or progress_count)
    )
    if progress_count <= 0 or growth_count <= 0 then
        return { ok = false, error = "attack_count_invalid" }
    end
    local attack_gain = tonumber(definition.attack_gain_per_attack) or 0
    local strength_gain = tonumber(definition.strength_gain_per_attack) or 0
    local agility_gain = tonumber(definition.agility_gain_per_attack) or 0
    local intellect_gain = tonumber(definition.intellect_gain_per_attack) or 0
    local multiplier = math.max(1, tonumber(income_multiplier) or 1)
    current.stage_attack_count = current.stage_attack_count + progress_count
    current.lifetime_attack_count = current.lifetime_attack_count + growth_count
    current.growth_attack = current.growth_attack
        + attack_gain * growth_count * multiplier
    current.growth_strength = current.growth_strength
        + strength_gain * growth_count * multiplier
    current.growth_agility = current.growth_agility
        + agility_gain * growth_count * multiplier
    current.growth_intellect = current.growth_intellect
        + intellect_gain * growth_count * multiplier
    publish(player_id, reason or "attack_landed")
    local guard = 0
    while upgrade_if_ready(player_id, current, definition) do
        guard = guard + 1
        if guard >= 20 then
            break
        end
        definition = weapons.by_id[current.content_id]
        if not definition then
            break
        end
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

local function on_attack_landed(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or payload.is_main_attack == false then return end
    local data = snapshot(player_id)
    if data.series_id ~= "growth_sword" and data.series_id ~= "frost_blade" then
        return
    end
    local multiplier = technology_stat_manager.training_room_multiplier(
        player_id,
        payload.target
    )
    add_attacks(
        player_id,
        data.progress_per_attack,
        "attack_landed",
        multiplier,
        1
    )
end

local function valid_entity(entity)
    return entity and (not entity.IsNull or not entity:IsNull())
end

local function is_building(entity)
    return valid_entity(entity) and entity.IsBuilding and entity:IsBuilding()
end

local function entity_player_id(entity)
    if not valid_entity(entity) then return nil end
    local explicit = tonumber(entity.survival_player_id)
    if explicit and explicit >= 0 then return explicit end
    if not entity.GetPlayerOwnerID then return nil end
    local player_id = tonumber(entity:GetPlayerOwnerID())
    return player_id and player_id >= 0 and player_id or nil
end

local function damage_source_belongs_to_hero(player_id, attacker, owner_hero)
    local hero = state(player_id).hero
    if not valid_entity(hero) or owner_hero ~= hero or not valid_entity(attacker) then
        return false
    end
    local current = attacker
    local seen = {}
    for _ = 1, 8 do
        if not valid_entity(current) or seen[current] or is_building(current) then
            return false
        end
        seen[current] = true
        if current == hero
            or current.survival_owner_hero == hero
            or current.survival_hero_owner == hero then
            return true
        end
        -- The permanent Monkey King clone deliberately owns a Player entity
        -- rather than the hero and is isolated from the hero modifier stack.
        -- Its strict business identity plus matching player id is the only
        -- same-player exception; builders, workers and towers remain excluded.
        local explicit_clone = current.IsClone and current:IsClone()
        if (explicit_clone or current.survival_monkey_king_clone == true)
            and entity_player_id(current) == player_id then
            return true
        end
        if not current.GetOwnerEntity then return false end
        current = current:GetOwnerEntity()
    end
    return false
end

local function on_damage_dealt(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or (tonumber(payload.final_damage) or 0) <= 0 then return end
    local data = snapshot(player_id)
    if data.series_id ~= "ice_blade" and data.series_id ~= "epic_icefire"
        and data.series_id ~= "legend_abyss" then
        return
    end
    if not damage_source_belongs_to_hero(
            player_id, payload.attacker, payload.owner_hero) then
        return
    end
    local multiplier = technology_stat_manager.training_room_multiplier(
        player_id,
        payload.target
    )
    local current = state(player_id)
    local definition = weapons.by_id[current.content_id]
    if not definition then return end
    local attack_gain = tonumber(definition.attack_gain_per_attack) or 0
    local strength_gain = tonumber(definition.strength_gain_per_attack) or 0
    local agility_gain = tonumber(definition.agility_gain_per_attack) or 0
    local intellect_gain = tonumber(definition.intellect_gain_per_attack) or 0
    current.growth_attack = current.growth_attack
        + attack_gain * multiplier
    current.growth_strength = current.growth_strength
        + strength_gain * multiplier
    current.growth_agility = current.growth_agility
        + agility_gain * multiplier
    current.growth_intellect = current.growth_intellect
        + intellect_gain * multiplier
    publish(player_id, "damage_dealt")
end

local function on_hero_summoned(payload)
    if payload.unit and not payload.unit:IsNull() then
        state(tonumber(payload.player_id)).hero = payload.unit
        payload.unit:AddNewModifier(
            payload.unit,
            nil,
            "modifier_weapon_attack_tracker",
            { player_id = payload.player_id }
        )
    end
end

local function get_growth(payload)
    return { ok = true, snapshot = snapshot(tonumber(payload.player_id)) }
end

local function on_inventory_changed(payload)
    if payload.changes and payload.changes[FORGING_HAMMER_ID] then
        publish(tonumber(payload.player_id), "forging_hammer_changed")
    end
end

local function debug_add(payload)
    return add_attacks(
        tonumber(payload.player_id),
        tonumber(payload.count) or 1,
        "debug_attack_growth"
    )
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(events.WEAPON_GROWTH_GET_REQUEST, get_growth)
    event_bus.handle_request(events.WEAPON_GROWTH_DEBUG_REQUEST, debug_add)
    event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, on_equipped)
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_attack_landed)
    event_bus.subscribe(events.COMBAT_DAMAGE_RESOLVED, on_damage_dealt)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_inventory_changed)
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
end

return M
