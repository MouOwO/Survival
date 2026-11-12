-- Authenticated HTTP representation only; no persistence or cross-reply cache.
-- The encrypted public catalogue is loaded/indexed once, O(catalogue bytes).
-- Idle/header lookup is O(1). A reply costs O(encoded/expanded bytes plus
-- sum(K log K) for K keys per object), bounded by 100000 nodes, depth 64 and
-- 4096 completed references. No timer, scene,
-- native, network or database calls are added. Defaults describe a complete
-- object, never an incremental patch; absent false/0/null is reconstructed.
local null = require('core/json_decoder').null
local M = {}
local MAX_NODES, MAX_DEPTH, MAX_REFS = 100000, 64, 4096
local MAX_BYTES = 8 * 1024 * 1024
local catalog, fields, symbols, templates, field_index
local function need(ok) if not ok then error('business_wire_invalid', 0) end end
local function object(value) return type(value) == 'table' and value ~= null end
local function integer(value, low, high)
    return type(value) == 'number' and value == value and value == math.floor(value)
        and value >= low and value <= high
end
local function array_size(value, maximum)
    need(object(value))
    local count, last = 0, 0
    for key in pairs(value) do
        need(integer(key, 1, maximum)); count = count + 1; last = math.max(last, key)
    end
    need(count == last and count <= maximum)
    return count
end
local function scalar(value)
    local kind = type(value)
    return value == null or kind == 'string' or kind == 'boolean'
        or kind == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end
local function byte_less(left, right)
    for index = 1, math.min(#left, #right) do
        local a, b = left:byte(index), right:byte(index)
        if a ~= b then return a < b end
    end
    return #left < #right
end
local function load_catalog()
    local supplied = require('config/generated/business_wire_catalog')
    need(object(supplied) and type(supplied.hash) == 'string' and #supplied.hash == 64
        and supplied.hash:match('^[0-9a-f]+$'))
    local schema = supplied.schema
    need(object(schema) and schema.version == 1)
    local field_count = array_size(schema.fields, 4096)
    local symbol_count = array_size(schema.symbols, 16384)
    local template_count = array_size(schema.templates, 512)
    need(field_count > 0)
    local by_field, seen_symbols, indexed_templates = {}, {}, {}
    for index = 1, field_count do
        local name = schema.fields[index]
        need(type(name) == 'string' and #name > 0 and #name <= 256 and not by_field[name])
        by_field[name] = index
    end
    for index = 1, symbol_count do
        local name = schema.symbols[index]
        need(type(name) == 'string' and #name <= 4096 and not seen_symbols[name])
        seen_symbols[name] = true
    end
    local template_names, default_count = {}, 0
    for index = 1, template_count do
        local entry = schema.templates[index]
        need(object(entry) and type(entry.name) == 'string' and #entry.name > 0
            and #entry.name <= 256 and not template_names[entry.name] and object(entry.defaults))
        local defaults, allowed = {}, {}
        for key, value in pairs(entry.defaults) do
            need(type(key) == 'string' and #key <= 256 and scalar(value))
            default_count = default_count + 1; need(default_count <= MAX_NODES)
            defaults[key], allowed[key] = value, true
        end
        indexed_templates[index] = {defaults = defaults, allowed = allowed}
        template_names[entry.name] = true
    end
    catalog, fields, symbols, templates, field_index = supplied, schema.fields,
        schema.symbols, indexed_templates, by_field
end
-- Missing/corrupt catalogue disables negotiation; legacy JSON remains usable.
if not pcall(load_catalog) then catalog, fields, symbols, templates, field_index = nil, nil, nil, nil, nil end

function M.schema_hash() return catalog and catalog.hash or nil end

function M.decode(value)
    if not object(value) then return nil, 'business_wire_invalid' end
    if value._bw == nil then return value end
    local ok, result = pcall(function()
        need(catalog ~= nil)
        for key in pairs(value) do need(key == '_bw') end
        local envelope = value._bw
        need(array_size(envelope, 3) == 3 and envelope[1] == 1 and envelope[2] == catalog.hash)
        local encoded_nodes, expanded_nodes, expanded_bytes, definitions = 0, 0, 0, {}
        local function bytes(count)
            expanded_bytes = expanded_bytes + count; need(expanded_bytes <= MAX_BYTES)
        end
        local function quoted_size(text)
            local size = #text + 2
            for index = 1, #text do
                local byte = text:byte(index)
                if byte == 34 or byte == 92 or byte == 8 or byte == 9 or byte == 10
                    or byte == 12 or byte == 13 then size = size + 1
                elseif byte < 32 then size = size + 5 end
                need(size <= MAX_BYTES)
            end
            return size
        end
        local function expansion(value)
            expanded_nodes = expanded_nodes + 1; need(expanded_nodes <= MAX_NODES)
            if value == nil or object(value) then bytes(2)
            elseif value == null then bytes(4)
            elseif type(value) == 'string' then bytes(quoted_size(value))
            elseif type(value) == 'boolean' then bytes(value and 4 or 5)
            else bytes(#tostring(value)) end
        end
        local function clone(source, depth)
            need(depth <= MAX_DEPTH); expansion(source)
            if not object(source) then need(scalar(source)); return source end
            local copy, count = {}, 0
            for key, child in pairs(source) do
                if count > 0 then bytes(1) end
                count = count + 1
                if type(key) == 'string' then bytes(quoted_size(key) + 1) end
                copy[key] = clone(child, depth + 1)
            end
            return copy
        end
        local function key_name(key)
            need(type(key) == 'string')
            if key:sub(1, 1) == '~' then
                local raw = key:sub(2)
                need(raw:sub(1, 1) == '~' or raw:sub(1, 1) == '@' or raw:match('^[0-9]+$'))
                return raw
            end
            if key:sub(1, 1) == '@' then
                local digits = key:sub(2)
                need(digits:match('^[1-9][0-9]*$') and #digits <= 5)
                local index = tonumber(digits)
                need(integer(index, 1, #symbols) and tostring(index) == digits)
                return symbols[index]
            end
            if key:match('^[0-9]+$') then
                need(key:match('^[1-9][0-9]*$') and #key <= 4)
                local index = tonumber(key)
                need(integer(index, 1, #fields) and tostring(index) == key)
                return fields[index]
            end
            need(field_index[key] == nil)
            return key
        end
        local decode
        local function decode_object(source, depth, template)
            need(object(source))
            local copy, seen = {}, {}
            if template then
                for key, default in pairs(template.defaults) do copy[key] = default end
            end
            -- JSON object order is lost in Lua tables. Both encoders and
            -- decoders therefore traverse encoded keys in UTF-8 byte order,
            -- so completed definitions always precede their references.
            local keys = {}
            for key in pairs(source) do
                need(type(key) == 'string' and #keys < MAX_NODES)
                keys[#keys + 1] = key
            end
            table.sort(keys, byte_less)
            for _, key in ipairs(keys) do
                local child = source[key]
                local name = key_name(key)
                need(not seen[name] and (not template or template.allowed[name]))
                seen[name] = true
                copy[name] = decode(child, depth + 1)
            end
            local count = 0
            for name, child in pairs(copy) do
                if template and not seen[name] then expansion(child) end
                if count > 0 then bytes(1) end
                bytes(quoted_size(name) + 1); count = count + 1
            end
            return copy
        end
        decode = function(source, depth)
            need(depth <= MAX_DEPTH)
            encoded_nodes = encoded_nodes + 1; need(encoded_nodes <= MAX_NODES)
            if not object(source) then expansion(source); need(scalar(source)); return source end
            if type(source[1]) ~= 'number' then expansion(); return decode_object(source, depth) end
            local length = array_size(source, MAX_NODES + 1)
            local tag = source[1]
            if tag == 0 then
                expansion()
                local copy = {}
                bytes(math.max(0, length - 2))
                for index = 2, length do copy[index - 1] = decode(source[index], depth + 1) end
                return copy
            elseif tag == 1 then
                need(length == 2 and integer(source[2], 1, #symbols))
                expansion(symbols[source[2]]); return symbols[source[2]]
            elseif tag == 2 then
                need(length == 3 and integer(source[2], 1, #templates))
                expansion()
                return decode_object(source[3], depth, templates[source[2]])
            elseif tag == 3 then
                need(length == 2 and integer(source[2], 1, MAX_REFS) and definitions[source[2]] ~= nil)
                return clone(definitions[source[2]], depth)
            elseif tag == 4 then
                local id = source[2]
                need(length == 3 and integer(id, 1, MAX_REFS) and definitions[id] == nil)
                local decoded = decode(source[3], depth + 1)
                -- Register only a completely decoded definition; references
                -- cannot point forward, form cycles, or share mutable results.
                need(definitions[id] == nil)
                definitions[id] = decoded
                return decoded
            end
            need(false)
        end
        local decoded = decode(envelope[3], 0)
        need(object(decoded))
        for key in pairs(decoded) do need(type(key) == 'string') end
        return decoded
    end)
    if not ok then return nil, 'business_wire_invalid' end
    return result
end
return M
