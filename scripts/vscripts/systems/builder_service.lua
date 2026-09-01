local event_bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/builder_definitions")
local player_context = require("systems/player_context_service")

local M = {}

local builder_by_player = {}
local initialized_player = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function definition()
    return (definitions.by_id or {}).default_builder
end

local function publish_selection(player_id, unit)
    local player = PlayerResource:GetPlayer(player_id)
    if player and CustomGameEventManager then
        CustomGameEventManager:Send_ServerToPlayer(player, "survival_select_unit", {
            entindex = unit:entindex(),
            reason = "builder_ready",
        })
    end
end

local function publish_identity(player_id, unit)
    if not CustomNetTables then
        return
    end
    CustomNetTables:SetTableValue("survival_builder_identity", "player_" .. tostring(player_id), {
        entindex = valid_entity(unit) and unit:entindex() or -1,
        unit_name = valid_entity(unit) and unit:GetUnitName() or "",
    })
end

local function create_builder(payload)
    local player_id = tonumber(payload.player_id)
    local hero = payload.hero
    if player_id == nil or player_id < 0 or not valid_entity(hero)
        or initialized_player[player_id] then
        return
    end

    local config = definition()
    if not config or config.enabled == false then
        error("default builder definition missing or disabled")
    end
    initialized_player[player_id] = true

    local spawn, spawn_error = player_context.resolve_builder_spawn(player_id)
    if not spawn then
        initialized_player[player_id] = nil
        print(string.format(
            "[BUILDER_READY] rejected player=%s error=%s",
            tostring(player_id), tostring(spawn_error)))
        return
    end
    local position = spawn.position
    local builder = CreateUnitByName(
        config.unit_name,
        position,
        true,
        nil,
        nil,
        payload.team
    )
    if not valid_entity(builder) then
        initialized_player[player_id] = nil
        error("failed to create independent builder")
    end

    local player = PlayerResource:GetPlayer(player_id)
    if builder.SetPlayerID then builder:SetPlayerID(player_id) end
    if player and builder.SetOwner then builder:SetOwner(player) end
    builder:SetControllableByPlayer(player_id, true)
    builder:SetBaseMoveSpeed(tonumber(config.move_speed) or 300)
    builder:SetModel(config.model_name)
    builder:SetOriginalModel(config.model_name)
    builder:SetModelScale(tonumber(config.model_scale) or 1)
    builder.survival_display_name = config.display_name
    builder.survival_builder_id = config.builder_id
    builder.survival_player_id = player_id
    local registered, register_error = player_context.register_unit(
        player_id,
        builder,
        "builder"
    )
    if not registered then
        initialized_player[player_id] = nil
        if UTIL_Remove then UTIL_Remove(builder) end
        error("failed to register builder owner: " .. tostring(register_error))
    end
    FindClearSpaceForUnit(builder, position, true)

    builder_by_player[player_id] = builder
    publish_identity(player_id, builder)

    local ready = {
        builder = builder,
        unit = builder,
        entindex = builder:entindex(),
        player_id = player_id,
        team = payload.team,
        slot_id = spawn.slot_id,
        spawn_marker = spawn.marker,
        spawn_source = spawn.source,
    }
    event_bus.emit(events.BUILDER_READY, ready)
    publish_selection(player_id, builder)
    print(string.format(
        "[BUILDER_READY] player=%s slot=%s spawn=%s source=%s entindex=%s unit=%s proxy=true courier=false",
        tostring(player_id), tostring(spawn.slot_id), tostring(spawn.marker),
        tostring(spawn.source), tostring(builder:entindex()),
        tostring(config.unit_name)))
end

local function get_builder(payload)
    payload = payload or {}
    local player_id = tonumber(payload.player_id)
    local candidate = payload.builder or payload.caster or payload.unit
    local candidate_entindex = tonumber(payload.entindex)
    if not valid_entity(candidate) and candidate_entindex
        and type(EntIndexToHScript) == "function" then
        local ok, entity = pcall(EntIndexToHScript, candidate_entindex)
        if ok and valid_entity(entity) then candidate = entity end
    end
    if valid_entity(candidate) then
        local matched_player_id = nil
        for registered_player_id, registered_builder in pairs(builder_by_player) do
            if valid_entity(registered_builder) and registered_builder == candidate then
                matched_player_id = registered_player_id
                break
            end
        end
        if matched_player_id == nil then
            return { ok = false, error = "builder_not_registered" }
        end
        if player_id ~= nil and player_id ~= matched_player_id then
            return { ok = false, error = "builder_not_owned" }
        end
        player_id = matched_player_id
    end
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "invalid_player_id" }
    end
    local builder = player_id and builder_by_player[player_id] or nil
    if not valid_entity(builder) then
        builder_by_player[player_id] = nil
        publish_identity(player_id, nil)
        return { ok = false, error = "builder_unavailable" }
    end
    if valid_entity(candidate) and candidate ~= builder then
        return { ok = false, error = "builder_not_owned" }
    end
    return {
        ok = true,
        builder = builder,
        unit = builder,
        entindex = builder:entindex(),
        player_id = player_id,
        team = builder:GetTeamNumber(),
    }
end

local function on_player_disconnected(payload)
    local player_id = tonumber(payload and payload.player_id)
    local builder = player_id and builder_by_player[player_id] or nil
    if player_id == nil then return end
    builder_by_player[player_id] = nil
    initialized_player[player_id] = nil
    if valid_entity(builder) then
        player_context.unregister_unit(builder)
        if UTIL_Remove then UTIL_Remove(builder) end
    end
    publish_identity(player_id, nil)
    print(string.format(
        "[PLAYER_ASSET_CLEANUP] player=%s asset=builder removed=%s",
        tostring(player_id), tostring(valid_entity(builder))))
end

function M.init()
    builder_by_player = {}
    initialized_player = {}
    event_bus.handle_request(events.BUILDER_GET_REQUEST, get_builder)
    event_bus.subscribe(events.HERO_READY, create_builder)
    event_bus.subscribe(events.PLAYER_DISCONNECTED, on_player_disconnected)
end

return M