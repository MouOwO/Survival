-- Backend-only wrapper. Execute the immutable bundle's original worker unchanged.
-- The request contains no configs. Static modules are private compiled chunks;
-- only modules actually required by the original settlement are constructed.
package.path="./?.lua"
local load,run=loadfile,dofile
local cache=assert(arg[1],"worker_cache_required")
local base=assert(cache:match("^(.*)[/\\][^/\\]+$"),"worker_cache_path_invalid")
local index=assert(load(cache))()
for name,token in pairs(index) do
    assert(type(name)=="string" and name:match("^[a-z][a-z0-9_]*$")
        and type(token)=="string" and #token==64 and token:match("^[a-f0-9]+$"),"worker_cache_index_invalid")
    local path=base.."/"..token..".luac"
    package.preload["config/generated/"..name]=function()
        local config=assert(load(path))()
        local module={rows=config.rows,by_id={}}
        for _,row in ipairs(config.rows) do module.by_id[row[config.key]]=row end
        return module
    end
end
local decoder=require("core/json_decoder")
local original=decoder.decode
decoder.decode=function(text)
    decoder.decode=original
    local input=original(text)
    assert(type(input)=="table" and input.configs==nil,"worker_configs_override")
    input.configs={}
    return input
end
run("worker.lua")
