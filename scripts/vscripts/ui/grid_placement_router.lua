local event_bus = require("core/event_bus")
local events = require("core/events")
local buildings = require("config/buildings_config")
local building_definitions = require("config/generated/building_definitions")
local arrow_tower_base = require("config/generated/arrow_tower_base")
local grid_config = require("config/grid_placement_config")

local M = {}
local profiles_by_ability = {}
local preview_units = {}
local preview_sessions = {}
local closed_preview_sessions = {}
local preview_request_ids = {}
local PREVIEW_UNIT_NAME = "npc_survival_grid_preview_proxy"

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function prepare_preview_unit(unit, profile)
    unit.survival_is_grid_preview = true
    if unit.SetHullRadius then unit:SetHullRadius(0) end
    if unit.SetModelScale and profile and profile.preview_model_scale then
        unit:SetModelScale(profile.preview_model_scale)
    end
end

local function destroy_preview(player_id)
    local unit = preview_units[player_id]
    preview_units[player_id] = nil
    if valid_entity(unit) then UTIL_Remove(unit) end
end

local function request_number(payload, key)
    local value = tonumber(payload and payload[key])
    if value == nil then return nil end
    return math.floor(value)
end

local function accept_preview_request(player_id, payload, request_ids)
    local session_id = request_number(payload, "session_id")
    local request_id = request_number(payload, "request_id")
    if not session_id or session_id <= 0 or not request_id or request_id <= 0 then
        return false, session_id
    end
    local current_session = preview_sessions[player_id] or 0
    local closed_session = closed_preview_sessions[player_id] or 0
    if session_id <= closed_session or session_id < current_session then
        return false, session_id
    end
    if session_id > current_session then
        destroy_preview(player_id)
        preview_sessions[player_id] = session_id
        preview_request_ids[player_id] = 0
    end
    if request_id <= (request_ids[player_id] or 0) then
        return false, session_id
    end
    request_ids[player_id] = request_id
    return true, session_id
end

local function close_preview_session(player_id, session_id)
    session_id = math.floor(tonumber(session_id) or 0)
    if session_id <= 0 then return false end
    closed_preview_sessions[player_id] = math.max(
        closed_preview_sessions[player_id] or 0,
        session_id
    )
    if session_id == (preview_sessions[player_id] or 0) then
        destroy_preview(player_id)
        return true
    end
    return false
end

local function ensure_preview(player_id, caster, profile, position, valid)
    local unit = preview_units[player_id]
    if valid_entity(unit) and unit:GetUnitName() ~= PREVIEW_UNIT_NAME then
        destroy_preview(player_id)
        unit = nil
    end
    if not valid_entity(unit) then
        unit = CreateUnitByName(
            PREVIEW_UNIT_NAME,
            position,
            false,
            caster,
            caster,
            caster:GetTeamNumber()
        )
        if not valid_entity(unit) then return end
        preview_units[player_id] = unit
        unit:SetOwner(caster)
        if profile.preview_model_name and profile.preview_model_name ~= "" then
            unit:SetModel(profile.preview_model_name)
            unit:SetOriginalModel(profile.preview_model_name)
        end
        prepare_preview_unit(unit, profile)
        unit:AddNewModifier(unit, nil, "modifier_grid_building_preview", {})
        if unit.SetDayTimeVisionRange then unit:SetDayTimeVisionRange(0) end
        if unit.SetNightTimeVisionRange then unit:SetNightTimeVisionRange(0) end
    end
    unit:SetAbsOrigin(position)
    if unit.SetRenderAlpha then
        unit:SetRenderAlpha(tonumber(
            (grid_config.preview_visual or {}).preview_alpha
        ) or 125)
    end
    if unit.SetRenderColor then unit:SetRenderColor(235, 245, 255) end
end

local function valid_player_id(player_id)
    return player_id ~= nil and player_id >= 0
        and PlayerResource:IsValidPlayerID(player_id)
end

local function source_player_id(payload)
    return tonumber(payload and (payload.PlayerID or payload.player_id))
end

local function send(player_id, event_name, payload)
    if not valid_player_id(player_id) then return end
    local player = PlayerResource:GetPlayer(player_id)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, event_name, payload)
    end
end

local function build_profiles()
    profiles_by_ability = {}
    for _, row in ipairs(building_definitions.rows or {}) do
        local ability_name = tostring(row.builder_ability or "")
        local definition = buildings[row.building_id]
        if ability_name ~= "" and definition then
            profiles_by_ability[ability_name] = {
                ability_name = ability_name,
                building_id = definition.id,
                display_name = definition.display_name,
                unit_name = definition.unit_name,
                preview_model_name = definition.id == "arrow_tower"
                    and (((arrow_tower_base.rows or {})[1] or {}).model_name)
                    or (((definition.levels or {})[1] or {}).model_name),
                preview_model_scale = definition.id == "arrow_tower"
                    and tonumber(((arrow_tower_base.rows or {})[1] or {}).model_scale)
                    or tonumber(((definition.levels or {})[1] or {}).model_scale),
                footprint_x = math.max(
                    2,
                    tonumber((definition.footprint or {}).x) or 2
                ),
                footprint_y = math.max(
                    2,
                    tonumber((definition.footprint or {}).y) or 2
                ),
                grid_footprint_x = math.max(
                    2,
                    tonumber((definition.footprint or {}).x) or 2
                ) * math.max(1, tonumber(grid_config.footprint_subdivision) or 1),
                grid_footprint_y = math.max(
                    2,
                    tonumber((definition.footprint or {}).y) or 2
                ) * math.max(1, tonumber(grid_config.footprint_subdivision) or 1),
            }
        end
    end
end

local function profile_list()
    local result = {}
    for _, profile in pairs(profiles_by_ability) do
        table.insert(result, profile)
    end
    table.sort(result, function(left, right)
        return left.ability_name < right.ability_name
    end)
    return result
end

local function force_cells_invalid(cells, reason)
    local result = {}
    for _, cell in ipairs(cells or {}) do
        local copy = {}
        for key, value in pairs(cell) do copy[key] = value end
        copy.ok = false
        copy.reason = reason or copy.reason or "build_validation_failed"
        table.insert(result, copy)
    end
    return result
end

local function request_anchor(position)
    local size = tonumber(grid_config.cell_size) or 64
    return math.floor(position.x / size + 0.5),
        math.floor(position.y / size + 0.5)
end

local function entity_diagnostic(entity)
    if not valid_entity(entity) then return "invalid" end
    local name = "unknown"
    pcall(function()
        name = entity.GetUnitName and entity:GetUnitName()
            or entity.GetAbilityName and entity:GetAbilityName()
            or name
    end)
    return tostring(entity:entindex()) .. ":" .. tostring(name)
end

local function resolve_profile_caster(player_id, payload, profile, allow_fallback)
    local entindex = tonumber(payload and payload.entindex)
    local ability_entindex = tonumber(payload and payload.ability_entindex)
    local caster = entindex and EntIndexToHScript(entindex) or nil
    local ability = ability_entindex and EntIndexToHScript(ability_entindex) or nil
    local registered = event_bus.request(events.BUILDER_GET_REQUEST, {
        player_id = player_id,
        caster = valid_entity(caster) and caster or nil,
    })
    if (not caster or caster:IsNull()) and allow_fallback then
        caster = registered and registered.ok and registered.builder or nil
    end
    if caster and not caster:IsNull() and (not ability or ability:IsNull()) then
        ability = caster:FindAbilityByName(profile.ability_name)
    end
    if not registered or not registered.ok then
        return nil, nil, (registered and registered.error) or "builder_unavailable"
    end
    if not caster or caster:IsNull() or not ability or ability:IsNull() then
        return nil, nil, "invalid_builder_or_ability"
    end
    if registered.builder ~= caster or ability:GetCaster() ~= caster then
        return nil, nil, "builder_not_owned"
    end
    if ability:GetAbilityName() ~= profile.ability_name then
        return nil, nil, "ability_profile_mismatch"
    end
    if ability:GetLevel() <= 0 or not ability:IsActivated() then
        return nil, nil, "ability_unavailable"
    end
    return caster, ability, nil
end

local function validate_preview(player_id, payload, profile, position)
    local caster, _, caster_error = resolve_profile_caster(
        player_id,
        payload,
        profile,
        true
    )
    if not caster then
        return nil, nil, { ok = false, error = caster_error, cells = {} }
    end
    local geometry = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = position,
        footprint = {
            x = profile.footprint_x,
            y = profile.footprint_y,
        },
        team = caster:GetTeamNumber(),
    }) or { ok = false, error = "grid_validation_failed", cells = {} }
    local business = event_bus.request(events.BUILD_CAN_PLACE_REQUEST, {
        caster = caster,
        player_id = player_id,
        building_id = profile.building_id,
        position = position,
    }) or { ok = false, error = "build_validation_failed" }
    if not business.ok then
        geometry.cells = force_cells_invalid(geometry.cells, business.error)
    end
    return caster, business, geometry
end

local function register_profile_request()
    CustomGameEventManager:RegisterListener(
        "ui_grid_placement_profiles_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            send(player_id, "ui_grid_placement_profiles", {
                profiles = profile_list(),
                cell_size = tonumber(grid_config.cell_size) or 64,
                preview_visual = grid_config.preview_visual or {},
                version = "GridPlacement_V2.2_PerBuildingFootprint",
            })
        end
    )
end

local function register_validation_request()
    CustomGameEventManager:RegisterListener(
        "ui_grid_placement_validate",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then return end
            local accepted, session_id = accept_preview_request(
                player_id,
                payload,
                preview_request_ids
            )
            if not accepted then return end
            local profile = profiles_by_ability[tostring(payload.ability_name or "")]
            local x = tonumber(payload.x)
            local y = tonumber(payload.y)
            local z = tonumber(payload.z)
            local position = x and y and z and Vector(x, y, z) or nil
            local request_anchor_x, request_anchor_y = 0, 0
            if position then
                request_anchor_x, request_anchor_y = request_anchor(position)
            end
            local requested_caster = tonumber(payload.entindex)
                and EntIndexToHScript(tonumber(payload.entindex)) or nil
            local requested_ability = tonumber(payload.ability_entindex)
                and EntIndexToHScript(tonumber(payload.ability_entindex)) or nil
            print(string.format(
                "[GridPlacement][SERVER] VALIDATE player=%s session=%s request=%s ability_name=%s caster=%s ability=%s world=%.1f,%.1f,%.1f anchor=%s:%s",
                tostring(player_id), tostring(session_id), tostring(payload.request_id),
                tostring(payload.ability_name), entity_diagnostic(requested_caster),
                entity_diagnostic(requested_ability), x or 0, y or 0, z or 0,
                tostring(request_anchor_x), tostring(request_anchor_y)))
            if not profile or not x or not y or not z then
                send(player_id, "ui_grid_placement_validation", {
                    session_id = session_id,
                    request_id = payload.request_id or "",
                    success = 0,
                    error = "invalid_preview_request",
                    ability_name = tostring(payload.ability_name or ""),
                    request_anchor_x = request_anchor_x,
                    request_anchor_y = request_anchor_y,
                    cells = {},
                })
                print(string.format(
                    "[GridPlacement][SERVER] VALIDATE_RESULT player=%s session=%s request=%s success=0 error=invalid_preview_request",
                    tostring(player_id), tostring(session_id), tostring(payload.request_id)))
                return
            end
            local caster, business, geometry = validate_preview(
                player_id,
                payload,
                profile,
                position
            )
            local success = business and business.ok and geometry.ok
            local world = geometry.world_position or position
            if caster then
                ensure_preview(player_id, caster, profile, world, success)
            else
                destroy_preview(player_id)
            end
            send(player_id, "ui_grid_placement_validation", {
                session_id = session_id,
                request_id = payload.request_id or "",
                success = success and 1 or 0,
                error = success and ""
                    or ((business and business.error)
                        or geometry.error
                        or "invalid_position"),
                ability_name = profile.ability_name,
                building_id = profile.building_id,
                request_anchor_x = request_anchor_x,
                request_anchor_y = request_anchor_y,
                anchor_x = geometry.anchor_x or 0,
                anchor_y = geometry.anchor_y or 0,
                world_x = world.x,
                world_y = world.y,
                world_z = world.z,
                cells = geometry.cells or {},
            })
            print(string.format(
                "[GridPlacement][SERVER] VALIDATE_RESULT player=%s session=%s request=%s success=%s error=%s resolved_caster=%s geometry_anchor=%s:%s cells=%s",
                tostring(player_id), tostring(session_id), tostring(payload.request_id),
                tostring(success), tostring(success and "" or ((business and business.error)
                    or geometry.error or "invalid_position")), entity_diagnostic(caster),
                tostring(geometry.anchor_x), tostring(geometry.anchor_y),
                tostring(#(geometry.cells or {}))))
        end
    )
end

local function register_preview_end()
    CustomGameEventManager:RegisterListener(
        "ui_grid_placement_preview_end",
        function(_, payload)
            local player_id = source_player_id(payload)
            if valid_player_id(player_id) then
                close_preview_session(player_id, payload.session_id)
            end
        end
    )
end

local function register_commit_request()
    CustomGameEventManager:RegisterListener(
        "ui_grid_placement_commit",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then return end
            local session_id = request_number(payload, "session_id")
            if not session_id
                or session_id ~= (preview_sessions[player_id] or 0)
                or session_id <= (closed_preview_sessions[player_id] or 0) then
                send(player_id, "ui_grid_placement_commit_result", {
                    success = 0,
                    error = "stale_preview_session",
                })
                return
            end
            local profile = profiles_by_ability[tostring(payload.ability_name or "")]
            local x = tonumber(payload.x)
            local y = tonumber(payload.y)
            local z = tonumber(payload.z)
            if not profile or not x or not y or not z then
                close_preview_session(player_id, session_id)
                send(player_id, "ui_grid_placement_commit_result", {
                    success = 0,
                    error = "invalid_commit_request",
                })
                return
            end
            local caster, ability, ability_error = resolve_profile_caster(
                player_id,
                payload,
                profile,
                false
            )
            if not caster then
                close_preview_session(player_id, session_id)
                send(player_id, "ui_grid_placement_commit_result", {
                    success = 0,
                    error = ability_error,
                })
                return
            end
            local position = Vector(x, y, z)
            local check = event_bus.request(events.BUILD_CAN_PLACE_REQUEST, {
                caster = caster,
                player_id = player_id,
                building_id = profile.building_id,
                position = position,
            }) or { ok = false, error = "build_validation_failed" }
            if not check.ok then
                close_preview_session(player_id, session_id)
                send(player_id, "ui_grid_placement_commit_result", {
                    success = 0,
                    error = check.error or "build_validation_failed",
                })
                return
            end
            local result = event_bus.request(events.BUILD_REQUEST, {
                caster = caster,
                player_id = player_id,
                building_id = profile.building_id,
                position = check.grid.world_position,
                source_ability = ability,
            })
            if result and result.ok then
                ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))
            end
            close_preview_session(player_id, session_id)
            send(player_id, "ui_grid_placement_commit_result", {
                success = result and result.ok and 1 or 0,
                error = result and result.ok and ""
                    or (result and result.error or "build_request_failed"),
                building_id = profile.building_id,
            })
        end
    )
end

function M.init()
    for player_id, _ in pairs(preview_units) do destroy_preview(player_id) end
    preview_units = {}
    preview_sessions = {}
    closed_preview_sessions = {}
    preview_request_ids = {}
    build_profiles()
    register_profile_request()
    register_validation_request()
    register_preview_end()
    register_commit_request()
    print("[GridPlacement] UI router initialized")
end

M._prepare_preview_unit_for_test = prepare_preview_unit
M._preview_unit_name_for_test = PREVIEW_UNIT_NAME
M._build_profiles_for_test = build_profiles
M._profiles_for_test = function() return profiles_by_ability end

return M
