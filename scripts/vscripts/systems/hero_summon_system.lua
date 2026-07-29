local event_bus = require("core/event_bus")
local events = require("core/events")
local ability_utils = require("core/ability_utils")
local heroes = require("config/generated/hero_definitions")
local summon_rules = require("config/generated/hero_summon_rules")
local stat_adapter = require("systems/hero_stat_adapter")
local cosmetic_service = require("systems/hero_cosmetic_service")
local projection = require("systems/hero_summon_projection")

local M = {}

local altar_by_team = {}
local builder_by_player = {}
local city_level_by_team = {}
local summoned_by_player = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function rule()
    return summon_rules.rows and summon_rules.rows[1] or {
        max_summoned_heroes = 1,
        requires_city_level = 3,
        shop_unlock_after_summon = true,
    }
end

local function current_summon(player_id)
    local state = summoned_by_player[player_id]
    return state and valid_entity(state.unit) and state or nil
end

local function snapshot(player_id)
    local team = PlayerResource:GetTeam(player_id)
    return projection.build(
        player_id,
        altar_by_team[team],
        city_level_by_team[team] or 0,
        current_summon(player_id)
    )
end

local function publish(player_id, reason)
    if not valid_player_id(player_id) then
        return
    end

    local team = PlayerResource:GetTeam(player_id)
    projection.update_altar(
        player_id,
        altar_by_team[team],
        current_summon(player_id) ~= nil
    )

    local data = snapshot(player_id)
    data.reason = reason or "changed"
    event_bus.emit(events.HERO_SUMMON_STATE_CHANGED, data)
    event_bus.emit(events.SHOP_UNLOCK_CHANGED, {
        player_id = player_id,
        unlocked = data.shop_unlocked,
        reason = data.reason,
    })
end

local function summon_position(anchor, definition)
    local offset = tonumber(definition.spawn_offset) or 260
    return anchor:GetAbsOrigin()
        + anchor:GetForwardVector() * offset
end

local function create_hero(player_id, team, altar, definition)
    local position = summon_position(altar, definition)
    local unit = CreateUnitByName(
        definition.unit_name,
        position,
        true,
        nil,
        nil,
        team
    )
    if not valid_entity(unit) then
        return nil
    end

    -- CreateUnitByName gives control but does not reliably assign the player
    -- identity used by GetPlayerOwnerID. Challenge pickup ownership and other
    -- hero systems require the summoned hero to report the real player ID.
    if unit.SetPlayerID then unit:SetPlayerID(player_id) end
    local player = PlayerResource:GetPlayer(player_id)
    if player and unit.SetOwner then unit:SetOwner(player) end
    unit:SetControllableByPlayer(player_id, true)
    FindClearSpaceForUnit(unit, position, true)

    print(string.format(
        "[HERO_SUMMON_OWNER_ASSIGNED] player=%s reported_owner=%s entindex=%s",
        tostring(player_id), tostring(unit:GetPlayerOwnerID()),
        tostring(unit:entindex())))

    ability_utils.remove_all(unit)
    if unit.SetAbilityPoints then
        unit:SetAbilityPoints(0)
    end

    stat_adapter.apply(unit, definition)
    -- Selected-unit UI must use the addon hero identity rather than the
    -- native carrier identity (for example Sven or Undying).
    unit.survival_display_name = definition.display_name
    unit.survival_hero_id = definition.hero_id
    if not unit:HasModifier("modifier_single_health_bar") then
        unit:AddNewModifier(unit, nil, "modifier_single_health_bar", {
            player_id = player_id,
        })
    end
    if not unit:HasModifier("modifier_debug_attack_cap") then
        unit:AddNewModifier(unit, nil, "modifier_debug_attack_cap", {})
    end
    cosmetic_service.apply(unit, definition.hero_id)
    return unit
end

local function validate(player_id, hero_id, debug_bypass)
    if not valid_player_id(player_id) then
        return nil, nil, "player_id_invalid"
    end
    if current_summon(player_id) then
        return nil, nil, "已经召唤过英雄"
    end

    local team = PlayerResource:GetTeam(player_id)
    local altar = altar_by_team[team]
    if debug_bypass and not valid_entity(altar) then
        altar = builder_by_player[player_id]
        if not valid_entity(altar) then
            altar = PlayerResource:GetSelectedHeroEntity(player_id)
        end
    end
    if not valid_entity(altar) then
        return nil, nil, "英雄祭坛尚未建造"
    end
    if not debug_bypass and (city_level_by_team[team] or 0)
        < (tonumber(rule().requires_city_level) or 3) then
        return nil, nil, "主城等级不足"
    end

    local definition = heroes.by_id[hero_id]
    if not definition or definition.enabled == false then
        return nil, nil, "英雄配置不存在"
    end

    local entitlement = projection.entitlements(player_id)
    if definition.vip_required == true
        and not debug_bypass
        and entitlement.vip ~= 1 then
        return nil, nil, "需要VIP权限"
    end
    return altar, definition, nil
end

local function summon(payload)
    local player_id = tonumber(payload.player_id)
    local hero_id = tostring(payload.hero_id or "")
    local altar, definition, error_code =
        validate(player_id, hero_id, payload.debug_bypass == true)
    if error_code then
        return { ok = false, error = error_code }
    end

    local team = PlayerResource:GetTeam(player_id)
    local unit = create_hero(
        player_id,
        team,
        altar,
        definition
    )
    if not unit then
        return { ok = false, error = "英雄创建失败" }
    end

    summoned_by_player[player_id] = {
        unit = unit,
        hero_id = hero_id,
        unit_name = definition.unit_name,
        team = team,
    }

    event_bus.emit(events.HERO_SUMMONED, {
        player_id = player_id,
        team = team,
        unit = unit,
        entindex = unit:entindex(),
        hero_id = hero_id,
        unit_name = definition.unit_name,
        display_name = definition.display_name,
    })
    publish(player_id, payload.debug_bypass == true
        and "cheat_hero_summoned" or "hero_summoned")

    return {
        ok = true,
        hero_id = hero_id,
        entindex = unit:entindex(),
        snapshot = snapshot(player_id),
    }
end

local function snapshot_request(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

local function get_summoned(payload)
    local state = current_summon(tonumber(payload.player_id))
    if not state then
        return { ok = false, error = "hero_not_summoned" }
    end
    return {
        ok = true,
        unit = state.unit,
        hero_id = state.hero_id,
        unit_name = state.unit_name,
    }
end

local function on_hero_ready(payload)
    builder_by_player[payload.player_id] = payload.hero
    city_level_by_team[payload.team] =
        city_level_by_team[payload.team] or 0
    publish(payload.player_id, "builder_ready")
end

local function on_building_created(payload)
    if payload.building_id == "hero_altar" then
        altar_by_team[payload.team] = payload.unit
        publish(payload.player_id, "altar_built")
    elseif payload.building_id == "main_city" then
        city_level_by_team[payload.team] = payload.level or 1
    end
end

local function on_building_changed(payload)
    if payload.building_id == "main_city" then
        city_level_by_team[payload.team] = payload.level or 0
        if payload.player_id ~= nil then
            publish(payload.player_id, "city_level_changed")
        end
    end
end

local function on_building_destroyed(payload)
    if payload.building_id == "hero_altar" then
        altar_by_team[payload.team] = nil
        if payload.player_id ~= nil then
            publish(payload.player_id, "altar_destroyed")
        end
    elseif payload.building_id == "main_city" then
        city_level_by_team[payload.team] = 0
    end
end

local function on_entitlement_changed(payload)
    publish(payload.player_id, "entitlement_changed")
end

local function on_hero_progression_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if not valid_player_id(player_id) then
        return
    end
    local team = PlayerResource:GetTeam(player_id)
    projection.update_altar(
        player_id,
        altar_by_team[team],
        current_summon(player_id) ~= nil
    )
end

function M.init()
    altar_by_team = {}
    builder_by_player = {}
    city_level_by_team = {}
    summoned_by_player = {}

    event_bus.handle_request(
        events.HERO_SUMMON_SNAPSHOT_REQUEST,
        snapshot_request
    )
    event_bus.handle_request(events.HERO_SUMMON_REQUEST, summon)
    event_bus.handle_request(
        events.HERO_SUMMON_GET_REQUEST,
        get_summoned
    )

    event_bus.subscribe(events.HERO_READY, on_hero_ready)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(
        events.BUILDING_DESTROYED,
        on_building_destroyed
    )
    event_bus.subscribe(
        events.PLAYER_ENTITLEMENT_CHANGED,
        on_entitlement_changed
    )
    event_bus.subscribe(
        events.HERO_PROGRESSION_CHANGED,
        on_hero_progression_changed
    )
end

return M
