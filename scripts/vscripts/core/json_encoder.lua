local M = {}

local function escape(value)
    return value:gsub('[%z\1-\31\\"]', function(character)
        local replacements = {
            ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
            ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
        }
        return replacements[character]
            or string.format("\\u%04x", string.byte(character))
    end)
end

local function array_length(value)
    local maximum = 0
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return nil
        end
        maximum = math.max(maximum, key)
        count = count + 1
    end
    if maximum ~= count then return nil end
    return maximum
end

local encode
encode = function(value, seen)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge,
            "JSON number must be finite")
        return tostring(value)
    end
    if kind == "string" then return '"' .. escape(value) .. '"' end
    assert(kind == "table", "unsupported JSON type: " .. kind)
    assert(not seen[value], "JSON cycle detected")
    seen[value] = true
    local length = array_length(value)
    local result = {}
    if length then
        for index = 1, length do result[index] = encode(value[index], seen) end
        seen[value] = nil
        return "[" .. table.concat(result, ",") .. "]"
    end
    for key, child in pairs(value) do
        assert(type(key) == "string", "JSON object key must be a string")
        result[#result + 1] = '"' .. escape(key) .. '":' .. encode(child, seen)
    end
    table.sort(result)
    seen[value] = nil
    return "{" .. table.concat(result, ",") .. "}"
end

function M.encode(value)
    return encode(value, {})
end

return M