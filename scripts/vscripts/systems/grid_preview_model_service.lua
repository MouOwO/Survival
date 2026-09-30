-- One visual-only proxy per player. Pose updates do not query terrain or units.
local scheduler = require("core/scheduler")
local geometry = require("core/building_grid_geometry")
local config = require("config/grid_placement_config")
local previews = {}
local M = {}
local function now() return GameRules:GetGameTime() end
local function valid(unit) return unit and not unit:IsNull() end
local function optional_value(unit, method_name)
    local method = unit and unit[method_name]
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, unit)
    if ok then return value end
    return nil
end

function M.clear(player_id)
    local state = previews[player_id]
    previews[player_id] = nil
    scheduler.cancel("grid_preview_model:" .. tostring(player_id))
    if state and valid(state.unit) then UTIL_Remove(state.unit) end
end

function M.clear_all()
    for player_id in pairs(previews) do M.clear(player_id) end
end

function M.update(player_id, caster, profile, position)
    local definition = require("config/buildings_config")[profile.building_id]
    if not definition then return end
    local _, x = geometry.snap_axis(position.x, profile.grid_footprint_x)
    local _, y = geometry.snap_axis(position.y, profile.grid_footprint_y)
    local z = tonumber(config.build_ground_height) or position.z
    local state = previews[player_id]
    local moving = profile.placement_action == "relocate"
    if state and (state.building_id ~= profile.building_id or state.moving ~= moving
        or (moving and state.caster ~= caster) or not valid(state.unit)) then
        M.clear(player_id)
        state = nil
    end
    if not state then
        local data = (definition.pre_class_levels or definition.levels or {})[1] or {}
        local model, asset = require("systems/building_visual_service").resolve(data)
        if moving then model = caster:GetModelName() end
        if not model or model == "" then return end
        local unit = CreateUnitByName("npc_survival_grid_preview_proxy", Vector(x,y,z),
            false, caster, caster, caster:GetTeamNumber())
        if not valid(unit) then return end
        -- Track before configuring: an engine API failure must not leak one
        -- untracked proxy per preview update.
        state = {unit=unit, building_id=profile.building_id, moving=moving}
        previews[player_id] = state
        local configured, failure = pcall(function()
        unit.survival_is_grid_preview = true
        require("systems/unit_health_bar_service").exclude(unit)
        -- A visual proxy can sit over water/outside the nav mesh. Flying avoids
        -- ground clear-space searches when its phase modifier is removed.
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_FLY)
        unit:SetHullRadius(0)
        unit:AddNewModifier(unit, nil, "modifier_grid_building_preview", {})
        unit:SetOriginalModel(model)
        unit:SetModel(model)
        unit:SetModelScale(moving and caster:GetModelScale()
            or tonumber(data.model_scale) or (asset and tonumber(asset.model_scale)) or 1)
        local skin = asset and tonumber(asset.model_skin) or 0
        if moving then
            -- Dota NPC handles expose SetSkin but may have no GetSkin. Resolve
            -- the tower's applied asset instead of falling back to LV1 art.
            local current = caster.survival_model_asset_id
                and require("config/asset_catalog").resolve(caster.survival_model_asset_id)
            skin = tonumber(optional_value(caster, "GetSkin"))
                or (current and tonumber(current.model_skin)) or 0
        end
        if type(unit.SetSkin) == "function" then unit:SetSkin(skin) end
        local angles = moving and optional_value(caster, "GetAngles") or nil
        unit:SetAngles(0, angles and angles.y or tonumber(data.model_yaw)
            or (asset and tonumber(asset.model_yaw)) or 0, 0)
        unit:SetRenderAlpha(tonumber((config.preview_visual or {}).preview_alpha) or 125)
        end)
        if not configured then
            M.clear(player_id)
            print("[GridPreviewModel] proxy configuration failed: " .. tostring(failure))
            return
        end
        -- Also cleans up abandoned sessions after UI reload/disconnection.
        scheduler.after(1, function()
            if previews[player_id] ~= state then return end
            if not valid(state.caster) or (state.caster.IsAlive and not state.caster:IsAlive())
                or now() - state.seen > 2 then M.clear(player_id); return end
            return 1
        end, "grid_preview_model:" .. tostring(player_id))
    end
    state.caster = caster
    state.seen = now()
    if state.x ~= x or state.y ~= y or state.z ~= z then
        state.unit:SetAbsOrigin(Vector(x,y,z))
        state.x, state.y, state.z = x, y, z
    end
end

return M
