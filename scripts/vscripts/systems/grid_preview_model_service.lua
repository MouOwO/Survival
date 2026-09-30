-- One visual-only proxy per player. Pose updates do not query terrain or units.
local scheduler = require("core/scheduler")
local geometry = require("core/building_grid_geometry")
local config = require("config/grid_placement_config")
local previews = {}
local M = {}
local function now() return GameRules:GetGameTime() end
local function valid(unit) return unit and not unit:IsNull() end

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
    if state and (state.building_id ~= profile.building_id or not valid(state.unit)) then
        M.clear(player_id)
        state = nil
    end
    if not state then
        local data = (definition.pre_class_levels or definition.levels or {})[1] or {}
        local model, asset = require("systems/building_visual_service").resolve(data)
        if not model or model == "" then return end
        local unit = CreateUnitByName("npc_survival_grid_preview_proxy", Vector(x,y,z),
            false, caster, caster, caster:GetTeamNumber())
        if not valid(unit) then return end
        unit.survival_is_grid_preview = true
        require("systems/unit_health_bar_service").exclude(unit)
        -- A visual proxy can sit over water/outside the nav mesh. Flying avoids
        -- ground clear-space searches when its phase modifier is removed.
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_FLY)
        unit:SetHullRadius(0)
        unit:AddNewModifier(unit, nil, "modifier_grid_building_preview", {})
        unit:SetOriginalModel(model)
        unit:SetModel(model)
        unit:SetModelScale(tonumber(data.model_scale) or (asset and tonumber(asset.model_scale)) or 1)
        unit:SetSkin((asset and tonumber(asset.model_skin)) or 0)
        unit:SetAngles(0, tonumber(data.model_yaw) or (asset and tonumber(asset.model_yaw)) or 0, 0)
        unit:SetRenderAlpha(tonumber((config.preview_visual or {}).preview_alpha) or 125)
        state = {unit=unit, building_id=profile.building_id}
        previews[player_id] = state
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
