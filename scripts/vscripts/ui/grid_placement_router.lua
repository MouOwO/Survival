local event_bus = require("core/event_bus")
local events = require("core/events")
local buildings = require("config/buildings_config")
local building_definitions = require("config/generated/building_definitions")
local grid_config = require("config/grid_placement_config")
local grid_geometry = require("core/building_grid_geometry")
local scheduler = require("core/scheduler")
local send

local M = {}
local profiles_by_ability = {}
local preview_sessions = {}
local closed_preview_sessions = {}
local preview_request_ids = {}
local preview_pose_ids = {}
local preview_areas = {}
local preview_terrain_caches = {}
local last_area_perf_log = -100
local static_area=""
local static_area_players={}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function destroy_preview(player_id)
    scheduler.cancel("grid_preview_area:" .. tostring(player_id))
    preview_areas[player_id] = nil
    require("systems/grid_preview_model_service").clear(player_id)
end

local function preview_area(player_id, caster, position, profile, session_id)
    local now = GameRules and GameRules:GetGameTime() or 0
    local cached = preview_areas[player_id]
    local interval = tonumber((grid_config.preview_visual or {}).area_refresh_interval) or 0.30
    if cached and cached.caster == caster:entindex() and (cached.job or now - cached.time < interval)
        and (position.x - cached.x)^2 + (position.y - cached.y)^2 < 256^2 then
        return cached.complete_area or cached.area, cached.complete_area and 1 or 0
    end
    local state = {time = now, x = position.x, y = position.y,
        caster = caster:entindex(), area = cached and cached.area or "",
        complete_area = cached and cached.complete_area or nil}
    preview_areas[player_id] = state
    local team, caster_index = caster:GetTeamNumber(), caster:entindex()
    preview_terrain_caches[player_id] = preview_terrain_caches[player_id] or {}
    local perf_clock = type(Time) == "function" and Time or os.clock
    local started, batches, max_batch_ms = perf_clock(), 0, 0
    state.job = coroutine.create(function()
        return require("systems/grid_placement_system").preview_area({
            position = position, team = team, ignore_entindex = caster_index, yield_after = 128,
            time_budget = 0.002, terrain_cache = preview_terrain_caches[player_id],
        })
    end)
    local function step()
        if preview_areas[player_id] ~= state or preview_sessions[player_id] ~= session_id then return end
        local batch_start = perf_clock()
        local ok, result = coroutine.resume(state.job)
        batches = batches+1
        max_batch_ms = math.max(max_batch_ms,(perf_clock()-batch_start)*1000)
        if not ok then
            state.job = nil
            print("[GridPlacement] background area failed: " .. tostring(result))
            return
        end
        local complete = coroutine.status(state.job) == "dead"
        if type(result) == "string" and (result ~= state.area or complete) then
            state.area = result
            -- The inline batch travels with the exact validation response.
            if batches > 1 and (complete or not state.complete_area) then send(player_id, "ui_grid_placement_area", {
                session_id = session_id, ability_name = profile.ability_name, area = result,
                complete = complete and 1 or 0,
            }) end
        end
        if not complete then return 0.05 end
        state.job = nil
        state.complete_area = result
        state.time = GameRules:GetGameTime()
        if state.time-last_area_perf_log >= 5 then
            last_area_perf_log = state.time
            print(string.format("[GridPlacement][PERF] area batches=%d elapsed_ms=%.1f max_batch_ms=%.2f bytes=%d",
                batches,(perf_clock()-started)*1000,max_batch_ms,#state.area))
        end
    end
    -- Only one small batch runs inline; the exact footprint reply never waits
    -- for the rest of the circle. Cancel/re-enter cannot resurrect an old scan.
    scheduler.cancel("grid_preview_area:" .. tostring(player_id))
    local delay = step()
    if delay then scheduler.after(delay, step, "grid_preview_area:" .. tostring(player_id)) end
    return state.complete_area or state.area, state.complete_area and 1 or 0
end

local function request_number(payload, key)
    local value = tonumber(payload and payload[key])
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return math.floor(value)
end

local function accept_preview_request(player_id, payload, request_ids)
    if require("systems/player_context_service").is_defeated(player_id) then return false end
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
        preview_pose_ids[player_id] = 0
    end
    if request_id <= (request_ids[player_id] or 0) then
        return false, session_id
    end
    request_ids[player_id] = request_id
    return true, session_id
end

local function close_preview_session(player_id, session_id)
    session_id = request_number({session_id=session_id}, "session_id") or 0
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

local function valid_player_id(player_id)
    return player_id ~= nil and player_id >= 0
        and PlayerResource:IsValidPlayerID(player_id)
end

local function source_player_id(payload)
    return tonumber(payload and payload.PlayerID)
end

send = function(player_id, event_name, payload)
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
                preview_model = 1,
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
    local tower = buildings.arrow_tower
    if tower then
        local footprint = tower.footprint or {x=2,y=2}
        local subdivision = math.max(1, tonumber(grid_config.footprint_subdivision) or 1)
        profiles_by_ability.ability_building_blink = {
            ability_name="ability_building_blink", building_id="arrow_tower",
            display_name="防御塔移动", placement_action="relocate", preview_model=1,
            footprint_x=footprint.x, footprint_y=footprint.y,
            grid_footprint_x=footprint.x*subdivision,
            grid_footprint_y=footprint.y*subdivision,
        }
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

local function request_anchor(position, profile)
    profile = profile or {}
    local x = grid_geometry.snap_axis(position.x, profile.grid_footprint_x or 2)
    local y = grid_geometry.snap_axis(position.y, profile.grid_footprint_y or 2)
    return x, y
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
    if profile.placement_action == "relocate" then
        local resolved, reason = require("systems/tower_relocation_service").resolve(
            player_id, entindex, ability_entindex)
        if not resolved then return nil, nil, reason end
        return resolved.unit, resolved.ability
    end
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

-- Separate, cheap pose channel: fast mouse movement may pause validation,
-- but must never leave the model at an old validation response position.
local function register_preview_pose()
    CustomGameEventManager:RegisterListener("ui_grid_placement_pose", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local profile = profiles_by_ability[tostring(payload.ability_name or "")]
        local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
        local function finite(v) return v and v == v and math.abs(v) <= 32768 end
        if not profile or not finite(x) or not finite(y) or not finite(z) then return end
        local caster = resolve_profile_caster(player_id, payload, profile, false)
        if not caster then return end
        if not accept_preview_request(player_id, payload, preview_pose_ids) then return end
        require("systems/grid_preview_model_service").update(player_id, caster, profile, Vector(x,y,z))
    end)
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
    if profile.placement_action == "relocate" then
        local grid = require("systems/tower_relocation_service").validate(
            player_id, caster:entindex(), position, payload.ability_entindex)
        return caster, grid, grid
    end
    -- The building service already checks the exact grid when business rules
    -- pass. Reuse that result rather than performing the same scan twice.
    local business = event_bus.request(events.BUILD_CAN_PLACE_REQUEST, {
        caster = caster,
        player_id = player_id,
        building_id = profile.building_id,
        position = position,
    }) or { ok = false, error = "build_validation_failed" }
    local geometry = business.grid or (business.world_position and business)
        or event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = position,
        footprint = {
            x = profile.footprint_x,
            y = profile.footprint_y,
        },
        team = caster:GetTeamNumber(),
        -- Only the already authenticated builder may move out of its own
        -- requested footprint. Never trust an ignore list from the client.
        ignore_entindex = caster:entindex(),
    }) or { ok = false, error = "grid_validation_failed", cells = {} }
    -- Keep per-cell results; business errors still reject success/commit.
    return caster, business, geometry
end

local function register_profile_request()
    CustomGameEventManager:RegisterListener(
        "ui_grid_placement_profiles_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if player_id~=nil then static_area_players[player_id]=true end
            send(player_id, "ui_grid_placement_profiles", {
                profiles = profile_list(),
                cell_size = tonumber(grid_config.cell_size) or 64,
                preview_visual = grid_config.preview_visual or {},
                -- Fixed white geometry; independent of cursor scans and
                -- advisory red/green occupancy packets.
                static_grid = {bounds=grid_config.grid_display_bounds or grid_config.build_bounds,
                    build_bounds=grid_config.build_bounds,
                    height=tonumber(grid_config.build_ground_height) or 0},
                version = "GridPlacement_V3_StaticWhiteGrid",
            })
            if static_area~="" then send(player_id,"ui_grid_placement_static_area",{area=static_area}) end
        end
    )
end

local function preview_cells(cells)
    -- The client derives the snapped rectangle from cell centers. Ground
    -- corners, policy reasons and grid indices stay server-side; transmitting
    -- four terrain corners for each of 16 cells duplicated most of the reply.
    local result = {}
    for _, cell in ipairs(cells or {}) do
        result[#result+1] = {x=cell.x,y=cell.y,z=cell.z,ok=cell.ok and 1 or 0}
    end
    return result
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
                request_anchor_x, request_anchor_y = request_anchor(position, profile)
            end
            if (grid_config.preview_visual or {}).debug_requests then
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
            end
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
            -- Validation never repositions the model; the independent pose
            -- channel follows the latest snapped cursor even during fast sweeps.
            if not caster then destroy_preview(player_id) end
            local area,area_complete="",0
            if caster then area,area_complete=preview_area(player_id,caster,position,profile,session_id) end
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
                cells = preview_cells(geometry.cells),
                area = area,
                area_complete = area_complete,
                cursor_x = position.x,
                cursor_y = position.y,
            })
            if (grid_config.preview_visual or {}).debug_requests then print(string.format(
                "[GridPlacement][SERVER] VALIDATE_RESULT player=%s session=%s request=%s success=%s error=%s resolved_caster=%s geometry_anchor=%s:%s cells=%s",
                tostring(player_id), tostring(session_id), tostring(payload.request_id),
                tostring(success), tostring(success and "" or ((business and business.error)
                    or geometry.error or "invalid_position")), entity_diagnostic(caster),
                tostring(geometry.anchor_x), tostring(geometry.anchor_y),
                tostring(#(geometry.cells or {})))) end
        end
    )
end

local function register_preview_end()
    CustomGameEventManager:RegisterListener("ui_grid_placement_pause_area",function(_,payload)
        local player_id=source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local session_id=request_number(payload,"session_id")
        local request_id=request_number(payload,"request_id")
        if not session_id or session_id ~= preview_sessions[player_id] or not request_id
            or request_id < (preview_request_ids[player_id] or 0)
            or session_id <= (closed_preview_sessions[player_id] or 0) then return end
        -- Preserve the terrain cache, discard only the now irrelevant scan.
        -- The next settled validation starts a new scan at the latest cursor.
        scheduler.cancel("grid_preview_area:"..tostring(player_id))
        preview_areas[player_id]=nil
    end)
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
            local profile = profiles_by_ability[tostring(payload.ability_name or "")]
            -- The first relocation click may precede every preview/ghost reply.
            -- Only a tower move can open a session at commit; ownership and
            -- the actual landing cell are still checked below on the server.
            local fresh_relocation = profile and profile.placement_action == "relocate"
                and session_id and session_id > (preview_sessions[player_id] or 0)
            local function reply(result)
                result.session_id = session_id
                send(player_id, "ui_grid_placement_commit_result", result)
            end
            if not session_id or session_id <= 0
                or (session_id ~= (preview_sessions[player_id] or 0) and not fresh_relocation)
                or session_id <= (closed_preview_sessions[player_id] or 0) then
                reply({
                    success = 0,
                    error = "stale_preview_session",
                })
                return
            end
            local x = tonumber(payload.x)
            local y = tonumber(payload.y)
            local z = tonumber(payload.z)
            if not profile or not x or not y or not z then
                close_preview_session(player_id, session_id)
                reply({
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
                reply({
                    success = 0,
                    error = ability_error,
                })
                return
            end
            local position = Vector(x, y, z)
            if profile.placement_action == "relocate" then
                if fresh_relocation then
                    destroy_preview(player_id)
                    preview_sessions[player_id] = session_id
                    preview_request_ids[player_id] = 0
                    preview_pose_ids[player_id] = 0
                end
                local result = require("systems/tower_relocation_service").move(
                    player_id, caster:entindex(), position, ability:entindex())
                close_preview_session(player_id, session_id)
                reply({
                    success=result.ok and 1 or 0, error=result.error or "",
                    building_id=profile.building_id, placement_action="relocate",
                })
                return
            end
            local check = event_bus.request(events.BUILD_CAN_PLACE_REQUEST, {
                caster = caster,
                player_id = player_id,
                building_id = profile.building_id,
                position = position,
            }) or { ok = false, error = "build_validation_failed" }
            if not check.ok then
                close_preview_session(player_id, session_id)
                reply({
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
            reply({
                success = result and result.ok and 1 or 0,
                error = result and result.ok and ""
                    or (result and result.error or "build_request_failed"),
                building_id = profile.building_id,
            })
        end
    )
end

function M.init()
    for player_id, _ in pairs(preview_areas) do destroy_preview(player_id) end
    preview_areas = {}
    preview_terrain_caches = {}
    last_area_perf_log = -100
    preview_sessions = {}
    closed_preview_sessions = {}
    preview_request_ids = {}
    preview_pose_ids = {}
    require("systems/grid_preview_model_service").clear_all()
    static_area="";static_area_players={}
    scheduler.cancel("grid_static_terrain")
    local grid=require("systems/grid_placement_system")
    if grid.static_preview then
        local job=coroutine.create(function()
            return grid.static_preview({yield_after=128,time_budget=0.002})
        end)
        scheduler.after(0.05,function()
            local ok,result=coroutine.resume(job)
            if not ok then print("[GridPlacement] static terrain failed: "..tostring(result));return end
            if coroutine.status(job)~="dead" then return 0.05 end
            static_area=type(result)=="string" and result or ""
            for player_id in pairs(static_area_players) do
                send(player_id,"ui_grid_placement_static_area",{area=static_area})
            end
            print("[GridPlacement] static terrain ready bytes="..#static_area)
        end,"grid_static_terrain")
    end
    event_bus.subscribe(events.PLAYER_DEFEATED, function(payload)
        destroy_preview(tonumber(payload.player_id))
    end)
    build_profiles()
    register_profile_request()
    register_preview_pose()
    register_validation_request()
    register_preview_end()
    register_commit_request()
    print("[GridPlacement] UI router initialized")
end

M._build_profiles_for_test = build_profiles
M._profiles_for_test = function() return profiles_by_ability end

return M
