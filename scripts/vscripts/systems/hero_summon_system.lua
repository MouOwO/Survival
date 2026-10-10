local event_bus = require("core/event_bus")
local events = require("core/events")
local heroes = require("config/generated/hero_definitions")
local stat_adapter = require("systems/hero_stat_adapter")
local cosmetic_service = require("systems/hero_cosmetic_service")
local projection = require("systems/hero_summon_projection")
local summon_access = require("systems/hero_summon_access")
local summon_eligibility = require("systems/hero_summon_eligibility")
local hero_anchor_service = require("systems/hero_anchor_service")
local destination_validation = require("systems/destination_validation_service")
local summon_destination = require("systems/hero_summon_destination")
local hero_asset_preload = require("systems/hero_asset_preload_service")
local player_context = require("systems/player_context_service")
local scheduler = require("core/scheduler")
local return_home = require("systems/hero_return_home_service")

local M = {}

local altar_by_player = {}
local builder_by_player = {}
local city_level_by_player = {}
local city_unit_by_player = {}
local summoned_by_player = {}
local replacing_by_player = {}
local pending_by_player = {}
local unavailable_by_player = {}
local pending_generation = 0
local summon

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function unavailable_reason(player_id)
    if player_context.is_defeated(player_id) then return "player_defeated" end
    return unavailable_by_player[player_id]
end

local function event_player_id(payload)
    local player_id = tonumber(payload and payload.player_id)
    return valid_player_id(player_id) and player_id or nil
end

local function current_summon(player_id)
    if unavailable_reason(player_id) then return nil end
    local state = summoned_by_player[player_id]
    return state and valid_entity(state.unit) and state or nil
end

local function snapshot(player_id)
    local data = projection.build(
        player_id,
        altar_by_player[player_id],
        city_level_by_player[player_id] or 0,
        current_summon(player_id)
    )
    local blocked = unavailable_reason(player_id)
    if blocked then
        data.summon_unlocked = 0
        data.summon_disabled_reason = blocked
    end
    return data
end

local function publish(player_id, reason)
    if not valid_player_id(player_id) then
        return
    end

    projection.update_altar(
        player_id,
        altar_by_player[player_id],
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

local function abort_unavailable_replacement(player_id, unit)
    local reason = unavailable_reason(player_id)
    if not reason then return nil end
    hero_anchor_service.abort_replacement(player_id, unit)
    local multiplayer = package.loaded["systems/multiplayer_player_service"]
    if valid_entity(unit) and multiplayer and multiplayer.reject_defeated_unit then
        multiplayer.reject_defeated_unit(unit)
    end
    return reason
end

local function initialize_replacement(player_id, team, altar, definition, position)
    local blocked = unavailable_reason(player_id)
    if blocked then return nil, blocked end
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

    -- Native hero replacement may synchronously emit engine callbacks. A defeat
    -- during that call must not unhide or commit its newly created hero.
    blocked = abort_unavailable_replacement(player_id, unit)
    if blocked then return nil, blocked end
    unit:RemoveNoDraw()
    if unit.SetPlayerID then unit:SetPlayerID(player_id) end
    local player = PlayerResource:GetPlayer(player_id)
    if player and unit.SetOwner then unit:SetOwner(player) end
    if unit.SetControllableByPlayer then
        unit:SetControllableByPlayer(player_id, true)
    end

    print(string.format(
        "[HERO_REPLACEMENT_OWNER] player=%s reported_owner=%s entindex=%s",
        tostring(player_id), tostring(unit:GetPlayerOwnerID()),
        tostring(unit:entindex())))

    preserve_and_hide_native_abilities(unit)
    if unit.SetAbilityPoints then
        unit:SetAbilityPoints(0)
    end

    stat_adapter.apply(unit, definition)
    -- Selected-unit UI must use the addon hero identity rather than the
    -- native carrier identity (for example Sven or Undying).
    unit.survival_display_name = definition.display_name
    unit.survival_hero_id = definition.hero_id
    local moved, move_error = destination_validation.teleport(unit, position, false)
    if not moved then
        hero_anchor_service.abort_replacement(player_id, unit)
        return nil, move_error
    end
    -- Seed native resurrection before the first death, instead of the map fountain.
    if unit.SetRespawnPosition then pcall(unit.SetRespawnPosition, unit, position) end
    if not unit:HasModifier("modifier_single_health_bar") then
        require("core/modifier_registry").ensure(unit, "modifier_single_health_bar", {
            player_id = player_id,
        })
    end
    if not unit:HasModifier("modifier_debug_attack_cap") then
        unit:AddNewModifier(unit, nil, "modifier_debug_attack_cap", {})
    end
    cosmetic_service.apply(unit, definition.hero_id)
    diagnose_drow_visible_modifiers(unit)
    blocked = abort_unavailable_replacement(player_id, unit)
    if blocked then return nil, blocked end
    local committed, commit_error = hero_anchor_service.commit_replacement(
        player_id,
        unit
    )
    if not committed then
        hero_anchor_service.abort_replacement(player_id, unit)
        return nil, commit_error
    end
    return unit, nil
end

local function validate(player_id, hero_id, debug_bypass)
    if not valid_player_id(player_id) then
        return nil, nil, "player_id_invalid"
    end
    local blocked = unavailable_reason(player_id)
    if blocked then return nil, nil, blocked end
    if current_summon(player_id) then
        return nil, nil, "已经召唤过英雄"
    end
    if replacing_by_player[player_id] then
        return nil, nil, "hero_replacement_in_progress"
    end

    local altar = altar_by_player[player_id]
    local unlocked, unlock_error = summon_eligibility.check(
        player_id, city_level_by_player[player_id], altar
    )
    if not debug_bypass and not unlocked then
        return nil, nil, unlock_error
    end
    local anchor_source = "hero_altar"
    if not summon_eligibility.altar_built(altar) then
        anchor_source = "builder"
        altar = builder_by_player[player_id]
        if not valid_entity(altar) then
            local result = event_bus.request(events.BUILDER_GET_REQUEST, {
                player_id = player_id,
            })
            altar = result and result.ok and result.builder or nil
        end
    end
    if not valid_entity(altar) or (altar.IsAlive and not altar:IsAlive())
        or not player_context.is_owned_by(player_id, altar) then
        return nil, nil, "自己的英雄祭坛或建筑师暂不可用"
    end

    local definition = heroes.by_id[hero_id]
    if not definition or definition.enabled == false then
        return nil, nil, "英雄配置不存在"
    end
    local entitlement = projection.entitlements(player_id)
    local hero_unlocked, hero_unlock_error = summon_access.check(
        definition, summon_access.context(player_id, entitlement)
    )
    if not debug_bypass and not hero_unlocked then
        return nil, nil, hero_unlock_error
    end
    -- Resolve before replacing the hidden carrier. The exact grounded result
    -- is also used for placement; do not recompute the old, possibly blocked
    -- marker after validation. Pending asset loads call validate again.
    local position, destination_error, destination_info =
        summon_destination.resolve(altar, definition, player_id, nil, {
            allow_without_city = true,
            anchor_source = anchor_source,
        })
    if destination_info and (not position or destination_info.attempts > 1) then
        print(string.format(
            "[HeroSummonDestination] player=%s source=%s attempts=%s last_rejection=%s position=%s",
            tostring(player_id), tostring(destination_info.source or "none"),
            tostring(destination_info.attempts), tostring(destination_info.last_reason or "none"),
            position and string.format("%.2f,%.2f,%.2f", position.x, position.y, position.z) or "none"))
    end
    if not position then
        return nil, nil, destination_error
    end
    return altar, definition, nil, position
end

local function complete_pending(player_id, generation, result)
    local pending = pending_by_player[player_id]
    if not pending or pending.generation ~= generation then return end
    pending_by_player[player_id] = nil
    for _, callback in ipairs(pending.completion_callbacks or {}) do
        pcall(callback, result)
    end
end

local function notify_preload(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function queue_pending_summon(payload, definition)
    local player_id = tonumber(payload.player_id)
    local existing = pending_by_player[player_id]
    if existing and existing.hero_id == definition.hero_id then
        if type(payload.on_completed) == "function" then
            existing.completion_callbacks[#existing.completion_callbacks + 1] =
                payload.on_completed
        end
        return {
            ok = true,
            pending = true,
            hero_id = definition.hero_id,
            status = "hero_resource_loading",
        }
    end

    pending_generation = pending_generation + 1
    local generation = pending_generation
    pending_by_player[player_id] = {
        generation = generation,
        hero_id = definition.hero_id,
        payload = payload,
        completion_callbacks = type(payload.on_completed) == "function"
            and { payload.on_completed } or {},
    }
    notify_preload(player_id, "英雄资源准备中，完成后将自动召唤")

    local queued, status = hero_asset_preload.request(definition.hero_id, {
        player_id = player_id,
        on_ready = function()
            local pending = pending_by_player[player_id]
            if not pending or pending.generation ~= generation then return end
            local retry_payload = {}
            for key, value in pairs(pending.payload) do
                retry_payload[key] = value
            end
            retry_payload.on_completed = nil
            local result = summon(retry_payload)
            complete_pending(player_id, generation, result)
        end,
        on_failed = function(reason)
            local pending = pending_by_player[player_id]
            if not pending or pending.generation ~= generation then return end
            local result = {
                ok = false,
                error = "hero_resource_load_failed:" .. tostring(reason),
            }
            notify_preload(player_id, "英雄资源加载失败，请稍后重试", "error")
            complete_pending(player_id, generation, result)
        end,
    })
    if not queued then
        pending_by_player[player_id] = nil
        return { ok = false, error = status or "hero_resource_queue_failed" }
    end
    return {
        ok = true,
        pending = true,
        hero_id = definition.hero_id,
        status = status,
    }
end

summon = function(payload)
    local player_id = tonumber(payload.player_id)
    local hero_id = tostring(payload.hero_id or "")
    local altar, definition, error_code, position =
        validate(player_id, hero_id, payload.debug_bypass == true)
    if error_code then
        return { ok = false, error = error_code }
    end

    if not hero_asset_preload.is_ready(hero_id, player_id) then
        return queue_pending_summon(payload, definition)
    end

    local team = PlayerResource:GetTeam(player_id)
    replacing_by_player[player_id] = true
    local unit, replacement_error = initialize_replacement(
        player_id,
        team,
        altar,
        definition,
        position
    )
    if not unit then
        replacing_by_player[player_id] = nil
        return { ok = false, error = replacement_error or "hero_replacement_failed" }
    end

    local blocked = abort_unavailable_replacement(player_id, unit)
    if blocked then
        replacing_by_player[player_id] = nil
        return { ok = false, error = blocked }
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
    blocked = abort_unavailable_replacement(player_id, unit)
    if blocked then return { ok = false, error = blocked } end
    local player = PlayerResource:GetPlayer(player_id)
    if player and CustomGameEventManager then
        CustomGameEventManager:Send_ServerToPlayer(player, "survival_select_unit", {
            entindex = unit:entindex(),
            reason = "combat_hero_ready",
        })
    end
    publish(player_id, payload.debug_bypass == true
        and "cheat_hero_summoned" or "hero_summoned")

    local result = {
        ok = true,
        hero_id = hero_id,
        entindex = unit:entindex(),
        snapshot = snapshot(player_id),
    }
    return result
end

local function snapshot_request(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

local function delete_hero(payload)
    local player_id = tonumber(payload and payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local blocked = unavailable_reason(player_id)
    if blocked then return { ok = false, error = blocked } end
    if replacing_by_player[player_id] then
        return { ok = false, error = "hero_replacement_in_progress" }
    end
    local state = current_summon(player_id)
    local pending = pending_by_player[player_id]
    if not state then
        -- Invalidate the queued generation before callbacks run. Its preload
        -- may finish later, but must not summon a hero after deletehero.
        if pending then
            complete_pending(player_id, pending.generation, {
                ok = false, error = "hero_summon_cancelled", cancelled = true,
            })
        end
        publish(player_id, "cheat_hero_deleted")
        return { ok = true, removed = false, cancelled = pending ~= nil,
            snapshot = snapshot(player_id) }
    end
    if hero_anchor_service.phase(player_id) ~= "combat_ready" then
        return { ok = false, error = "hero_anchor_not_ready" }
    end

    local old_unit, old_index = state.unit, state.unit:entindex()
    replacing_by_player[player_id] = true
    -- Keep the player bound to a native hero; deleting it with UTIL_Remove
    -- alone leaves the engine/anchor unable to perform the next summon.
    local ok, placeholder = pcall(PlayerResource.ReplaceHeroWithNoTransfer,
        PlayerResource, player_id, "npc_dota_hero_wisp", 0, 0)
    if not ok or not valid_entity(placeholder) then
        replacing_by_player[player_id] = nil
        return { ok = false, error = "hero_delete_failed" }
    end
    local restored, restore_error = hero_anchor_service.restore_placeholder(
        player_id, old_unit, placeholder
    )
    if not restored then
        replacing_by_player[player_id] = nil
        return { ok = false, error = restore_error }
    end
    summoned_by_player[player_id] = nil
    if pending then
        complete_pending(player_id, pending.generation, {
            ok = false, error = "hero_summon_cancelled", cancelled = true,
        })
    end
    -- Do not impersonate defeat/disconnect: those paths disable the player
    -- and destroy their buildings. Removal only retires this combat hero.
    cosmetic_service.clear(old_unit)
    event_bus.emit(events.HERO_REMOVED, {
        player_id = player_id, unit = old_unit, entindex = old_index,
        hero_id = state.hero_id, reason = "cheat_deletehero",
    })
    replacing_by_player[player_id] = nil
    publish(player_id, "cheat_hero_deleted")
    local builder = builder_by_player[player_id]
    local player = PlayerResource:GetPlayer(player_id)
    if player and CustomGameEventManager and valid_entity(builder) then
        CustomGameEventManager:Send_ServerToPlayer(player, "survival_select_unit", {
            entindex = builder:entindex(), reason = "combat_hero_removed",
        })
    end
    return { ok = true, removed = true, snapshot = snapshot(player_id) }
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
    local player_id = event_player_id(payload)
    if player_id == nil or unavailable_reason(player_id) then return end
    builder_by_player[player_id] = payload.builder
    city_level_by_player[player_id] = city_level_by_player[player_id] or 0
    publish(player_id, "builder_ready")
end

local function on_building_created(payload)
    local player_id = event_player_id(payload)
    if player_id == nil or unavailable_reason(player_id) then return end
    if payload.building_id == "hero_altar" then
        altar_by_player[player_id] = payload.unit
        publish(player_id, "altar_built")
    elseif payload.building_id == "main_city" then
        city_unit_by_player[player_id] = payload.unit
        city_level_by_player[player_id] = payload.level or 1
        publish(player_id, "city_built")
    end
end

local function on_building_changed(payload)
    if not payload or payload.building_id ~= "main_city" then return end
    local player_id = event_player_id(payload)
    if player_id == nil or unavailable_reason(player_id) then return end
    local level, unit = payload.level or 0, payload.unit
    -- Research publishes every owned building even when its city level is
    -- unchanged. This branch only projects city-level summon eligibility;
    -- profile, entitlement, rogue and rebirth updates have their own handlers.
    -- Unknown events, missing handles and city replacements remain observable.
    if payload.reason == "technology_stats_changed" and type(payload.level) == "number"
        and city_unit_by_player[player_id] == unit and valid_entity(unit)
        and city_level_by_player[player_id] == level then return end
    city_unit_by_player[player_id] = unit
    city_level_by_player[player_id] = level
    publish(player_id, "city_level_changed")
end

local function on_building_destroyed(payload)
    local player_id = event_player_id(payload)
    if player_id == nil then return end
    if payload.building_id == "hero_altar" then
        local current = altar_by_player[player_id]
        if payload.unit and current ~= payload.unit then return end
        altar_by_player[player_id] = nil
        publish(player_id, "altar_destroyed")
    elseif payload.building_id == "main_city" then
        city_unit_by_player[player_id] = nil
        city_level_by_player[player_id] = 0
        publish(player_id, "city_destroyed")
    end
end

local function on_player_unavailable(payload, defeated)
    local player_id = event_player_id(payload)
    if player_id == nil then return end
    local reason = (defeated or player_context.is_defeated(player_id)) and "player_defeated"
        or payload.defeat_cleanup and "player_defeated" or "player_disconnected"
    unavailable_by_player[player_id] = reason
    local pending = pending_by_player[player_id]
    if pending then
        complete_pending(player_id, pending.generation, { ok = false, error = reason })
    end
    replacing_by_player[player_id], summoned_by_player[player_id] = nil, nil
    builder_by_player[player_id], altar_by_player[player_id] = nil, nil
    city_unit_by_player[player_id] = nil
    city_level_by_player[player_id] = 0
    publish(player_id, reason)
end

local function on_entitlement_changed(payload)
    publish(payload.player_id, "entitlement_changed")
end

local function on_profile_changed(payload)
    local player_id = event_player_id(payload)
    if player_id == nil or unavailable_reason(player_id) then return end
    publish(player_id, "profile_changed")
end

local function on_rogue_reward_changed(payload)
    if payload and payload.effects_changed == false then return end
    local player_id = event_player_id(payload)
    if player_id == nil or unavailable_reason(player_id) then return end
    publish(player_id, "rogue_unlock_changed")
end

local function on_hero_progression_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if not valid_player_id(player_id) or unavailable_reason(player_id) then
        return
    end
    projection.update_altar(
        player_id,
        altar_by_player[player_id],
        current_summon(player_id) ~= nil
    )
end

local function on_hero_killed(payload)
    local unit = payload and payload.victim
    if not valid_entity(unit) or not unit.GetPlayerOwnerID then return end
    local player_id = unit:GetPlayerOwnerID()
    local state = current_summon(player_id)
    if not state or state.unit ~= unit then return end
    state.awaiting_respawn = true
    state.respawn_serial = (state.respawn_serial or 0) + 1
    -- Update native spawn placement too, so the engine never briefly shows the
    -- hero at the obsolete fountain before npc_spawned finishes.
    local position = summon_destination.resolve(nil, nil, player_id, unit)
    if position and unit.SetRespawnPosition then
        pcall(unit.SetRespawnPosition, unit, position)
    end
end

function M.on_npc_spawned(unit)
    if not valid_entity(unit) or not unit.GetPlayerOwnerID then return end
    local player_id = unit:GetPlayerOwnerID()
    local state = current_summon(player_id)
    if not state or state.unit ~= unit or not state.awaiting_respawn then return end
    local serial = state.respawn_serial
    scheduler.after(0, function()
        if current_summon(player_id) ~= state or state.unit ~= unit
            or state.respawn_serial ~= serial or not state.awaiting_respawn
            or not valid_entity(unit) or not unit:IsAlive() then return end
        state.awaiting_respawn = false
        -- Re-resolve after resurrection, since another building may now occupy
        -- the earlier point. Ownership, room exit and camera follow match F2.
        local result = return_home.return_unit(unit, player_id, { silent = true })
        if result.ok and unit.SetRespawnPosition then
            pcall(unit.SetRespawnPosition, unit, result.position)
        end
    end, "hero_respawn_home:" .. tostring(player_id))
end

function M.init()
    altar_by_player = {}
    builder_by_player = {}
    city_level_by_player = {}
    city_unit_by_player = {}
    summoned_by_player = {}
    replacing_by_player = {}
    pending_by_player = {}
    unavailable_by_player = {}
    -- Old resource callbacks may arrive after a new Tools session initializes.
    pending_generation = pending_generation + 1

    event_bus.handle_request(
        events.HERO_SUMMON_SNAPSHOT_REQUEST,
        snapshot_request
    )
    event_bus.handle_request(events.HERO_SUMMON_REQUEST, summon)
    event_bus.handle_request(events.HERO_DELETE_REQUEST, delete_hero)
    event_bus.handle_request(
        events.HERO_SUMMON_GET_REQUEST,
        get_summoned
    )

    event_bus.subscribe(events.PLAYER_DEFEATED, function(payload)
        on_player_unavailable(payload, true)
    end)
    event_bus.subscribe(events.PLAYER_DISCONNECTED, on_player_unavailable)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_hero_killed)
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
    event_bus.subscribe(events.PLAYER_PROFILE_CHANGED, on_profile_changed)
    event_bus.subscribe(events.ROGUE_REWARD_CHANGED, on_rogue_reward_changed)
    event_bus.subscribe(
        events.HERO_PROGRESSION_CHANGED,
        on_hero_progression_changed
    )
end

return M
