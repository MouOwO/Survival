-- Preserve authored proportions and gameplay geometry; scale only model output.
local M = { multiplier = 2 / 3 }
local original_size_ids = { arrow_tower = true, building_arrow_tower = true, ultimate_tower = true, wall = true, building_wall = true }
local original_size_names = { building_arrow_tower = true, npc_dota_unit_ultimate_tower = true, building_wall = true }

local function monster_name(name)
    return type(name) == "string" and (name:match("^npc_survival_wave_")
        or name:match("^npc_survival_named_")) ~= nil
end

local function hero(entity)
    if type(entity.survival_hero_id) == "string" and entity.survival_hero_id ~= "" then return true end
    if type(entity.IsHero) == "function" then
        local ok, value = pcall(entity.IsHero, entity)
        if ok and value == true then return true end
    end
    return false
end

local function valid(entity)
    return entity and (not entity.IsNull or not entity:IsNull())
end

local function number(value)
    value = tonumber(value)
    if value and value >= 0 and value < math.huge then return value end
end

local function current(entity)
    if not valid(entity) or type(entity.GetModelScale) ~= "function" then return nil end
    local ok, value = pcall(entity.GetModelScale, entity)
    return ok and number(value) or nil
end

function M.factor(entity, building_id)
    if original_size_ids[building_id] then return 1 end
    if valid(entity) then
        if original_size_ids[entity.survival_building_id] then return 1 end
        if hero(entity) then return 1 end
        if entity.survival_is_wave_monster == true or entity.survival_is_challenge_monster == true
            or entity.survival_rebirth_scene_display == true then return 1 end
        if type(entity.GetUnitName) == "function" then
            local ok, name = pcall(entity.GetUnitName, entity)
            -- The spawn event precedes monster role flags and authored scale assignment.
            if ok and (original_size_names[name] or monster_name(name)
                or type(name) == "string" and name:match("^npc_dota_hero_")) then return 1 end
        end
        -- Props and previews inherit their owner's exemption without an NPC name.
        if building_id == nil and entity.survival_visual_scale_exempt then return 1 end
    end
    return M.multiplier
end

function M.value(entity, authored_scale, building_id)
    return (number(authored_scale) or 1) * M.factor(entity, building_id)
end

local function write(entity, final_scale, factor)
    if not valid(entity) or type(entity.SetModelScale) ~= "function" then
        return false, nil, "model_scale_api_missing"
    end
    final_scale = number(final_scale)
    if not final_scale then return false, nil, "invalid_model_scale" end
    local ok, result = pcall(entity.SetModelScale, entity, final_scale)
    if not ok or result == false then return false, nil, "model_scale_set_failed" end
    entity.survival_visual_base_scale = final_scale / factor
    entity.survival_visual_scale_multiplier = factor
    entity.survival_visual_final_scale = final_scale
    entity.survival_visual_scale_exempt = factor == 1
    return true, final_scale
end

function M.apply(entity, authored_scale, building_id)
    local scale = number(authored_scale)
    if not scale then return false, nil, "invalid_model_scale" end
    local factor = M.factor(entity, building_id)
    return write(entity, scale * factor, factor)
end

-- Mirrors, moving previews and death proxies already receive the final scale.
function M.copy_final(entity, final_scale, building_id)
    return write(entity, final_scale, M.factor(entity, building_id))
end

function M.original(entity, fallback)
    local scale = current(entity)
    if scale then
        return scale / (number(entity.survival_visual_scale_multiplier) or 1)
    end
    return valid(entity) and number(entity.survival_visual_base_scale)
        or number(fallback) or 1
end

-- Cover native heroes and other NPCs without an authored scale assignment.
-- Repeated spawn events do not multiply an already scaled model again.
function M.ensure(entity)
    local scale = current(entity)
    if not scale then return false, nil, "model_scale_api_missing" end
    local previous = number(entity.survival_visual_final_scale)
    if previous and math.abs(scale - previous) <= math.max(1, math.abs(previous)) * 0.000001 then
        return true, scale
    end
    return M.apply(entity, scale)
end

return M
