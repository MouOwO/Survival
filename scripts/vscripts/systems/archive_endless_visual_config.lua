-- Visual-only endless cycle. Combat rows and collision stay in their existing
-- configuration; every monster born in a wave receives the same resolved row.
local rows = require("config/generated/archive_endless_visuals")
local components = require("config/generated/archive_endless_visual_components")
local ornaments = require("config/generated/archive_endless_visual_ornaments")

local M = {}
local templates, resolved, resources

local function vector(x, y, z)
    return { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0 }
end

local function initialize()
    if templates then return end
    local built, seen_models, listed = {}, {}, {}
    local function add_resource(path)
        assert(type(path) == "string" and path ~= "", "endless_visual_model_missing")
        if not seen_models[path] then
            seen_models[path] = true
            listed[#listed + 1] = { resource_type = "model", path = path }
        end
    end
    local by_id = {}
    for _, row in ipairs(rows.rows) do
        if row.enabled ~= false then
            local slot, round = tonumber(row.cycle_slot), tonumber(row.outfit_round)
            assert(slot and slot >= 1 and slot <= 50 and slot == math.floor(slot),
                "endless_visual_slot_invalid")
            assert(round and round >= 1 and round <= 4 and round == math.floor(round),
                "endless_visual_round_invalid")
            local key = slot .. ":" .. round
            assert(not built[key] and not by_id[row.visual_id], "endless_visual_duplicate")
            local scale = tonumber(row.base_scale)
            assert(scale and scale > 0, "endless_visual_scale_invalid")
            local entry = {
                visual_id = row.visual_id, asset_id = row.visual_id,
                cycle_slot = slot, outfit_round = round,
                display_name = row.display_name, outfit_name = row.outfit_name,
                model_path = row.model_path, base_scale = scale,
                model_skin = row.model_skin, components = {}, ornaments = {},
                activity_modifiers = {}, effects = {},
                bounds = { min = vector(row.bounds_min_x, row.bounds_min_y, row.bounds_min_z),
                    max = vector(row.bounds_max_x, row.bounds_max_y, row.bounds_max_z) },
            }
            for _, name in ipairs(row.activity_modifiers or {}) do
                entry.activity_modifiers[#entry.activity_modifiers + 1] = {
                    modifier_name = name, enabled = true,
                }
            end
            built[key], by_id[row.visual_id] = entry, entry
            add_resource(row.model_path)
        end
    end
    for slot = 1, 50 do
        for round = 1, 4 do
            assert(built[slot .. ":" .. round], "endless_visual_cycle_incomplete")
        end
    end
    for _, component in ipairs(components.rows) do
        if component.enabled ~= false then
            local entry = assert(by_id[component.visual_id], "endless_component_visual_missing")
            assert(component.attach_mode == "bone_merge", "endless_component_attachment_invalid")
            entry.components[#entry.components + 1] = component
            add_resource(component.model_path)
        end
    end
    for _, ornament in ipairs(ornaments.rows) do
        if ornament.enabled ~= false then
            local entry = assert(by_id[ornament.visual_id], "endless_ornament_visual_missing")
            local scale = tonumber(ornament.model_scale)
            assert(scale and scale > 0, "endless_ornament_scale_invalid")
            entry.ornaments[#entry.ornaments + 1] = {
                ornament_id = ornament.ornament_id, model_path = ornament.model_path,
                attachment = ornament.attachment or "",
                local_origin = vector(ornament.local_x, ornament.local_y, ornament.local_z),
                root_origin = vector(ornament.root_x, ornament.root_y, ornament.root_z),
                local_angles = { pitch = tonumber(ornament.angle_pitch) or 0,
                    yaw = tonumber(ornament.angle_yaw) or 0,
                    roll = tonumber(ornament.angle_roll) or 0 },
                model_scale = scale,
            }
            add_resource(ornament.model_path)
        end
    end
    table.sort(listed, function(a, b) return a.path < b.path end)
    templates, resolved, resources = built, {}, listed
end

function M.resolve(wave)
    wave = tonumber(wave)
    if not wave or wave < 1 or wave ~= math.floor(wave) then
        return nil, "endless_visual_wave_invalid"
    end
    initialize()
    local slot = (wave - 1) % 50 + 1
    local round = math.floor((wave - 1) / 50) % 4 + 1
    local multiplier = wave <= 200 and 1 or 1.5
    local key = slot .. ":" .. round .. ":" .. multiplier
    if not resolved[key] then
        local template = templates[slot .. ":" .. round]
        local value = {}
        for field, data in pairs(template) do value[field] = data end
        value.model_scale = template.base_scale * multiplier
        value.size_multiplier = multiplier
        resolved[key] = value
    end
    return resolved[key]
end

-- Standalone props must be loaded with the engine's real Precache(context),
-- not an opaque runtime context or an unrelated hero's async outfit proxy.
function M.resources()
    initialize()
    return resources
end

return M
