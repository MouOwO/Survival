-- Small static ornaments follow a parent transform; they never borrow a
-- different creature's skeleton or run a positioning timer.
local model_scale = require("visual/model_scale")
local M = {}
local STATE_KEY = "survival_endless_monster_ornaments_state"
local GENERATION_KEY = "survival_endless_monster_ornaments_generation"

local function valid(entity)
    if not entity then return false end
    if type(entity.IsNull) == "function" and entity:IsNull() then return false end
    if type(IsValidEntity) == "function" then
        local ok, result = pcall(IsValidEntity, entity)
        if ok and result == false then return false end
    end
    return true
end

local function call(entity, method, ...)
    if not entity or type(entity[method]) ~= "function" then return false end
    local ok, result = pcall(entity[method], entity, ...)
    return ok and result ~= false, result
end

local function remove(parts)
    for _, part in ipairs(parts or {}) do
        if valid(part) then
            local removed = false
            if type(UTIL_Remove) == "function" then
                removed = pcall(UTIL_Remove, part)
            end
            if not removed then call(part, "RemoveSelf") end
        end
    end
end

local function owned_state(unit)
    local state = unit and unit[STATE_KEY]
    return state and state.owner == unit and state or nil
end

function M.clear(unit)
    if not unit then return true end
    unit[GENERATION_KEY] = (tonumber(unit[GENERATION_KEY]) or 0) + 1
    local state = owned_state(unit)
    if state then
        unit[STATE_KEY] = nil
        remove(state.parts)
    end
    return true
end

local function number(value, default)
    if value == nil then return default end
    local parsed = tonumber(value)
    if not parsed or parsed ~= parsed or parsed == math.huge or parsed == -math.huge then
        return nil
    end
    return parsed
end

local function triple(value, names)
    value = value or {}
    if type(value) ~= "table" and type(value) ~= "userdata" then return nil end
    local result = {}
    for index, name in ipairs(names) do
        result[index] = number(value[index] or value[name], 0)
        if result[index] == nil then return nil end
    end
    return result
end

local function root_origin(visual, entry)
    if entry.root_origin then return triple(entry.root_origin, { "x", "y", "z" }) end
    local bounds = visual.bounds
    if bounds and bounds.min and bounds.max then
        local low = triple(bounds.min, { "x", "y", "z" })
        local high = triple(bounds.max, { "x", "y", "z" })
        if not low or not high then return nil end
        return { (low[1] + high[1]) / 2, (low[2] + high[2]) / 2, high[3] }
    end
    return triple(entry.local_origin, { "x", "y", "z" })
end

local function attachment_exists(unit, name)
    if name == "" then return true end
    for _, method in ipairs({ "ScriptLookupAttachment", "LookupAttachment" }) do
        local ok, index = call(unit, method, name)
        if ok and tonumber(index) and tonumber(index) > 0 then return true end
    end
    return false
end

local function normalized(unit, visual)
    local scale = number(visual.model_scale, 1)
    if not scale or scale <= 0 then return nil, "invalid_model_scale" end
    scale = model_scale.value(unit, scale)
    local entries, signature = {}, { tostring(scale) }
    for index, entry in ipairs(visual.ornaments or {}) do
        if type(entry) ~= "table" or type(entry.model_path) ~= "string"
            or entry.model_path == "" then return nil, "invalid_ornament_model" end
        local attachment = tostring(entry.attachment or "")
        local origin = triple(entry.local_origin, { "x", "y", "z" })
        local angles = triple(entry.local_angles, { "pitch", "yaw", "roll" })
        local local_scale = number(entry.model_scale, 1)
        if not attachment_exists(unit, attachment) then
            attachment = ""
            origin = root_origin(visual, entry)
            -- The local angles may compensate for the attachment's rotated
            -- bind pose. That compensation is wrong on the root transform.
            angles = triple(entry.root_angles, { "pitch", "yaw", "roll" })
        end
        if not origin or not angles or not local_scale or local_scale <= 0 then
            return nil, "invalid_ornament_transform"
        end
        -- Coordinates and prop size are supplied in the unscaled body space.
        -- Explicit scaling also covers root-parented props without a bone pose.
        local transform = {
            model_path = entry.model_path, attachment = attachment,
            origin = { origin[1] * scale, origin[2] * scale, origin[3] * scale },
            angles = angles, scale = local_scale * scale,
        }
        entries[index] = transform
        signature[#signature + 1] = table.concat({
            transform.model_path, attachment,
            tostring(transform.origin[1]), tostring(transform.origin[2]), tostring(transform.origin[3]),
            tostring(angles[1]), tostring(angles[2]), tostring(angles[3]), tostring(transform.scale),
        }, "\31")
    end
    return entries, table.concat(signature, "\30")
end

local function intact(state)
    for _, part in ipairs(state.parts) do
        if not valid(part) then return false end
    end
    return true
end

function M.apply(unit, visual)
    if not valid(unit) then
        M.clear(unit)
        return false, "invalid_unit"
    end
    if type(unit.IsAlive) == "function" and not unit:IsAlive() then
        M.clear(unit)
        return false, "unit_dead"
    end
    if type(visual) ~= "table" then return false, "visual_missing" end
    if visual.ornaments ~= nil and type(visual.ornaments) ~= "table" then
        return false, "ornaments_invalid"
    end
    if not visual.ornaments or #visual.ornaments == 0 then
        M.clear(unit)
        return true, "no_ornaments"
    end
    local entries, signature = normalized(unit, visual)
    if not entries then return false, signature end
    local previous = owned_state(unit)
    if previous and previous.signature == signature and intact(previous) then
        return true, "unchanged", previous.parts
    end
    if type(SpawnEntityFromTableSynchronous) ~= "function" or type(Vector) ~= "function" then
        return false, "spawn_api_missing"
    end
    local generation = (tonumber(unit[GENERATION_KEY]) or 0) + 1
    unit[GENERATION_KEY] = generation
    local parts = {}
    local function abandon(reason)
        remove(parts)
        return false, reason
    end
    for _, entry in ipairs(entries) do
        local ok, part = pcall(SpawnEntityFromTableSynchronous, "prop_dynamic", {
            model = entry.model_path, solid = "0", spawnflags = "256",
            DisableBoneFollowers = "1", disableshadows = "1", origin = "0 0 -2048",
        })
        if not ok or not valid(part) then return abandon("ornament_spawn_failed") end
        parts[#parts + 1] = part
        -- This final size was calculated in the owner's scale context. Props
        -- have no NPC name, so preserve that context when recording the base.
        part.survival_visual_scale_exempt = model_scale.factor(unit) == 1
        if not call(part, "SetOwner", unit)
            or not call(part, "SetParent", unit, entry.attachment)
            or not call(part, "SetLocalOrigin", Vector(unpack(entry.origin)))
            or not call(part, "SetLocalAngles", unpack(entry.angles))
            or not model_scale.copy_final(part, entry.scale) then
            return abandon("ornament_attach_failed")
        end
        if unit[GENERATION_KEY] ~= generation then return abandon("superseded") end
        if not valid(unit) or type(unit.IsAlive) == "function" and not unit:IsAlive() then
            M.clear(unit)
            return abandon("unit_dead")
        end
        part.survival_is_endless_monster_ornament = true
        part.survival_endless_monster_ornament_owner = unit
    end
    unit[STATE_KEY] = { owner = unit, signature = signature, parts = parts }
    remove(previous and previous.parts)
    return true, "applied", parts
end

return M
