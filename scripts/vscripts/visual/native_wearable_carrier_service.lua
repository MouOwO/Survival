if type(LinkLuaModifier) == "function" then
    LinkLuaModifier(
        "modifier_native_wearable_visual_carrier",
        "modifiers/modifier_native_wearable_visual_carrier",
        LUA_MODIFIER_MOTION_NONE
    )
end

local catalog = require("config/asset_catalog")
local logger = require("core/logger")

local M = {}
local carriers_by_unit = {}
local diagnostic_state_by_unit = {}

local function valid(entity)
    if not entity then return false end
    if type(entity.IsNull) == "function" and entity:IsNull() then return false end
    if type(IsValidEntity) == "function" then
        local ok, is_valid = pcall(IsValidEntity, entity)
        if ok and not is_valid then return false end
    end
    return true
end

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then return false, nil end
    return pcall(method, target, ...)
end

local function entindex(entity)
    local ok, value = safe_call(entity, "entindex")
    return ok and tonumber(value) or nil
end

local function key(unit)
    return valid(unit) and entindex(unit) or nil
end

local function entity_owner(entity)
    for _, method_name in ipairs({ "GetOwner", "GetOwnerEntity" }) do
        if type(entity and entity[method_name]) == "function" then
            local ok, owner = safe_call(entity, method_name)
            if ok and owner ~= nil then return true, owner end
        end
    end
    if entity and entity.owner ~= nil then return true, entity.owner end
    return false, nil
end

local function each_live_entity(class_name, callback)
    if not Entities then return end
    local seen = {}
    local function visit(entity)
        if not valid(entity) then return end
        local index = entindex(entity)
        if index and seen[index] then return end
        if index then seen[index] = true end
        callback(entity)
    end

    if type(Entities.FindAllByClassname) == "function" then
        local ok, entities = pcall(
            Entities.FindAllByClassname,
            Entities,
            class_name
        )
        if ok then
            for _, entity in ipairs(entities or {}) do visit(entity) end
        end
    end
    if type(Entities.FindByClassname) == "function" then
        local previous = nil
        for _ = 1, 4096 do
            local ok, entity = pcall(
                Entities.FindByClassname,
                Entities,
                previous,
                class_name
            )
            if not ok or not valid(entity) or entity == previous then break end
            visit(entity)
            previous = entity
        end
    end
end

local function remove(entity)
    if not valid(entity) then return end
    if type(UTIL_Remove) == "function" then
        pcall(UTIL_Remove, entity)
    else
        safe_call(entity, "RemoveSelf")
    end
end

local function hide_owner(unit, previous)
    if previous then
        if previous.mode == "render_alpha" then
            safe_call(unit, "SetRenderAlpha", 0)
        else
            safe_call(unit, "AddNoDraw")
        end
        return previous
    end
    if type(unit.SetRenderAlpha) == "function" then
        local original_alpha = 255
        local ok, alpha = safe_call(unit, "GetRenderAlpha")
        if ok and tonumber(alpha) then original_alpha = tonumber(alpha) end
        if safe_call(unit, "SetRenderAlpha", 0) then
            return { mode = "render_alpha", original_alpha = original_alpha }
        end
    end
    safe_call(unit, "AddNoDraw")
    return { mode = "no_draw" }
end

local function show_owner(unit, state)
    if not state then return end
    if state.mode == "render_alpha" then
        safe_call(unit, "SetRenderAlpha", state.original_alpha or 255)
    else
        safe_call(unit, "RemoveNoDraw")
    end
end

local function read_hide_state(entity)
    local identity = entity and entity.survival_native_wearable_hide_identity
    if identity ~= nil and identity ~= entity then return nil end
    local mode = entity and entity.survival_native_wearable_hide_mode
    if mode == "render_alpha" then
        return {
            mode = mode,
            original_alpha = tonumber(
                entity.survival_native_wearable_original_alpha
            ) or 255,
        }
    end
    if mode == "no_draw" then return { mode = mode } end
    return nil
end

local function default_hide_state(unit)
    if unit and type(unit.SetRenderAlpha) == "function" then
        return { mode = "render_alpha", original_alpha = 255 }
    end
    return { mode = "no_draw" }
end

local function remember_hide_state(unit, carrier, state)
    for _, entity in ipairs({ unit, carrier }) do
        if entity then
            entity.survival_native_wearable_hide_identity = entity
            entity.survival_native_wearable_hide_mode = state.mode
            entity.survival_native_wearable_original_alpha = state.original_alpha
        end
    end
end

local function forget_hide_state(unit)
    if not unit then return end
    unit.survival_native_wearable_hide_mode = nil
    unit.survival_native_wearable_original_alpha = nil
    unit.survival_native_wearable_hide_identity = nil
end

local function declaration(asset)
    return asset and asset.native_wearables or {}
end

local function wearable_declarations(asset)
    local result = {}
    for _, wearable in ipairs(declaration(asset)) do
        if tostring(wearable.item_def or "") ~= ""
            or tostring(wearable.model_path or "") ~= "" then
            result[#result + 1] = wearable
        end
    end
    return result
end

local function carrier_marked(carrier)
    return valid(carrier)
        and carrier.survival_is_native_wearable_visual == true
end

local function carrier_owned_by(unit, carrier)
    local owner_index = key(unit)
    if not owner_index or not carrier_marked(carrier)
        or tonumber(carrier.survival_native_wearable_owner_entindex)
            ~= owner_index then
        return false
    end
    local owner_ok, owner = entity_owner(carrier)
    return owner_ok and owner == unit
end

local function carrier_stale_for(unit, carrier)
    local owner_index = key(unit)
    if not owner_index or not carrier_marked(carrier)
        or tonumber(carrier.survival_native_wearable_owner_entindex)
            ~= owner_index then
        return false
    end
    local owner_ok, owner = entity_owner(carrier)
    if not owner_ok or owner == nil then return true end
    if owner == unit then return false end
    return not valid(owner) or entindex(owner) ~= owner_index
end

local function carrier_conflicts_with(unit, carrier)
    local owner_index = key(unit)
    return owner_index ~= nil
        and carrier_marked(carrier)
        and tonumber(carrier.survival_native_wearable_owner_entindex)
            == owner_index
        and not carrier_owned_by(unit, carrier)
end

local function child_owned_by(carrier, wearable, owner_index)
    local carrier_index = entindex(carrier)
    if not carrier_index or not valid(wearable)
        or (wearable.survival_is_native_wearable ~= true
            and wearable.survival_native_wearable_key == nil) then
        return false
    end
    if wearable.survival_native_wearable_owner_entindex ~= nil
        and tonumber(wearable.survival_native_wearable_owner_entindex)
            ~= owner_index then
        return false
    end
    if wearable.survival_native_wearable_carrier_entindex ~= nil
        and tonumber(wearable.survival_native_wearable_carrier_entindex)
            ~= carrier_index then
        return false
    end
    local owner_ok, owner = entity_owner(wearable)
    return owner_ok and owner == carrier
end

local function child_matches(wearable, definition)
    if not valid(wearable) or not definition then return false end
    if wearable.survival_native_wearable_key ~= definition.wearable_key
        or tostring(wearable.survival_native_wearable_item_def or "")
            ~= tostring(definition.item_def or "") then
        return false
    end
    local class_ok, class_name = safe_call(wearable, "GetClassname")
    if class_ok and class_name ~= definition.entity_class then return false end
    local model_ok, model_name = safe_call(wearable, "GetModelName")
    return not model_ok or model_name == definition.model_path
end

local function remove_carrier_children(carrier)
    each_live_entity("dota_item_wearable", function(wearable)
        local owner_ok, owner = entity_owner(wearable)
        if owner_ok and owner == carrier
            and (wearable.survival_is_native_wearable == true
                or wearable.survival_native_wearable_key ~= nil) then
            remove(wearable)
        end
    end)
end

local function remove_carrier(carrier, wearables)
    for _, wearable in ipairs(wearables or {}) do remove(wearable) end
    remove_carrier_children(carrier)
    remove(carrier)
end

local function entity_value(entity, method_name, fallback)
    local ok, value = safe_call(entity, method_name)
    if ok and value ~= nil and tostring(value) ~= "" then
        return tostring(value)
    end
    return fallback or "<unavailable>"
end

local function item_def_list(asset)
    local values = {}
    for _, wearable in ipairs(declaration(asset)) do
        local item_def = tostring(wearable.item_def or "")
        if item_def ~= "" then values[#values + 1] = item_def end
    end
    return #values > 0 and table.concat(values, "|") or "<none>"
end

local function wearable_list(wearables)
    local values = {}
    for _, wearable in ipairs(wearables or {}) do
        values[#values + 1] = string.format(
            "%s:%s:%s:%s",
            tostring(wearable.survival_native_wearable_key or "<unknown>"),
            tostring(wearable.survival_native_wearable_item_def or "<unknown>"),
            entity_value(wearable, "GetModelName", "<unavailable>"),
            entity_value(wearable, "entindex", "<unavailable>")
        )
    end
    return #values > 0 and table.concat(values, "|") or "<none>"
end

local function diagnostic_context(unit, asset, carrier, wearables)
    return string.format(
        "asset=%s owner=%s expected_unit=%s actual_unit=%s expected_body=%s actual_body=%s item_defs=%s wearables_expected=%s wearables_created=%s wearables=%s",
        tostring(asset and asset.asset_id or "<none>"),
        tostring(key(unit) or -1),
        tostring(asset and asset.async_unit_name or "<missing>"),
        carrier and entity_value(carrier, "GetUnitName") or "<none>",
        tostring(asset and asset.primary_model or "<missing>"),
        carrier and entity_value(carrier, "GetModelName") or "<none>",
        item_def_list(asset),
        tostring(#wearable_declarations(asset)),
        tostring(#(wearables or {})),
        wearable_list(wearables)
    )
end

local function diagnostic_failure(unit, asset, status, carrier, phase, wearables)
    local state_key = table.concat({
        tostring(asset and asset.asset_id or "<none>"),
        tostring(status),
        tostring(phase or "unknown"),
    }, ":")
    local owner_index = key(unit)
    if owner_index and diagnostic_state_by_unit[owner_index] == state_key then return end
    if owner_index then diagnostic_state_by_unit[owner_index] = state_key end
    logger.warn(
        "NativeWearableCarrier",
        "failure status=" .. tostring(status)
            .. " phase=" .. tostring(phase or "unknown")
            .. " " .. diagnostic_context(unit, asset, carrier, wearables)
    )
end

local function diagnostic_success(unit, asset, state, mode)
    local context = diagnostic_context(
        unit,
        asset,
        state.carrier,
        state.wearables
    )
    local state_key = tostring(mode) .. ":" .. context
    local owner_index = key(unit)
    if owner_index and diagnostic_state_by_unit[owner_index] == state_key then return end
    if owner_index then diagnostic_state_by_unit[owner_index] = state_key end
    logger.info(
        "NativeWearableCarrier",
        "ready mode=" .. tostring(mode)
            .. " carrier=" .. entity_value(state.carrier, "entindex")
            .. " " .. context
    )
end

local function angle_component(value, name, index)
    if value == nil then return nil end
    local ok, component = pcall(function()
        return value[name] or value[index]
    end)
    return ok and tonumber(component) or nil
end

local function read_angles(unit)
    for _, method_name in ipairs({ "GetAngles", "GetAnglesAsVector" }) do
        local ok, angles = safe_call(unit, method_name)
        if ok and angles then
            local pitch = angle_component(angles, "x", 1)
            local yaw = angle_component(angles, "y", 2)
            local roll = angle_component(angles, "z", 3)
            if pitch and yaw and roll then return pitch, yaw, roll end
        end
    end
    return nil
end

local function sync_transform(unit, carrier)
    if not valid(unit) or not valid(carrier) then return false end
    local position_ok, position = safe_call(unit, "GetAbsOrigin")
    if not position_ok or not position then return false end
    local set_ok, set_result = safe_call(carrier, "SetAbsOrigin", position)
    if not set_ok or set_result == false then return false end

    local pitch, yaw, roll = read_angles(unit)
    if pitch and yaw and roll and type(carrier.SetAngles) == "function" then
        local angles_ok, angles_result = safe_call(
            carrier,
            "SetAngles",
            pitch,
            yaw,
            roll
        )
        return angles_ok and angles_result ~= false
    end
    local forward_ok, forward = safe_call(unit, "GetForwardVector")
    if forward_ok and forward and type(carrier.SetForwardVector) == "function" then
        local x = angle_component(forward, "x", 1)
        local y = angle_component(forward, "y", 2)
        local z = angle_component(forward, "z", 3)
        if x and y and z then
            local applied, result = safe_call(
                carrier,
                "SetForwardVector",
                forward
            )
            return applied and result ~= false
        end
    end
    return true
end

local function carrier_matches_asset(unit, carrier, asset)
    if not carrier_owned_by(unit, carrier) or not asset then return false end
    if tostring(carrier.survival_model_asset_id or "")
        ~= tostring(asset.asset_id or "") then
        return false
    end
    local unit_ok, unit_name = safe_call(carrier, "GetUnitName")
    if unit_ok and unit_name ~= asset.async_unit_name then return false end
    local model_ok, model_name = safe_call(carrier, "GetModelName")
    return not model_ok or model_name == asset.primary_model
end

local function recover_wearables(unit, carrier, asset)
    local expected = wearable_declarations(asset)
    local candidates = {}
    each_live_entity("dota_item_wearable", function(wearable)
        if child_owned_by(carrier, wearable, key(unit)) then
            candidates[#candidates + 1] = wearable
        end
    end)
    table.sort(candidates, function(a, b)
        return (entindex(a) or math.huge) < (entindex(b) or math.huge)
    end)

    local selected = {}
    local used = {}
    for _, definition in ipairs(expected) do
        local match = nil
        for _, wearable in ipairs(candidates) do
            if not used[wearable] and child_matches(wearable, definition) then
                match = wearable
                break
            end
        end
        if not match then return nil end
        used[match] = true
        match.survival_is_native_wearable = true
        match.survival_native_wearable_owner_entindex = key(unit)
        match.survival_native_wearable_carrier_entindex = entindex(carrier)
        selected[#selected + 1] = match
    end
    for _, wearable in ipairs(candidates) do
        if not used[wearable] then remove(wearable) end
    end
    return selected
end

local function state_complete(state, asset)
    if not state or state.owner == nil
        or not carrier_matches_asset(state.owner, state.carrier, asset) then
        return false
    end
    local expected = wearable_declarations(asset)
    local actual = state.wearables or {}
    if #actual ~= #expected then return false end
    for index, definition in ipairs(expected) do
        local wearable = actual[index]
        if not child_owned_by(state.carrier, wearable, key(state.owner))
            or not child_matches(wearable, definition) then
            return false
        end
    end
    return true
end

local function recover_state(unit, carrier, asset)
    if not carrier_matches_asset(unit, carrier, asset) then return nil end
    local wearables = recover_wearables(unit, carrier, asset)
    if not wearables then return nil end
    local state = {
        owner = unit,
        asset = asset,
        asset_id = asset.asset_id,
        carrier = carrier,
        wearables = wearables,
        hide_state = read_hide_state(unit) or read_hide_state(carrier),
    }
    safe_call(carrier, "RemoveNoDraw")
    for _, wearable in ipairs(wearables) do safe_call(wearable, "RemoveNoDraw") end
    return state
end

local function all_live_carriers()
    local result = {}
    each_live_entity("npc_dota_creature", function(carrier)
        if carrier_marked(carrier) then result[#result + 1] = carrier end
    end)
    return result
end

local function reconcile(unit, requested_asset, preserve_duplicates, allow_rebind)
    local owner_index = key(unit)
    if not owner_index then return nil end
    local registered = carriers_by_unit[owner_index]
    if registered and registered.owner ~= unit then
        if not allow_rebind then return nil end
        registered = nil
    end

    local candidates = {}
    local seen = {}
    local complete = {}
    local owned = {}
    for _, carrier in ipairs(all_live_carriers()) do
        if carrier_stale_for(unit, carrier) then
            remove_carrier(carrier)
        elseif carrier_owned_by(unit, carrier) then
            owned[#owned + 1] = carrier
            local asset_id = tostring(carrier.survival_model_asset_id or "")
            local asset = catalog.get(asset_id)
            if requested_asset and asset_id == tostring(requested_asset.asset_id) then
                asset = requested_asset
            end
            local state = asset and recover_state(unit, carrier, asset) or nil
            if state then
                candidates[#candidates + 1] = state
                seen[carrier] = true
                complete[carrier] = true
            end
        end
    end
    if registered and not seen[registered.carrier] then
        local asset = registered.asset
        if requested_asset
            and registered.asset_id == requested_asset.asset_id then
            asset = requested_asset
        end
        if state_complete(registered, asset) then
            candidates[#candidates + 1] = registered
            complete[registered.carrier] = true
        end
    end

    table.sort(candidates, function(a, b)
        local a_requested = requested_asset
            and a.asset_id == requested_asset.asset_id
        local b_requested = requested_asset
            and b.asset_id == requested_asset.asset_id
        if a_requested ~= b_requested then return a_requested end
        return (entindex(a.carrier) or math.huge)
            < (entindex(b.carrier) or math.huge)
    end)
    local selected = candidates[1]
    if not selected then
        for _, carrier in ipairs(owned) do remove_carrier(carrier) end
        return nil
    end
    for _, carrier in ipairs(owned) do
        if not complete[carrier]
            or (not preserve_duplicates and carrier ~= selected.carrier) then
            remove_carrier(carrier)
        end
    end
    selected.hide_state = selected.hide_state or default_hide_state(unit)
    hide_owner(unit, selected.hide_state)
    remember_hide_state(unit, selected.carrier, selected.hide_state)
    carriers_by_unit[owner_index] = selected
    return selected
end

local function spawn_wearables(unit, carrier, asset)
    local spawned = {}
    for _, definition in ipairs(wearable_declarations(asset)) do
        local item_def = tostring(definition.item_def or "")
        local model_path = tostring(definition.model_path or "")
        local entity_class = tostring(definition.entity_class or "")
        local attach_mode = tostring(definition.attach_mode or "")
        if item_def == "" or model_path == "" then
            diagnostic_failure(
                unit,
                asset,
                "wearable_declaration_invalid",
                carrier,
                "validate",
                spawned
            )
            return nil, "wearable_declaration_invalid"
        end
        if entity_class ~= "dota_item_wearable" or attach_mode ~= "bone_merge" then
            diagnostic_failure(
                unit,
                asset,
                "wearable_attachment_contract_invalid",
                carrier,
                "validate",
                spawned
            )
            return nil, "wearable_attachment_contract_invalid"
        end
        if type(SpawnEntityFromTableSynchronous) ~= "function" then
            diagnostic_failure(
                unit,
                asset,
                "wearable_factory_missing",
                carrier,
                "create",
                spawned
            )
            return nil, "wearable_factory_missing"
        end
        local create_ok, wearable = pcall(
            SpawnEntityFromTableSynchronous,
            entity_class,
            { model = model_path }
        )
        if not create_ok or not valid(wearable) then
            diagnostic_failure(
                unit,
                asset,
                "wearable_create_failed",
                carrier,
                "create",
                spawned
            )
            remove(wearable)
            return nil, "wearable_create_failed"
        end
        safe_call(wearable, "SetModel", model_path)
        safe_call(wearable, "SetOriginalModel", model_path)
        safe_call(wearable, "AddNoDraw")
        local owner_ok, owner_result = safe_call(wearable, "SetOwner", carrier)
        if not owner_ok or owner_result == false then
            diagnostic_failure(
                unit,
                asset,
                "wearable_attach_failed",
                carrier,
                "set_owner",
                spawned
            )
            remove(wearable)
            return nil, "wearable_attach_failed"
        end
        local follow_ok, follow_result = safe_call(
            wearable,
            "FollowEntity",
            carrier,
            true
        )
        if not follow_ok or follow_result == false then
            diagnostic_failure(
                unit,
                asset,
                "wearable_attach_failed",
                carrier,
                "follow_entity",
                spawned
            )
            remove(wearable)
            return nil, "wearable_attach_failed"
        end
        safe_call(wearable, "SetSolid", rawget(_G, "SOLID_NONE") or 0)
        wearable.survival_is_native_wearable = true
        wearable.survival_native_wearable_owner_entindex = key(unit)
        wearable.survival_native_wearable_carrier_entindex = entindex(carrier)
        wearable.survival_native_wearable_key = definition.wearable_key
        wearable.survival_native_wearable_item_def = item_def
        spawned[#spawned + 1] = wearable
    end
    return spawned
end

local function create_carrier(unit, asset)
    if type(CreateUnitByName) ~= "function" then
        diagnostic_failure(unit, asset, "carrier_factory_missing", nil, "create")
        return nil, "carrier_factory_missing"
    end
    local position_ok, position = safe_call(unit, "GetAbsOrigin")
    if not position_ok or not position then
        diagnostic_failure(unit, asset, "carrier_position_missing", nil, "create")
        return nil, "carrier_position_missing"
    end
    local team = 0
    local team_ok, resolved_team = safe_call(unit, "GetTeamNumber")
    if team_ok and resolved_team ~= nil then team = resolved_team end
    local unit_name = tostring(asset.async_unit_name or "")
    local create_ok, carrier = pcall(
        CreateUnitByName,
        unit_name,
        position,
        false,
        unit,
        unit,
        team
    )
    if not create_ok or not valid(carrier) then
        diagnostic_failure(unit, asset, "carrier_create_failed", carrier, "create")
        return nil, "carrier_create_failed"
    end

    safe_call(carrier, "AddNoDraw")
    local owner_ok, owner_result = safe_call(carrier, "SetOwner", unit)
    local transform_ok = sync_transform(unit, carrier)
    if not owner_ok or owner_result == false or not transform_ok then
        diagnostic_failure(unit, asset, "carrier_attach_failed", carrier, "attach")
        remove(carrier)
        return nil, "carrier_attach_failed"
    end
    local player_id = -1
    local player_ok, resolved_player = safe_call(unit, "GetPlayerOwnerID")
    if player_ok and tonumber(resolved_player) then
        player_id = tonumber(resolved_player)
    end
    safe_call(carrier, "SetControllableByPlayer", player_id, false)
    local modifier_ok, modifier = safe_call(
        carrier,
        "AddNewModifier",
        carrier,
        nil,
        "modifier_native_wearable_visual_carrier",
        {}
    )
    if not modifier_ok or not modifier then
        diagnostic_failure(unit, asset, "carrier_modifier_failed", carrier, "modifier")
        remove(carrier)
        return nil, "carrier_modifier_failed"
    end

    carrier.survival_is_native_wearable_visual = true
    carrier.survival_native_wearable_owner_entindex = key(unit)
    carrier.survival_model_asset_id = asset.asset_id
    local wearables, wearable_status = spawn_wearables(unit, carrier, asset)
    if not wearables then
        remove_carrier(carrier)
        return nil, wearable_status
    end
    return carrier, wearables
end

function M.IsNativeWearableAsset(asset)
    return #declaration(asset) > 0
end

function M.Has(unit)
    local state = reconcile(unit, nil)
    return state ~= nil and state_complete(state, state.asset)
end

function M.Matches(unit, asset)
    local state = reconcile(unit, asset)
    return M.IsNativeWearableAsset(asset)
        and state ~= nil
        and state.asset_id == asset.asset_id
        and state_complete(state, asset)
end

function M.Apply(unit, asset)
    local owner_index = key(unit)
    if not owner_index then
        diagnostic_failure(unit, asset, "invalid_entity", nil, "validate_owner")
        return false, "invalid_entity"
    end
    if not M.IsNativeWearableAsset(asset) then
        diagnostic_failure(unit, asset, "native_wearables_missing", nil, "validate_asset")
        return false, "native_wearables_missing"
    end
    if tostring(asset.async_unit_name or "") == "" then
        diagnostic_failure(unit, asset, "carrier_unit_missing", nil, "validate_asset")
        return false, "carrier_unit_missing"
    end

    local previous = reconcile(unit, asset, true, true)
    local mapped = carriers_by_unit[owner_index]
    if not previous and mapped and mapped.owner == unit then previous = mapped end
    if previous and previous.asset_id == asset.asset_id
        and state_complete(previous, asset) then
        if not sync_transform(unit, previous.carrier) then
            diagnostic_failure(unit, asset, "carrier_sync_failed", previous.carrier, "reuse_sync")
            return false, "carrier_sync_failed"
        end
        previous.hide_state = hide_owner(unit, previous.hide_state)
        remember_hide_state(unit, previous.carrier, previous.hide_state)
        safe_call(previous.carrier, "RemoveNoDraw")
        for _, other in ipairs(all_live_carriers()) do
            if other ~= previous.carrier
                and (carrier_owned_by(unit, other)
                    or carrier_conflicts_with(unit, other)) then
                remove_carrier(other)
            end
        end
        carriers_by_unit[owner_index] = previous
        diagnostic_success(unit, asset, previous, "reuse")
        return true, asset.asset_id, previous.carrier
    end

    local carrier, wearables_or_status = create_carrier(unit, asset)
    if not carrier then return false, wearables_or_status end
    local wearables = wearables_or_status
    local hide_state = previous and previous.hide_state
        or read_hide_state(unit)
    if hide_state then
        hide_owner(unit, hide_state)
    else
        hide_state = hide_owner(unit, nil)
    end
    local state = {
        owner = unit,
        asset = asset,
        asset_id = asset.asset_id,
        carrier = carrier,
        wearables = wearables,
        hide_state = hide_state,
    }
    carriers_by_unit[owner_index] = state
    remember_hide_state(unit, carrier, hide_state)
    safe_call(carrier, "RemoveNoDraw")
    for _, wearable in ipairs(wearables) do safe_call(wearable, "RemoveNoDraw") end
    if previous and previous.carrier ~= carrier then
        remove_carrier(previous.carrier, previous.wearables)
    end
    for _, other in ipairs(all_live_carriers()) do
        if other ~= carrier
            and (carrier_owned_by(unit, other)
                or carrier_conflicts_with(unit, other)) then
            remove_carrier(other)
        end
    end
    diagnostic_success(unit, asset, state, previous and "replace" or "create")
    return true, asset.asset_id, carrier
end

function M.Refresh(unit, asset)
    return M.Apply(unit, asset)
end

function M.Sync(unit)
    local state = reconcile(unit, nil)
    if not state then return false end
    if not state_complete(state, state.asset) then
        diagnostic_failure(unit, state.asset, "wearable_missing", state.carrier, "sync_validate")
        return false
    end
    if not sync_transform(unit, state.carrier) then
        diagnostic_failure(unit, state.asset, "carrier_sync_failed", state.carrier, "sync_transform")
        return false
    end
    return true
end

function M.Clear(unit)
    local owner_index = key(unit)
    local state = owner_index and carriers_by_unit[owner_index]
    if state and state.owner ~= unit then return end
    local hide_state = state and state.hide_state or read_hide_state(unit)
    if state then remove_carrier(state.carrier, state.wearables) end
    for _, carrier in ipairs(all_live_carriers()) do
        if carrier_owned_by(unit, carrier) then
            hide_state = hide_state or read_hide_state(carrier)
            remove_carrier(carrier)
        end
    end
    if owner_index then
        carriers_by_unit[owner_index] = nil
        diagnostic_state_by_unit[owner_index] = nil
    end
    if valid(unit) and hide_state then
        show_owner(unit, hide_state)
        forget_hide_state(unit)
    end
end

function M.StartGesture(unit, activity, playback_rate)
    if activity == nil then return false end
    local state = reconcile(unit, nil)
    if not state or not state_complete(state, state.asset) then return false end
    if tonumber(playback_rate)
        and type(state.carrier.StartGestureWithPlaybackRate) == "function" then
        safe_call(
            state.carrier,
            "StartGestureWithPlaybackRate",
            activity,
            tonumber(playback_rate)
        )
    else
        safe_call(state.carrier, "StartGesture", activity)
    end
    return true
end

function M._count_for_test()
    local count = 0
    for _, state in pairs(carriers_by_unit) do
        if state_complete(state, state.asset) then count = count + 1 end
    end
    return count
end

function M._wearable_count_for_test(unit)
    local owner_index = key(unit)
    local state = owner_index and carriers_by_unit[owner_index]
    return state and #(state.wearables or {}) or 0
end

function M._live_carrier_count_for_test(unit)
    local count = 0
    for _, carrier in ipairs(all_live_carriers()) do
        if carrier_owned_by(unit, carrier) then count = count + 1 end
    end
    return count
end

return M