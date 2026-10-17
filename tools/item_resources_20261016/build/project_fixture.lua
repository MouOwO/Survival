-- Read-only production projection with explicit synthetic ownership.
package.path = "scripts/vscripts/?.lua;" .. package.path
local json = require("core/json_encoder")
local catalog = require("config/generated/archive_commerce_goods")
local project = require("systems/archive_commerce_goods").project
local resources = require("config/generated/item_resources")
local profile = {save={content_inventory={},archive={vip_claimed={}},gameplay_stats={starjoy_reward_level=0}}}
for _, item in ipairs(catalog.rows) do
    if item.kind == "product" then profile.save.content_inventory[item.ownership_id] = 1 end
end
local output = assert(io.open(assert(arg[1], "Output fixture path required"), "wb"))
output:write(json.encode({rows=project(profile),resource_source_hash=resources.source_hash,scope="Synthetic ownership only, formal production metadata; no save writes"}))
output:close()
