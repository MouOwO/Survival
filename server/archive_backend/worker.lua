-- One short-lived process per settlement. Only trusted packaged Lua is executable.
package.path = "./?.lua"
local decoder=require("core/json_decoder")
local encoder=require("core/json_encoder")
local input=decoder.decode(io.read("*a"))
for name,config in pairs(input.configs) do
    local module={rows=config.rows,by_id={}}
    for _,row in ipairs(config.rows) do module.by_id[row[config.key]]=row end
    package.loaded["config/generated/"..name]=module
end
local seed=assert(tonumber(input.seed))
RandomInt=function(a,b)
    seed=(seed*48271)%2147483647
    return a+math.floor((seed/2147483647)*(b-a+1))
end
local settlement=require("systems/archive_settlement")
-- No remote code, filesystem IO, shell execution or clock access from the settlement.
local write=io.write
io=nil;os=nil;dofile=nil;loadfile=nil;loadstring=nil;debug=nil
local ok,result=pcall(settlement.settle,input.profile,input.command,input.has_pass==true)
if not ok then result={ok=false,error="settlement_failed"} end
write(encoder.encode(result))
