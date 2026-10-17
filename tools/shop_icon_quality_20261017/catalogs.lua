-- Read-only full real shop catalog; JSON array fields used by the audit only.
package.path = "scripts/vscripts/?.lua;" .. package.path
local catalog = require("systems/shop_catalog")
local function quote(value)
    return '"' .. tostring(value or ''):gsub('\\', '\\\\'):gsub('"', '\\"')
        :gsub('\r', '\\r'):gsub('\n', '\\n'):gsub('\t', '\\t') .. '"'
end
local keys = {'entryid','contentid','name','contenttype','icon','icon_type','shopid'}
local result = {}
for _, entry in ipairs(catalog.entries()) do
    local row = {}
    for _, key in ipairs(keys) do row[#row+1] = quote(key) .. ':' .. quote(entry[key]) end
    row[#row+1] = '"in_shop":' .. tostring(catalog.allowed_in_mode(entry, 'shop') == true)
    row[#row+1] = '"in_research":' .. tostring(catalog.allowed_in_mode(entry, 'research') == true)
    row[#row+1] = '"in_challenge":' .. tostring(catalog.allowed_in_mode(entry, 'challenge') == true)
    result[#result+1] = '{' .. table.concat(row, ',') .. '}'
end
io.write('[' .. table.concat(result, ',') .. ']')
