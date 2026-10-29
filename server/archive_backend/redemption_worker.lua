-- The worker executes only installed reducer files and immutable bundle sources.
package.path = "./?.lua"
local input = require("core/json_decoder").decode(io.read("*a"))
for name, config in pairs(input.configs) do
    local module = { rows=config.rows, by_id={} }
    for _, row in ipairs(config.rows) do module.by_id[row[config.key]] = row end
    package.loaded["config/generated/"..name] = module
end
local products = assert(input.command.rewards.products)
local catalog = {rows=products,by_id={}}
for _, row in ipairs(products) do catalog.by_id[row.sku] = row end
package.loaded["config/generated/commerce_catalog"] = catalog
local reducer = assert(loadfile(assert(arg[1])))()
local encode, write = require("core/json_encoder").encode, io.write
io=nil;os=nil;dofile=nil;loadfile=nil;loadstring=nil;debug=nil
local ok, result = pcall(reducer.settle, input.profile, input.command)
if not ok then result={ok=false,error="redeem_rewards_pending"} end
write(encode(result))
