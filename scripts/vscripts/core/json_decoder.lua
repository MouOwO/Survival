local M = {}
M.null = {}

local function decode_error(text, index, message)
    error("json decode error at " .. tostring(index) .. ": " .. message
        .. " near " .. string.sub(text, index, index + 20), 0)
end

local function skip_space(text, index)
    while true do
        local char = string.sub(text, index, index)
        if char ~= " " and char ~= "\t" and char ~= "\r" and char ~= "\n" then
            return index
        end
        index = index + 1
    end
end

local escapes = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
    ["b"] = "\b", ["f"] = "\f", ["n"] = "\n",
    ["r"] = "\r", ["t"] = "\t",
}

local function utf8_from_codepoint(value)
    if value <= 0x7F then
        return string.char(value)
    end
    if value <= 0x7FF then
        return string.char(
            0xC0 + math.floor(value / 0x40),
            0x80 + (value % 0x40)
        )
    end
    if value <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(value / 0x1000),
            0x80 + (math.floor(value / 0x40) % 0x40),
            0x80 + (value % 0x40)
        )
    end
    return string.char(
        0xF0 + math.floor(value / 0x40000),
        0x80 + (math.floor(value / 0x1000) % 0x40),
        0x80 + (math.floor(value / 0x40) % 0x40),
        0x80 + (value % 0x40)
    )
end

local parse_value

local function parse_string(text, index)
    local parts = {}
    index = index + 1
    local start = index
    while index <= #text do
        local char = string.sub(text, index, index)
        if char == '"' then
            parts[#parts + 1] = string.sub(text, start, index - 1)
            return table.concat(parts), index + 1
        end
        if char == "\\" then
            parts[#parts + 1] = string.sub(text, start, index - 1)
            local escaped = string.sub(text, index + 1, index + 1)
            if escaped == "u" then
                local hex = string.sub(text, index + 2, index + 5)
                if not string.match(hex, "^%x%x%x%x$") then
                    decode_error(text, index, "invalid unicode escape")
                end
                local codepoint = tonumber(hex, 16)
                index = index + 6
                if codepoint >= 0xD800 and codepoint <= 0xDBFF then
                    if string.sub(text, index, index + 1) ~= "\\u" then
                        decode_error(text, index, "high surrogate without low surrogate")
                    end
                    local low_hex = string.sub(text, index + 2, index + 5)
                    local low = tonumber(low_hex, 16)
                    if low == nil or low < 0xDC00 or low > 0xDFFF then
                        decode_error(text, index, "invalid low surrogate")
                    end
                    codepoint = 0x10000 + (codepoint - 0xD800) * 0x400
                        + (low - 0xDC00)
                    index = index + 6
                elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
                    decode_error(text, index, "unexpected low surrogate")
                end
                parts[#parts + 1] = utf8_from_codepoint(codepoint)
            else
                local decoded = escapes[escaped]
                if decoded == nil then
                    decode_error(text, index, "invalid escape")
                end
                parts[#parts + 1] = decoded
                index = index + 2
            end
            start = index
        elseif string.byte(char) < 32 then
            decode_error(text, index, "control character in string")
        else
            index = index + 1
        end
    end
    decode_error(text, index, "unterminated string")
end

local function parse_number(text, index)
    local finish = index
    while string.match(string.sub(text, finish, finish), "[-+0-9.eE]") do
        finish = finish + 1
    end
    local raw = string.sub(text, index, finish - 1)
    if not string.match(raw, "^-?%d+%.?%d*[eE]?[-+]?%d*$") then
        decode_error(text, index, "invalid number")
    end
    local mantissa, exponent = string.match(raw, "^([^eE]+)([eE].+)$")
    mantissa = mantissa or raw
    local mantissa_ok = string.match(mantissa, "^-?0$")
        or string.match(mantissa, "^-?[1-9]%d*$")
        or string.match(mantissa, "^-?0%.%d+$")
        or string.match(mantissa, "^-?[1-9]%d*%.%d+$")
    local exponent_ok = exponent == nil
        or string.match(exponent, "^[eE][-+]?%d+$")
    if not mantissa_ok or not exponent_ok then
        decode_error(text, index, "invalid number")
    end
    local value = tonumber(raw)
    if value == nil then
        decode_error(text, index, "invalid number")
    end
    return value, finish
end

local function parse_array(text, index)
    local result = {}
    index = skip_space(text, index + 1)
    if string.sub(text, index, index) == "]" then
        return result, index + 1
    end
    while true do
        local value
        value, index = parse_value(text, index)
        result[#result + 1] = value
        index = skip_space(text, index)
        local char = string.sub(text, index, index)
        if char == "]" then
            return result, index + 1
        end
        if char ~= "," then
            decode_error(text, index, "expected array comma")
        end
        index = skip_space(text, index + 1)
    end
end

local function parse_object(text, index)
    local result = {}
    index = skip_space(text, index + 1)
    if string.sub(text, index, index) == "}" then
        return result, index + 1
    end
    while true do
        if string.sub(text, index, index) ~= '"' then
            decode_error(text, index, "expected object key")
        end
        local key
        key, index = parse_string(text, index)
        index = skip_space(text, index)
        if string.sub(text, index, index) ~= ":" then
            decode_error(text, index, "expected object colon")
        end
        if result[key] ~= nil then
            decode_error(text, index, "duplicate object key: " .. key)
        end
        local value
        value, index = parse_value(text, skip_space(text, index + 1))
        result[key] = value
        index = skip_space(text, index)
        local char = string.sub(text, index, index)
        if char == "}" then
            return result, index + 1
        end
        if char ~= "," then
            decode_error(text, index, "expected object comma")
        end
        index = skip_space(text, index + 1)
    end
end

parse_value = function(text, index)
    index = skip_space(text, index)
    local char = string.sub(text, index, index)
    if char == '"' then
        return parse_string(text, index)
    end
    if char == "{" then
        return parse_object(text, index)
    end
    if char == "[" then
        return parse_array(text, index)
    end
    if char == "-" or string.match(char, "%d") then
        return parse_number(text, index)
    end
    if string.sub(text, index, index + 3) == "true" then
        return true, index + 4
    end
    if string.sub(text, index, index + 4) == "false" then
        return false, index + 5
    end
    if string.sub(text, index, index + 3) == "null" then
        return M.null, index + 4
    end
    decode_error(text, index, "unexpected token")
end

function M.decode(text)
    if type(text) ~= "string" then
        error("json text must be a string", 0)
    end
    local value, index = parse_value(text, 1)
    index = skip_space(text, index)
    if index <= #text then
        decode_error(text, index, "trailing content")
    end
    return value
end

return M
