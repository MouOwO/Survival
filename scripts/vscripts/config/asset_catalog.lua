local generated = require("config/generated/asset_catalog")

local M = {
    rows = generated.rows or {},
    by_id = generated.by_id or {},
    by_model = {},
    by_particle = {},
}

for _, row in ipairs(M.rows) do
    if type(row.primary_model) == "string" and row.primary_model ~= ""
        and M.by_model[row.primary_model] == nil then
        M.by_model[row.primary_model] = row
    end
end

for _, row in ipairs(M.rows) do
    for _, particle_path in ipairs(row.particle_resources or {}) do
        if M.by_particle[particle_path] == nil then
            M.by_particle[particle_path] = row
        end
    end
end

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

function M.get(asset_id)
    local row = M.by_id[tostring(asset_id or "")]
    if row and row.enabled ~= false then
        return row
    end
    return nil
end

function M.resolve(asset_id)
    local visited = {}
    local current_id = tostring(asset_id or "")
    while nonempty(current_id) and not visited[current_id] do
        visited[current_id] = true
        local row = M.by_id[current_id]
        if row and row.enabled ~= false and nonempty(row.primary_model) then
            return row
        end
        current_id = row and row.fallback_asset_id or ""
    end
    return nil
end

function M.model(asset_id, fallback_path)
    local row = M.resolve(asset_id)
    if row and nonempty(row.primary_model) then
        return row.primary_model, row
    end
    return fallback_path, nil
end

function M.for_model(model_path)
    return M.by_model[tostring(model_path or "")]
end

function M.for_particle(particle_path)
    return M.by_particle[tostring(particle_path or "")]
end

function M.group(load_group)
    local result = {}
    for _, row in ipairs(M.rows) do
        if row.enabled ~= false and row.load_group == load_group then
            table.insert(result, row)
        end
    end
    table.sort(result, function(a, b)
        local a_order = tonumber(a.load_order) or math.huge
        local b_order = tonumber(b.load_order) or math.huge
        if a_order ~= b_order then return a_order < b_order end
        local a_priority = tonumber(a.priority) or 0
        local b_priority = tonumber(b.priority) or 0
        if a_priority ~= b_priority then return a_priority > b_priority end
        return tostring(a.asset_id) < tostring(b.asset_id)
    end)
    return result
end

return M