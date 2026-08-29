if type(LinkLuaModifier) == "function" then
    LinkLuaModifier(
        "modifier_native_wearable_visual_carrier",
        "modifiers/modifier_native_wearable_visual_carrier",
        LUA_MODIFIER_MOTION_NONE
    )
end

local M = {}
local carriers_by_unit = {}

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

local function remove(entity)
    if not valid(entity) then return end
    if type(UTIL_Remove) == "function" then
        pcall(UTIL_Remove, entity)
    else
        safe_call(entity, "RemoveSelf")
    end
end

local function key(unit)
    return valid(unit) and type(unit.entindex) == "function" and unit:entindex() or nil
end

local function hide_owner(unit, previous_state)
    if previous_state then
        if previous_state.mode == "render_alpha" then
            safe_call(unit, "SetRenderAlpha", 0)
        else
            safe_call(unit, "AddNoDraw")
        end
        return previous_state
    end
    if type(unit.SetRenderAlpha) == "function" then
        local original_alpha = 255
        local alpha_ok, resolved_alpha = safe_call(unit, "GetRenderAlpha")
        if alpha_ok and tonumber(resolved_alpha) then
            original_alpha = tonumber(resolved_alpha)
        end
        local hidden = safe_call(unit, "SetRenderAlpha", 0)
        if hidden then
            return {
                mode = "render_alpha",
                original_alpha = original_alpha,
            }
        end
    end
    safe_call(unit, "AddNoDraw")
    return { mode = "no_draw" }
end

local function show_owner(unit, hide_state)
    if hide_state and hide_state.mode == "render_alpha" then
        safe_call(unit, "SetRenderAlpha", hide_state.original_alpha or 255)
    else
        safe_call(unit, "RemoveNoDraw")
    end
end

local function declaration(asset)
    return asset and asset.native_wearables or {}
end

function M.IsNativeWearableAsset(asset)
    return #declaration(asset) > 0
end

function M.Has(unit)
    local entindex = key(unit)
    local state = entindex and carriers_by_unit[entindex]
    return state ~= nil and state.owner == unit and valid(state.carrier)
end

function M.Matches(unit, asset)
    local entindex = key(unit)
    local state = entindex and carriers_by_unit[entindex]
    return M.IsNativeWearableAsset(asset)
        and state ~= nil
        and state.owner == unit
        and state.asset_id == asset.asset_id
        and valid(state.carrier)
end

function M.Apply(unit, asset)
    local entindex = key(unit)
    if not entindex then return false, "invalid_entity" end
    if not M.IsNativeWearableAsset(asset) then
        return false, "native_wearables_missing"
    end

    local unit_name = tostring(asset.async_unit_name or "")
    if unit_name == "" then return false, "carrier_unit_missing" end
    local previous = carriers_by_unit[entindex]
    if previous and previous.owner ~= unit then
        remove(previous.carrier)
        carriers_by_unit[entindex] = nil
        previous = nil
    end
    if previous and previous.asset_id == asset.asset_id and valid(previous.carrier) then
        previous.hide_state = hide_owner(unit, previous.hide_state)
        return true, asset.asset_id, previous.carrier
    end
    if type(CreateUnitByName) ~= "function" then
        return false, "carrier_factory_missing"
    end

    local ok_position, position = safe_call(unit, "GetAbsOrigin")
    if not ok_position or not position then return false, "carrier_position_missing" end
    local team = 0
    local ok_team, resolved_team = safe_call(unit, "GetTeamNumber")
    if ok_team and resolved_team ~= nil then team = resolved_team end
    local ok_create, carrier = pcall(
        CreateUnitByName,
        unit_name,
        position,
        false,
        unit,
        unit,
        team
    )
    if not ok_create or not valid(carrier) then
        return false, "carrier_create_failed"
    end

    safe_call(carrier, "AddNoDraw")
    local owner_ok = safe_call(carrier, "SetOwner", unit)
    -- This is a complete hero visual carrier, not a wearable. Follow the
    -- building transform without merging the hero skeleton into the tower.
    local follow_ok = safe_call(carrier, "FollowEntity", unit, false)
    if not owner_ok or not follow_ok then
        remove(carrier)
        return false, "carrier_attach_failed"
    end
    local player_id = -1
    local ok_player, resolved_player = safe_call(unit, "GetPlayerOwnerID")
    if ok_player and tonumber(resolved_player) then player_id = tonumber(resolved_player) end
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
        remove(carrier)
        return false, "carrier_modifier_failed"
    end
    carrier.survival_is_native_wearable_visual = true
    carrier.survival_native_wearable_owner_entindex = entindex
    carrier.survival_model_asset_id = asset.asset_id

    carriers_by_unit[entindex] = {
        owner = unit,
        asset_id = asset.asset_id,
        carrier = carrier,
        hide_state = hide_owner(unit, previous and previous.hide_state),
    }
    safe_call(carrier, "RemoveNoDraw")
    if previous then remove(previous.carrier) end
    return true, asset.asset_id, carrier
end

function M.Refresh(unit, asset)
    return M.Apply(unit, asset)
end

function M.Clear(unit)
    local entindex = key(unit)
    local state = entindex and carriers_by_unit[entindex]
    if state and state.owner ~= unit then return end
    if state then remove(state.carrier) end
    if entindex then carriers_by_unit[entindex] = nil end
    if state and valid(unit) then show_owner(unit, state.hide_state) end
end

function M.StartGesture(unit, activity, playback_rate)
    if activity == nil then return false end
    local entindex = key(unit)
    local state = entindex and carriers_by_unit[entindex]
    if not state or state.owner ~= unit or not valid(state.carrier) then
        return false
    end
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
        if valid(state.carrier) then count = count + 1 end
    end
    return count
end

return M