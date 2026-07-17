local event_bus = require("core/event_bus")
local events = require("core/events")
local builder_config = require("config/builder_config")

local M = {}
local heroes_by_team = {}
local city_level_by_team = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function required_city_level(ability_name)
    local unlock = builder_config.unlocks and builder_config.unlocks[ability_name]
    return unlock and (unlock.city_level or 0) or 0
end

local function apply_team(team)
    local hero = heroes_by_team[team]
    if not valid_entity(hero) then return end

    local city_level = city_level_by_team[team] or 0
    for _, ability_name in ipairs(builder_config.abilities or {}) do
        local ability = hero:FindAbilityByName(ability_name)
        if ability and not ability:IsNull() then
            local unlocked = city_level >= required_city_level(ability_name)
            ability:SetActivated(unlocked)
        end
    end

    event_bus.emit(events.BUILDER_UNLOCK_CHANGED, {
        unit = hero,
        team = team,
        player_id = hero:GetPlayerOwnerID(),
        building_id = "builder",
        city_level = city_level,
    })
end

local function on_hero_ready(payload)
    if not valid_entity(payload.hero) then return end
    heroes_by_team[payload.team] = payload.hero
    apply_team(payload.team)
end

local function on_building_changed(payload)
    if payload.building_id ~= "main_city" then return end
    city_level_by_team[payload.team] = payload.level or 0
    apply_team(payload.team)
end

local function on_building_destroyed(payload)
    if payload.building_id ~= "main_city" then return end
    city_level_by_team[payload.team] = 0
    apply_team(payload.team)
end

function M.init()
    heroes_by_team = {}
    city_level_by_team = {}
    event_bus.subscribe(events.HERO_READY, on_hero_ready)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
end

return M
