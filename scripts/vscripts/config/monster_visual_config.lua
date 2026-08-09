local visual_assets = require("config/generated/monster_visual_assets")
local visual_components = require("config/generated/monster_visual_components")
local visual_effects = require("config/generated/monster_visual_effects")
local wave_visuals = require("config/generated/wave_visual_definitions")

local M = {}

local components_by_asset = {}
local effects_by_asset = {}

local function add_resource(result, seen, resource_type, path, async_unit_name)
    path = tostring(path or "")
    local key = resource_type .. ":" .. path
    if path == "" or seen[key] then return end
    seen[key] = true
    result[#result + 1] = {
        resource_type = resource_type,
        path = path,
        async_unit_name = async_unit_name,
    }
end

local function append_enabled(grouped, row)
    if row.enabled == false then return end
    local asset_id = tostring(row.visual_asset_id or "")
    if asset_id == "" then return end
    grouped[asset_id] = grouped[asset_id] or {}
    grouped[asset_id][#grouped[asset_id] + 1] = row
end

for _, row in ipairs(visual_components.rows or {}) do
    append_enabled(components_by_asset, row)
end
for _, row in ipairs(visual_effects.rows or {}) do
    append_enabled(effects_by_asset, row)
end

local function enabled_wave(wave_number)
    local row = wave_visuals.by_id[tonumber(wave_number)]
    if row and row.enabled ~= false then return row end
    return nil
end

function M.asset(visual_asset_id)
    local visited = {}
    local current_id = tostring(visual_asset_id or "")
    while current_id ~= "" and not visited[current_id] do
        visited[current_id] = true
        local row = visual_assets.by_id[current_id]
        if row and row.enabled ~= false
            and tostring(row.model_path or "") ~= "" then
            return row
        end
        current_id = row and tostring(row.fallback_visual_asset_id or "") or ""
    end
    return nil
end

local function role_selection(wave, member_role, normal_index)
    if member_role == "assault_boss" then
        return wave.stage_boss_visual_asset_id
                or wave.mini_boss_visual_asset_id
                or wave.main_visual_asset_id,
            wave.stage_boss_scale or wave.mini_boss_scale or wave.main_scale,
            "stage_boss"
    end
    if member_role == "wave_leader" then
        return wave.mini_boss_visual_asset_id or wave.main_visual_asset_id,
            wave.mini_boss_scale or wave.main_scale,
            "mini_boss"
    end

    local support_every = math.floor(tonumber(wave.support_every_nth) or 0)
    local instance_index = math.max(1, math.floor(tonumber(normal_index) or 1))
    if support_every > 0 and wave.support_visual_asset_id
        and instance_index % support_every == 0 then
        return wave.support_visual_asset_id,
            wave.support_scale or wave.main_scale,
            "support"
    end
    return wave.main_visual_asset_id, wave.main_scale, "main"
end

function M.resolve(wave_number, member_role, normal_index)
    local wave = enabled_wave(wave_number)
    if not wave then return nil, "wave_visual_not_found" end
    local requested_id, scale, visual_role = role_selection(
        wave,
        tostring(member_role or "normal"),
        normal_index
    )
    local asset = M.asset(requested_id)
    if not asset then return nil, "visual_asset_not_found" end
    return {
        wave_number = tonumber(wave_number),
        visual_role = visual_role,
        requested_visual_asset_id = requested_id,
        visual_asset_id = asset.visual_asset_id,
        model_path = asset.model_path,
        model_scale = tonumber(scale) or 1,
        assembly_mode = asset.assembly_mode,
        components = components_by_asset[asset.visual_asset_id] or {},
        effects = effects_by_asset[asset.visual_asset_id] or {},
    }
end

function M.append_resources_for_wave(wave_number, result, seen)
    local wave = enabled_wave(wave_number)
    result = result or {}
    seen = seen or {}
    if not wave then return result, seen end
    for _, asset_id in ipairs({
        wave.main_visual_asset_id,
        wave.support_visual_asset_id,
        wave.mini_boss_visual_asset_id,
        wave.stage_boss_visual_asset_id,
    }) do
        local asset = M.asset(asset_id)
        if asset then
            add_resource(result, seen, "model", asset.model_path,
                asset.async_unit_name)
            for _, component in ipairs(components_by_asset[asset.visual_asset_id] or {}) do
                add_resource(result, seen, "model", component.model_path)
            end
            for _, effect in ipairs(effects_by_asset[asset.visual_asset_id] or {}) do
                add_resource(result, seen, "particle", effect.particle_path)
            end
        end
    end
    return result, seen
end

function M.resources_for_wave(wave_number)
    return M.append_resources_for_wave(wave_number, {}, {})
end

function M._select_role_for_test(wave, member_role, normal_index)
    return role_selection(wave, member_role, normal_index)
end

return M