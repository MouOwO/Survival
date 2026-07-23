local M = {}

local types = {
    ability = true, item = true, dot = true, reflection = true,
    splash = true, script = true,
}

function M.validate(request)
    if type(request) ~= "table" then return false, "invalid_request" end
    if not request.attacker or request.attacker:IsNull()
        or not request.victim or request.victim:IsNull() then
        return false, "invalid_entity"
    end
    if not types[request.source_kind] then return false, "invalid_source_kind" end
    if type(request.base_damage) ~= "number" or request.base_damage < 0 then
        return false, "invalid_base_damage"
    end
    if type(request.damage_type) ~= "number" then return false, "invalid_damage_type" end
    return true
end

function M.number(value, fallback)
    return tonumber(value) or fallback or 0
end

return M
