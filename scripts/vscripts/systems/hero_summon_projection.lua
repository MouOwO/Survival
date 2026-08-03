local event_bus = require("core/event_bus")
local events = require("core/events")
local heroes = require("config/generated/hero_definitions")
local altar_actions = require("config/generated/altar_actions")

local M = {}

local SUMMON_ABILITIES = {
    hero_doom = "ability_summon_doom",
    hero_shadow_fiend = "ability_summon_shadow_fiend",
    hero_axe = "ability_summon_axe",
    hero_drow_ranger = "ability_summon_drow_ranger",
    hero_monkey_king = "ability_summon_monkey_king",
    hero_blademaster = "ability_summon_blademaster",
}
local TRAVEL_ABILITIES = {
    "ability_enter_endless_training",
    "ability_enter_shadow_realm",
}
local TRAVEL_ACTION_BY_ABILITY = {}
for _, action in ipairs(altar_actions.rows or {}) do
    if action.enabled ~= false
        and action.ability_name
        and action.ability_name ~= "" then
        TRAVEL_ACTION_BY_ABILITY[action.ability_name] = action
    end
end

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function rebirth_level(player_id)
    local result = event_bus.request(
        events.HERO_PROGRESSION_GET_REQUEST,
        { player_id = player_id }
    )
    return tonumber(result and result.snapshot
        and result.snapshot.rebirth_level) or 0
end

function M.entitlements(player_id)
    local result = event_bus.request(
        events.PLAYER_ENTITLEMENT_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot or {
        vip = 0,
        values = {},
    }
end

local function option(definition, entitlement)
    local vip_required = definition.vip_required == true
    local available = not vip_required or entitlement.vip == 1
    return {
        hero_id = definition.hero_id,
        unit_name = definition.unit_name,
        display_name = definition.display_name,
        primary_attribute = definition.primary_attribute,
        vip_required = vip_required and 1 or 0,
        available = available and 1 or 0,
        disabled_reason = available and "" or "需要VIP权限",
        attack_range = tonumber(definition.attack_range) or 0,
        all_attributes_bonus =
            tonumber(definition.all_attributes_bonus) or 0,
        damage_multiplier =
            tonumber(definition.damage_multiplier) or 1,
        max_health_multiplier =
            tonumber(definition.max_health_multiplier) or 1,
        max_mana_multiplier =
            tonumber(definition.max_mana_multiplier) or 1,
        initial_skill_count =
            tonumber(definition.initial_skill_count) or 0,
        skill_capacity =
            tonumber(definition.skill_capacity) or 10,
        sort_order = tonumber(definition.sort_order) or 0,
        notes = definition.notes or "",
    }
end

function M.build(player_id, altar, city_level, summoned)
    local entitlement = M.entitlements(player_id)
    local options = {}
    for _, definition in ipairs(heroes.rows or {}) do
        if definition.enabled ~= false then
            table.insert(options, option(definition, entitlement))
        end
    end
    table.sort(options, function(a, b)
        return a.sort_order < b.sort_order
    end)

    return {
        player_id = player_id,
        altar_built = valid_entity(altar) and 1 or 0,
        city_level = city_level or 0,
        hero_summoned = summoned and 1 or 0,
        summoned_hero_id = summoned and summoned.hero_id or "",
        summoned_unit_name =
            summoned and summoned.unit_name or "",
        shop_unlocked = summoned and 1 or 0,
        vip = entitlement.vip or 0,
        heroes = options,
    }
end

function M.update_altar(player_id, altar, already_summoned)
    if not valid_entity(altar) then
        return
    end

    local entitlement = M.entitlements(player_id)
    local current_rebirth_level = rebirth_level(player_id)
    for hero_id, ability_name in pairs(SUMMON_ABILITIES) do
        local ability = altar:FindAbilityByName(ability_name)
        local definition = heroes.by_id[hero_id]
        if ability and definition then
            local vip_ok = definition.vip_required ~= true
                or entitlement.vip == 1
            ability:SetActivated(
                not already_summoned and vip_ok
            )
            ability:SetHidden(already_summoned == true)
        end
    end
    for _, ability_name in ipairs(TRAVEL_ABILITIES) do
        local ability = altar:FindAbilityByName(ability_name)
        if ability then
            local action = TRAVEL_ACTION_BY_ABILITY[ability_name] or {}
            local required_rebirth_level =
                tonumber(action.required_rebirth_level) or 0
            local unlocked = current_rebirth_level
                >= required_rebirth_level
            ability:SetHidden(already_summoned ~= true)
            ability:SetActivated(already_summoned == true and unlocked)
        end
    end
end

return M
