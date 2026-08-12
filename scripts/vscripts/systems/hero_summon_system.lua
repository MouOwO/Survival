local event_bus = require("core/event_bus")
local events = require("core/events")
local heroes = require("config/generated/hero_definitions")
local summon_rules = require("config/generated/hero_summon_rules")
local stat_adapter = require("systems/hero_stat_adapter")
local cosmetic_service = require("systems/hero_cosmetic_service")
local projection = require("systems/hero_summon_projection")
local hero_anchor_service = require("systems/hero_anchor_service")
local destination_validation = require("systems/destination_validation_service")
local modifier_registry = require("core/modifier_registry")

local M = {}

local altar_by_team = {}
local builder_by_player = {}
local city_level_by_team = {}
local summoned_by_player = {}
local replacing_by_player = {}

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

local function preserve_and_hide_native_abilities(unit)
    local count = math.max(0, tonumber(unit:GetAbilityCount()) or 0)
    for index = 0, count - 1 do
        local ability = unit:GetAbilityByIndex(index)
        if ability and not ability:IsNull() then
            ability:SetHidden(true)
            ability:SetActivated(false)
        end
    end
    print(string.format(
        "[HERO_SUMMON_ABILITIES] policy=preserve_engine_abilities hidden=%s ability_count=%s",
        tostring(count > 0), tostring(count)))
    return count > 0
end

local function diagnose_drow_visible_modifiers(unit)
    if unit:GetUnitName() ~= "npc_dota_hero_drow_ranger"
        or type(unit.FindAllModifiers) ~= "function" then return end
    for _, modifier in ipairs(unit:FindAllModifiers() or {}) do
        local hidden = modifier.IsHidden and modifier:IsHidden() or false
        if not hidden then
            local ability = modifier.GetAbility and modifier:GetAbility() or nil
            print(string.format(
                "[DROW_VISIBLE_MODIFIER] modifier=%s ability=%s",
                tostring(modifier:GetName()),
                tostring(ability and not ability:IsNull()
                    and ability:GetAbilityName() or "none")
            ))
        end
    end
end

local function configured_number(definition, key)
    local value = definition and definition[key]
    if value == nil or value == "" then return nil end
    return tonumber(value)
end

local function validate_replacement_modifiers(unit, definition)
    local required = {}
    if (configured_number(definition, "attack_speed") or 0) > 0 then
        required[#required + 1] = "modifier_debug_attack_cap"
    end
    if (configured_number(definition, "attack_range") or 0) > 0 then
        required[#required + 1] = "modifier_survival_hero_attack_range"
    end
    if (configured_number(definition, "base_health") or 0) > 0 then
        required[#required + 1] = "modifier_survival_hero_base_health"
    end
    if configured_number(definition, "base_mana") ~= nil then
        required[#required + 1] = "modifier_survival_hero_mana_standard"
    end

    local missing = {}
    for _, modifier_name in ipairs(required) do
        if not unit:HasModifier(modifier_name) then
            missing[#missing + 1] = modifier_name
        end
    end
    if #missing > 0 then
        return false, table.concat(missing, ",")
    end
    return true, #required
end

local function initialize_replacement(player_id, team, altar, definition)
    local registry_call_ok, modifiers_valid, modifier_detail = pcall(
        modifier_registry.ensure_available
    )
    if not registry_call_ok or modifiers_valid ~= true then
        local error_detail = registry_call_ok and modifier_detail or modifiers_valid
        print(string.format(
            "[HERO_REPLACEMENT_FAILED] player=%s hero=%s modifier_registry=%s",
            tostring(player_id), tostring(definition.unit_name),
            tostring(error_detail)
        ))
        return nil, "modifier_registry_unavailable"
    end
    print(string.format(
        "[HERO_REPLACEMENT_MODIFIER_PREFLIGHT] player=%s hero=%s checked=%s recovered=%s",
        tostring(player_id), tostring(definition.unit_name),
        tostring(modifier_detail and modifier_detail.checked or "unknown"),
        tostring(modifier_detail and modifier_detail.recovered or 0)
    ))

    local position = summon_position(altar, definition)
    local placeholder, begin_error = hero_anchor_service.begin_replacement(player_id)
    if not placeholder then
        return nil, begin_error
    end

    local call_ok, unit = pcall(
        PlayerResource.ReplaceHeroWithNoTransfer,
        PlayerResource,
        player_id,
        definition.unit_name,
        0,
        0
    )
    if not call_ok or not valid_entity(unit) then
        hero_anchor_service.abort_replacement(player_id)
        print(string.format(
            "[HERO_REPLACEMENT_FAILED] player=%s hero=%s error=%s",
            tostring(player_id), tostring(definition.unit_name), tostring(unit)))
        return nil, "hero_replacement_failed"
    end

    unit:RemoveNoDraw()

    print(string.format(
        "[HERO_REPLACEMENT_OWNER] player=%s reported_owner=%s entindex=%s",
        tostring(player_id), tostring(unit:GetPlayerOwnerID()),
        tostring(unit:entindex())))

    preserve_and_hide_native_abilities(unit)
    if unit.SetAbilityPoints then
        unit:SetAbilityPoints(0)
    end

    local stat_ok, stat_error = pcall(stat_adapter.apply, unit, definition)
    if not stat_ok then
        hero_anchor_service.abort_replacement(player_id)
        print(string.format(
            "[HERO_REPLACEMENT_FAILED] player=%s hero=%s stat_apply=%s",
            tostring(player_id), tostring(definition.unit_name),
            tostring(stat_error)
        ))
        return nil, "hero_modifier_apply_failed"
    end
    -- Selected-unit UI must use the addon hero identity rather than the
    -- native carrier identity (for example Sven or Undying).
    unit.survival_display_name = definition.display_name
    unit.survival_hero_id = definition.hero_id
    local moved, move_error = destination_validation.teleport(unit, position, false)
    if not moved then
        hero_anchor_service.abort_replacement(player_id)
        return nil, move_error
    end
    -- The retired custom world-health-bar overlay no longer consumes a marker
    -- modifier. Native overhead health bars remain enabled for this hero.
    local unit_modifiers_valid, missing_modifiers =
        validate_replacement_modifiers(unit, definition)
    if not unit_modifiers_valid then
        hero_anchor_service.abort_replacement(player_id)
        print(string.format(
            "[HERO_REPLACEMENT_FAILED] player=%s hero=%s missing_unit_modifiers=%s",
            tostring(player_id), tostring(definition.unit_name),
            tostring(missing_modifiers)
        ))
        return nil, "hero_modifier_apply_failed"
    end
    cosmetic_service.apply(unit, definition.hero_id)
    diagnose_drow_visible_modifiers(unit)
    local committed, commit_error = hero_anchor_service.commit_replacement(
        player_id,
        unit
    )
    if not committed then
        hero_anchor_service.abort_replacement(player_id)
        return nil, commit_error
    end
    return unit, nil
end

local function validate(player_id, hero_id, debug_bypass)
    if not valid_player_id(player_id) then
        return nil, nil, "player_id_invalid"
    end
    if current_summon(player_id) then
        return nil, nil, "已经召唤过英雄"
    end
    if replacing_by_player[player_id] then
        return nil, nil, "hero_replacement_in_progress"
    end

    local team = PlayerResource:GetTeam(player_id)
    local altar = altar_by_team[team]
    if debug_bypass and not valid_entity(altar) then
        altar = builder_by_player[player_id]
        if not valid_entity(altar) then
            local result = event_bus.request(events.BUILDER_GET_REQUEST, {
                player_id = player_id,
            })
            altar = result and result.ok and result.builder or nil
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
    local spawn = summon_position(altar, definition)
    spawn.z = GetGroundHeight(spawn, altar)
    local destination_ok, destination_error =
        destination_validation.validate_hero_position(spawn)
    if not destination_ok then
        return nil, nil, destination_error
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
    replacing_by_player[player_id] = true
    local unit, replacement_error = initialize_replacement(
        player_id,
        team,
        altar,
        definition
    )
    if not unit then
        replacing_by_player[player_id] = nil
        return { ok = false, error = replacement_error or "hero_replacement_failed" }
    end

    summoned_by_player[player_id] = {
        unit = unit,
        hero_id = hero_id,
        unit_name = definition.unit_name,
        team = team,
    }
    replacing_by_player[player_id] = nil

    event_bus.emit(events.HERO_SUMMONED, {
        player_id = player_id,
        team = team,
        unit = unit,
        entindex = unit:entindex(),
        hero_id = hero_id,
        unit_name = definition.unit_name,
        display_name = definition.display_name,
    })
    local player = PlayerResource:GetPlayer(player_id)
    if player and CustomGameEventManager then
        CustomGameEventManager:Send_ServerToPlayer(player, "survival_select_unit", {
            entindex = unit:entindex(),
            reason = "combat_hero_ready",
        })
    end
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

local function on_builder_ready(payload)
    builder_by_player[payload.player_id] = payload.builder
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
    replacing_by_player = {}

    event_bus.handle_request(
        events.HERO_SUMMON_SNAPSHOT_REQUEST,
        snapshot_request
    )
    event_bus.handle_request(events.HERO_SUMMON_REQUEST, summon)
    event_bus.handle_request(
        events.HERO_SUMMON_GET_REQUEST,
        get_summoned
    )

    event_bus.subscribe(events.BUILDER_READY, on_builder_ready)
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

M._test = {
    validate_replacement_modifiers = validate_replacement_modifiers,
}

return M
