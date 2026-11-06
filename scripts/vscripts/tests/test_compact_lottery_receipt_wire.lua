-- Offline cross-language vectors supplied by the Node production-code test.
package.path='scripts/vscripts/?.lua;'..package.path
local f=assert(io.open(assert(arg[1]),'rb'))
local data=require('core/json_decoder').decode(f:read('*a'));f:close()
local lookup=assert(loadfile('scripts/vscripts/config/generated/ui_static_catalog_lookup.lua'))()
lookup.lottery_receipt=data.seed
local codec=require('ui/compact_lottery_receipt_wire').Create(lookup)
for _,vector in ipairs(data.vectors)do
 local raw=codec.Encode(vector.view,vector.revision,vector.receipt,vector.changes)
 local hex=raw:gsub('.',function(c)return string.format('%02x',string.byte(c))end)
 assert(hex==vector.hex,'production Lua/JS bytes differ')
end
assert(codec.Inspect().steady_registry_visits==0)
print('PRODUCTION_LOTTERY_RECEIPT_LUA_PARITY_PASS '..#data.vectors)
